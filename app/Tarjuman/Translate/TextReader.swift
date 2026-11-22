// SPDX-License-Identifier: AGPL-3.0-only
import CoreVideo
import Foundation
import Vision

/// Reads text inside a region of a video frame with Apple Vision (on device).
enum TextReader {
    /// - Parameter region: normalized rect, origin top-left (0...1).
    /// - Returns: recognized lines, top to bottom.
    static func read(_ frame: CVPixelBuffer, region: CGRect, languages: [String] = ["en-US"]) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        let r = region.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        if !r.isNull, r.width > 0.02, r.height > 0.02 {
            // Vision uses a bottom-left origin.
            request.regionOfInterest = CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = (request.results ?? []).sorted { a, b in
            let dy = a.boundingBox.midY - b.boundingBox.midY
            if abs(dy) > 0.02 { return dy > 0 } // higher on screen first
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return observations.compactMap { obs -> String? in
            guard let top = obs.topCandidates(1).first, top.confidence >= 0.3 else { return nil }
            let s = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
    }
}
