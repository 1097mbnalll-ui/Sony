// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import SwiftUI
import Translation

/// Anything that can translate one subtitle line into Arabic.
///
/// Today only `AppleTranslator` (free, on device, unlimited) is active.
/// A paid provider (e.g. Claude through our own server) can be added later by
/// conforming to this protocol and registering it in `TranslationProviderID`.
protocol TranslationProvider: AnyObject {
    var id: TranslationProviderID { get }
    @MainActor func translate(_ text: String, context: TranslationContext) async throws -> String
}

struct TranslationContext {
    var speaker: String?
    var recentLines: [String]
    var gameName: String
}

enum TranslationProviderID: String, CaseIterable, Identifiable {
    case apple
    // case premium  // reserved for a future paid tier
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: return "ترجمة أبل (مجانية، على الجهاز)"
        }
    }
}

/// Apple's Translation framework. The session only lives inside a SwiftUI
/// `.translationTask`, so requests are queued here and served by that task.
@MainActor
final class AppleTranslator: ObservableObject, TranslationProvider {
    enum Availability: Equatable { case unknown, installed, needsDownload, unsupported }

    let id = TranslationProviderID.apple
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var availability: Availability = .unknown

    private let source = Locale.Language(identifier: "en")
    private let target = Locale.Language(identifier: "ar")
    private var queue: [(String, CheckedContinuation<String, Error>)] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var cache: [String: String] = [:]

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "الترجمة غير متاحة" }
    }

    /// Starts (or restarts) the translation session; may show Apple's download prompt.
    func activate() {
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: source, target: target)
        } else {
            configuration?.invalidate()
        }
        Task { await refreshAvailability() }
    }

    func refreshAvailability() async {
        let status = await LanguageAvailability().status(from: source, to: target)
        switch status {
        case .installed: availability = .installed
        case .supported: availability = .needsDownload
        case .unsupported: availability = .unsupported
        @unknown default: availability = .unknown
        }
    }

    func translate(_ text: String, context: TranslationContext) async throws -> String {
        if let hit = cache[text] { return hit }
        if availability == .unsupported { throw Failure.unavailable }
        if configuration == nil { activate() }
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.append((text, cont))
            wake()
        }
        cache[text] = result
        if cache.count > 2000 { cache.removeAll(keepingCapacity: true) }
        return result
    }

    /// Runs inside `.translationTask` for as long as the session is valid.
    func serve(_ session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            LogStore.shared.error("Translation prepare failed: \(error.localizedDescription)")
        }
        await refreshAvailability()
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                if queue.isEmpty {
                    await withCheckedContinuation { waiter = $0 }
                    continue
                }
                let (text, cont) = queue.removeFirst()
                do {
                    let response = try await session.translate(text)
                    cont.resume(returning: response.targetText)
                } catch {
                    LogStore.shared.error("Translate failed: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor in self.wake() }
        }
    }

    private func wake() {
        waiter?.resume()
        waiter = nil
    }
}
