// SPDX-License-Identifier: AGPL-3.0-only
import CoreVideo
import Foundation

/// Watches the dialogue region of the stream, and translates only when the
/// text actually changed (and has stopped changing, for typewriter subtitles).
@MainActor
final class LiveTranslator: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let speaker: String?
        let original: String
        let translated: String
    }

    enum Status: Equatable {
        case idle
        case watching
        case translating
        case error(String)
    }

    @Published private(set) var current: Line?
    @Published private(set) var history: [Line] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var isWatching = false

    let apple = AppleTranslator()
    private let speech = ArabicSpeech()
    private weak var settings: AppSettings?
    private var frameSource: (() -> CVPixelBuffer?)?

    private var loop: Task<Void, Never>?
    private var busy = false
    private var lastTranslatedKey = ""
    private var pendingKey = ""
    private let ocrQueue = DispatchQueue(label: "tarjuman.ocr", qos: .userInitiated)

    /// The active provider. A paid provider would be selected here later.
    private var provider: TranslationProvider { apple }

    func attach(settings: AppSettings, frames: @escaping () -> CVPixelBuffer?) {
        self.settings = settings
        self.frameSource = frames
    }

    /// Starts automatic watching (if the setting is on). Call when streaming starts.
    func streamStarted() {
        apple.activate()
        status = .watching
        if settings?.autoTranslate ?? true { startLoop() }
    }

    func streamStopped() {
        stopLoop()
        speech.stop()
        status = .idle
        pendingKey = ""
    }

    func setAuto(_ on: Bool) {
        guard status != .idle else { return }
        if on { startLoop() } else { stopLoop() }
    }

    /// "ترجم الحين": reads once and translates even if the text looks unchanged.
    func translateNow() {
        Task { await readOnce(force: true) }
    }

    func speakCurrent() {
        if let t = current?.translated { speech.speak(t) }
    }

    func clearHistory() {
        history.removeAll()
        current = nil
    }

    // MARK: - loop

    private func startLoop() {
        guard loop == nil else { return }
        isWatching = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readOnce(force: false)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
        isWatching = false
    }

    private func readOnce(force: Bool) async {
        guard !busy, let frame = frameSource?(), let settings else { return }
        busy = true
        defer { busy = false }

        let region = settings.region
        let lines: [String] = await withCheckedContinuation { cont in
            ocrQueue.async { cont.resume(returning: TextReader.read(frame, region: region)) }
        }
        let parsed = SpeakerParser.parse(lines)
        let key = Self.normalize(parsed.text)
        guard key.count >= 2 else {
            pendingKey = ""
            if force { status = .error("ما لقيت نص في المنطقة المحددة") }
            return
        }

        if !force {
            if key == lastTranslatedKey || Self.similarity(key, lastTranslatedKey) > 0.88 { return }
            // Wait until the same text is read twice in a row (typewriter effect).
            if key != pendingKey {
                pendingKey = key
                return
            }
        }
        lastTranslatedKey = key
        await translate(parsed)
    }

    private func translate(_ parsed: SpeakerParser.Parsed) async {
        status = .translating
        let context = TranslationContext(
            speaker: parsed.speaker,
            recentLines: ([current].compactMap { $0 } + Array(history.prefix(4))).map(\.original),
            gameName: settings?.gameName ?? "")
        do {
            let arabic = try await provider.translate(parsed.text, context: context)
            let line = Line(speaker: parsed.speaker, original: parsed.text, translated: arabic)
            if let c = current {
                history.insert(c, at: 0)
                if history.count > 30 { history.removeLast(history.count - 30) }
            }
            current = line
            status = .watching
            if settings?.autoSpeak == true { speech.speak(arabic) }
        } catch {
            status = .error(apple.availability == .unsupported
                            ? "ترجمة أبل غير متاحة على هذا الجهاز"
                            : "ما قدرت أترجم. تأكد إن لغة العربي منزّلة في الترجمة.")
        }
    }

    // MARK: - text comparison

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let kept = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 1.0 = identical. Levenshtein ratio, fine for subtitle-length strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if abs(x.count - y.count) > max(x.count, y.count) / 4 { return 0 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}
