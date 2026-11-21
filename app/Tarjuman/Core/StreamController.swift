// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import UIKit

/// Owns one Remote Play session: wakes the console, connects, decodes video.
/// The app only receives; it never sends controller input.
final class StreamController: ObservableObject {
    enum State: Equatable {
        case idle
        case waking
        case connecting
        case streaming
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var fps: Int = 0
    @Published private(set) var videoSize: String = ""
    @Published var loginPinRequested = false
    @Published var loginPinWasWrong = false

    let decoder = VideoDecoder()
    let renderer = PreviewRenderer()

    private var session: OpaquePointer?
    private var context: Unmanaged<SessionContext>?
    private var generation = 0
    private var framesThisSecond = 0
    private var statsTimer: Timer?
    private var wakeTask: Task<Void, Never>?
    private let frameLock = NSLock()

    /// Passed to C as `user`; lets late callbacks from an old session be ignored.
    final class SessionContext {
        weak var controller: StreamController?
        let generation: Int
        init(_ c: StreamController, _ g: Int) { controller = c; generation = g }
    }

    init() {
        decoder.onFrame = { [weak self] pb in
            guard let self else { return }
            self.renderer.display(pb)
            self.frameLock.lock(); self.framesThisSecond += 1; self.frameLock.unlock()
        }
    }

    var isActive: Bool {
        switch state {
        case .waking, .connecting, .streaming: return true
        default: return false
        }
    }

    /// Wakes the console if needed, then starts streaming.
    func start(console: Console, settings: AppSettings, scanner: HostScanner) {
        stop()
        let host = scanner.host(for: console.host)
        if host?.state == .standby {
            state = .waking
            LogStore.shared.info("Waking \(console.name)")
            let rc = console.registKey.withUnsafeBytes { raw in
                trjm_wakeup(console.host, raw.bindMemory(to: CChar.self).baseAddress, console.ps5)
            }
            if rc != 0 { LogStore.shared.error("Wakeup failed: \(TrjmCore.errorString(rc))") }
            scanner.addTarget(console.host)
            wakeTask = Task { @MainActor [weak self] in
                for _ in 0..<45 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, self.state == .waking else { return }
                    if scanner.host(for: console.host)?.state == .ready {
                        // Give the console a moment to bring up Remote Play.
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard self.state == .waking else { return }
                        self.connect(console: console, settings: settings)
                        return
                    }
                }
                guard let self, self.state == .waking else { return }
                self.state = .failed("الجهاز ما صحى. تأكد إن «البقاء متصلاً بالإنترنت» و«تفعيل تشغيل الـPS5 عبر الشبكة» مفعّلة في إعدادات وضع الراحة.")
            }
        } else {
            connect(console: console, settings: settings)
        }
    }

    private func connect(console: Console, settings: AppSettings) {
        generation += 1
        let codec: VideoDecoder.Codec = (settings.useHEVC && console.ps5) ? .hevc : .h264
        decoder.reset(codec: codec)
        renderer.clear()
        state = .connecting
        LogStore.shared.info("Connecting to \(console.host) \(settings.resolution)p\(settings.fps) \(codec == .hevc ? "HEVC" : "H.264")")

        var cfg = TrjmSessionConfig()
        copyData(console.registKey, into: &cfg.regist_key)
        copyData(console.morning, into: &cfg.morning)
        copyData(ConsoleStore.storedAccountId ?? Data(count: 8), into: &cfg.account_id)
        cfg.ps5 = console.ps5
        cfg.resolution = Int32(settings.resolution)
        cfg.fps = Int32(settings.fps)
        cfg.codec = codec == .hevc ? TRJM_CODEC_H265 : TRJM_CODEC_H264
        cfg.enable_audio = false

        let ctx = Unmanaged.passRetained(SessionContext(self, generation))
        var callbacks = TrjmSessionCallbacks()
        callbacks.user = ctx.toOpaque()
        callbacks.event = { type, code, msg, user in
            guard let user else { return }
            let ctx = Unmanaged<SessionContext>.fromOpaque(user).takeUnretainedValue()
            let text = msg.map { String(cString: $0) }
            DispatchQueue.main.async {
                ctx.controller?.handleEvent(type, code: Int(code), message: text, generation: ctx.generation)
            }
        }
        callbacks.video = { buf, size, _, _, user in
            guard let buf, let user else { return true }
            let ctx = Unmanaged<SessionContext>.fromOpaque(user).takeUnretainedValue()
            guard let c = ctx.controller else { return true }
            return c.decoder.decode(UnsafeBufferPointer(start: buf, count: size))
        }

        var err: Int32 = 0
        let s = console.host.withCString { hostPtr -> OpaquePointer? in
            cfg.host = hostPtr
            return trjm_session_start(&cfg, &callbacks, &err)
        }
        guard let s else {
            ctx.release()
            state = .failed("ما قدرت أبدأ الاتصال: \(TrjmCore.errorString(err))")
            return
        }
        session = s
        context = ctx
        UIApplication.shared.isIdleTimerDisabled = true
        startStats()
    }

    func stop() {
        wakeTask?.cancel()
        wakeTask = nil
        teardownSession()
        if isActive { state = .idle }
        if case .failed = state { state = .idle }
    }

    func submitLoginPin(_ pin: String) {
        loginPinRequested = false
        guard let s = session else { return }
        _ = trjm_session_set_login_pin(s, pin)
    }

    func requestKeyframe() {
        if let s = session { _ = trjm_session_request_keyframe(s) }
    }

    private func teardownSession() {
        statsTimer?.invalidate()
        statsTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        guard let s = session else { return }
        let ctx = context
        session = nil
        context = nil
        generation += 1
        DispatchQueue.global(qos: .userInitiated).async {
            trjm_session_free(s) // joins chiaki's threads; must not run on main
            ctx?.release()
        }
        fps = 0
    }

    private func handleEvent(_ type: TrjmEventType, code: Int, message: String?, generation g: Int) {
        guard g == generation else { return }
        switch type {
        case TRJM_EVENT_CONNECTED:
            LogStore.shared.info("Stream connected")
            state = .streaming
        case TRJM_EVENT_LOGIN_PIN_REQUEST:
            loginPinWasWrong = code != 0
            loginPinRequested = true
        case TRJM_EVENT_QUIT:
            LogStore.shared.info("Stream ended: \(message ?? "") (\(code))")
            teardownSession()
            if code != 0 {
                state = .failed(Self.describeQuit(code: code, message: message))
            } else {
                state = .idle
            }
        default:
            break
        }
    }

    private func startStats() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameLock.lock()
            let n = self.framesThisSecond
            self.framesThisSecond = 0
            self.frameLock.unlock()
            self.fps = n
            if let pb = self.decoder.latestFrame {
                self.videoSize = "\(CVPixelBufferGetWidth(pb))×\(CVPixelBufferGetHeight(pb))"
            }
        }
    }

    private static func describeQuit(code: Int, message: String?) -> String {
        switch code {
        case Int(TRJM_QUIT_RP_IN_USE):
            return "التشغيل عن بُعد مستخدم من جهاز ثاني."
        case Int(TRJM_QUIT_CONNECTION_REFUSED), Int(TRJM_QUIT_CTRL_CONNECTION_REFUSED):
            return "الجهاز رفض الاتصال. تأكد إنه شغّال وإن التشغيل عن بُعد مفعّل."
        case Int(TRJM_QUIT_VERSION_MISMATCH):
            return "إصدار نظام الجهاز غير مدعوم."
        case Int(TRJM_QUIT_REMOTE_DISCONNECTED):
            return "الجهاز قطع الاتصال (يمكن دخل وضع الراحة أو الشبكة ضعيفة)."
        default:
            return "انقطع الاتصال: \(message ?? "خطأ غير معروف")"
        }
    }
}
