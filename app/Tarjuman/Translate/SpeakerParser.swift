// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Splits "NAME: line" style subtitles into speaker + text, without any AI.
enum SpeakerParser {
    struct Parsed: Equatable {
        var speaker: String?
        var text: String
    }

    private static let inline = try! NSRegularExpression(
        pattern: #"^\s*([A-Z][A-Za-z0-9 .'\-]{0,24}?)\s*[:：]\s*(.+)$"#)

    static func parse(_ lines: [String]) -> Parsed {
        var lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return Parsed(speaker: nil, text: "") }

        // 1) "Atsu: I won't let them..."
        let ns = first as NSString
        if let m = inline.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges == 3 {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let rest = ns.substring(with: m.range(at: 2))
            if looksLikeName(name) {
                lines[0] = rest
                return Parsed(speaker: name, text: join(lines))
            }
        }

        // 2) Name alone on the first line, dialogue below.
        if lines.count >= 2, looksLikeName(first), !first.hasSuffix("."), !first.hasSuffix("?"), !first.hasSuffix("!") {
            let isUpper = first == first.uppercased() && first.rangeOfCharacter(from: .letters) != nil
            if isUpper || first.split(separator: " ").count <= 2 {
                return Parsed(speaker: first.capitalized, text: join(Array(lines.dropFirst())))
            }
        }

        return Parsed(speaker: nil, text: join(lines))
    }

    private static func looksLikeName(_ s: String) -> Bool {
        let words = s.split(separator: " ")
        guard (1...3).contains(words.count), s.count <= 24 else { return false }
        return words.allSatisfy { w in w.first.map { $0.isUppercase || $0.isNumber } ?? false }
    }

    private static func join(_ lines: [String]) -> String {
        lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
