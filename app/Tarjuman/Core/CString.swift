// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Reads a fixed-size C char array (imported as a tuple) as a String.
func stringFromCTuple<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        let bytes = raw.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Bytes of a fixed-size C array (imported as a tuple).
func dataFromCTuple<T>(_ tuple: T) -> Data {
    withUnsafeBytes(of: tuple) { Data($0) }
}

/// Copies `data` into a fixed-size C array (imported as a tuple), zero padded.
func copyData<T>(_ data: Data, into tuple: inout T) {
    withUnsafeMutableBytes(of: &tuple) { dst in
        dst.initializeMemory(as: UInt8.self, repeating: 0)
        let n = min(dst.count, data.count)
        guard n > 0 else { return }
        data.prefix(n).withUnsafeBytes { src in
            dst.baseAddress!.copyMemory(from: src.baseAddress!, byteCount: n)
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
