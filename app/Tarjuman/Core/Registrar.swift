// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Registers ("links") this phone with a console using the 8-digit code
/// shown on the console under Remote Play > Link Device.
final class Registrar: ObservableObject {
    enum State: Equatable {
        case idle
        case working
        case success(Console)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var regist: OpaquePointer?
    private var pendingHost = ""
    private var pendingPS5 = true
    private var pendingName = ""

    func start(host: String, ps5: Bool, name: String, accountId: Data, pin: UInt32) {
        cancel()
        pendingHost = host
        pendingPS5 = ps5
        pendingName = name
        state = .working
        var acc = [UInt8](accountId.prefix(8))
        while acc.count < 8 { acc.append(0) }
        let user = Unmanaged.passUnretained(self).toOpaque()
        LogStore.shared.info("Registering with \(host)")
        regist = trjm_regist_start(host, ps5, acc, pin, { resPtr, user in
            guard let resPtr, let user else { return }
            let me = Unmanaged<Registrar>.fromOpaque(user).takeUnretainedValue()
            let r = resPtr.pointee
            let success = r.success
            let canceled = r.canceled
            let nickname = stringFromCTuple(r.server_nickname)
            let mac = dataFromCTuple(r.server_mac)
            let key = dataFromCTuple(r.regist_key)
            let morning = dataFromCTuple(r.morning)
            DispatchQueue.main.async {
                me.finish(success: success, canceled: canceled, nickname: nickname, mac: mac, key: key, morning: morning)
            }
        }, user)
        if regist == nil {
            state = .failed("ما قدرت أبدأ الربط")
        }
    }

    func cancel() {
        if let r = regist {
            regist = nil
            DispatchQueue.global().async { trjm_regist_free(r) }
        }
        if state == .working { state = .idle }
    }

    func reset() {
        cancel()
        state = .idle
    }

    private func finish(success: Bool, canceled: Bool, nickname: String, mac: Data, key: Data, morning: Data) {
        if let r = regist {
            regist = nil
            DispatchQueue.global().async { trjm_regist_free(r) }
        }
        if success {
            let name = nickname.isEmpty ? (pendingName.isEmpty ? "PS5" : pendingName) : nickname
            let console = Console(id: mac.hexString, name: name, host: pendingHost, ps5: pendingPS5,
                                  registKey: key, morning: morning)
            LogStore.shared.info("Registered with \(name)")
            state = .success(console)
        } else if canceled {
            state = .idle
        } else {
            state = .failed("فشل الربط. تأكد إن شاشة «ربط جهاز» مفتوحة في الـPS5 وإن الرمز صحيح، وإن الجوال والجهاز على نفس الشبكة.")
        }
    }
}
