// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// In-app log so testers can copy/share what happened (no Mac, no console).
final class LogStore: ObservableObject {
    static let shared = LogStore()

    struct Line: Identifiable {
        let id: Int
        let date: Date
        let level: Int // 0 debug, 1 info, 2 warning, 3 error
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private var pending: [Line] = []
    private var counter = 0
    private var flushScheduled = false
    private let lock = NSLock()
    private let maxLines = 3000

    func append(level: Int, _ text: String) {
        lock.lock()
        counter += 1
        pending.append(Line(id: counter, date: Date(), level: level, text: text))
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.flush() }
        }
    }

    func info(_ text: String) { append(level: 1, text) }
    func error(_ text: String) { append(level: 3, text) }

    private func flush() {
        lock.lock()
        let new = pending
        pending.removeAll()
        flushScheduled = false
        lock.unlock()
        lines.append(contentsOf: new)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    func clear() { lines.removeAll() }

    var exportText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        let tags = ["D", "I", "W", "E"]
        return lines.map { "\(f.string(from: $0.date)) [\(tags[min(max($0.level, 0), 3)])] \($0.text)" }
            .joined(separator: "\n")
    }
}
