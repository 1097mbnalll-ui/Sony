// SPDX-License-Identifier: AGPL-3.0-only
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Hardware H.264 / HEVC decoder (VideoToolbox) for chiaki's Annex-B frames.
/// Produces NV12 pixel buffers that can be shown on screen and fed to Vision.
final class VideoDecoder {
    enum Codec { case h264, hevc }

    /// Called on the decoding thread for every decoded frame.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private(set) var codec: Codec = .h264
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var vps: Data?
    private var sps: Data?
    private var pps: Data?
    private var failures = 0

    private let latestLock = NSLock()
    private var latest: CVPixelBuffer?

    /// Most recent decoded frame (thread-safe). Used later for text reading.
    var latestFrame: CVPixelBuffer? {
        latestLock.lock(); defer { latestLock.unlock() }
        return latest
    }

    func reset(codec: Codec) {
        invalidateSession()
        self.codec = codec
        formatDescription = nil
        vps = nil; sps = nil; pps = nil
        failures = 0
        latestLock.lock(); latest = nil; latestLock.unlock()
    }

    deinit { invalidateSession() }

    /// Decodes one access unit. Returns false if a keyframe should be requested.
    func decode(_ buf: UnsafeBufferPointer<UInt8>) -> Bool {
        guard buf.count > 4 else { return true }
        var payload = Data()
        payload.reserveCapacity(buf.count + 16)
        var paramsChanged = false

        for r in Self.nalRanges(buf) {
            let nal = UnsafeBufferPointer(rebasing: buf[r])
            guard let header = nal.first else { continue }
            switch codec {
            case .h264:
                let type = header & 0x1F
                if type == 7 { paramsChanged = store(nal, in: &sps) || paramsChanged; continue }
                if type == 8 { paramsChanged = store(nal, in: &pps) || paramsChanged; continue }
                if type == 9 { continue } // access unit delimiter
            case .hevc:
                let type = (header >> 1) & 0x3F
                if type == 32 { paramsChanged = store(nal, in: &vps) || paramsChanged; continue }
                if type == 33 { paramsChanged = store(nal, in: &sps) || paramsChanged; continue }
                if type == 34 { paramsChanged = store(nal, in: &pps) || paramsChanged; continue }
                if type == 35 { continue } // access unit delimiter
            }
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { payload.append(contentsOf: $0) }
            payload.append(nal)
        }

        if paramsChanged || formatDescription == nil {
            if !rebuildFormat() { return payload.isEmpty }
        }
        guard !payload.isEmpty else { return true }
        guard let fd = formatDescription else { return false }
        if session == nil && !createSession(fd) { return false }
        guard let session else { return false }

        guard let sample = makeSampleBuffer(payload, fd) else { return false }
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [],
                                                       infoFlagsOut: &infoFlags) { [weak self] status, _, image, _, _ in
            guard let self else { return }
            if status == noErr, let image {
                self.latestLock.lock(); self.latest = image; self.latestLock.unlock()
                self.onFrame?(image)
            }
        }
        if status != noErr {
            failures += 1
            if failures < 5 || failures % 100 == 0 {
                LogStore.shared.error("Video decode error \(status)")
            }
            // Session may be invalid after the app returned from background.
            if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr {
                invalidateSession()
            }
            return false
        }
        failures = 0
        return true
    }

    // MARK: - helpers

    private func store(_ nal: UnsafeBufferPointer<UInt8>, in slot: inout Data?) -> Bool {
        let d = Data(nal)
        if slot == d { return false }
        slot = d
        return true
    }

    private func rebuildFormat() -> Bool {
        var sets: [Data] = []
        switch codec {
        case .h264:
            guard let sps, let pps else { return false }
            sets = [sps, pps]
        case .hevc:
            guard let vps, let sps, let pps else { return false }
            sets = [vps, sps, pps]
        }
        var fd: CMVideoFormatDescription?
        let status = Self.withPointers(sets) { ptrs, sizes -> OSStatus in
            switch codec {
            case .h264:
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
            case .hevc:
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &fd)
            }
        }
        guard status == noErr, let fd else {
            LogStore.shared.error("Could not create video format (\(status))")
            return false
        }
        if let old = formatDescription, CMFormatDescriptionEqual(old, otherFormatDescription: fd) {
            return true
        }
        formatDescription = fd
        let dims = CMVideoFormatDescriptionGetDimensions(fd)
        LogStore.shared.info("Video format \(codec == .h264 ? "H.264" : "HEVC") \(dims.width)x\(dims.height)")
        invalidateSession()
        return true
    }

    private func createSession(_ fd: CMVideoFormatDescription) -> Bool {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]() as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var s: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: fd,
                                                  decoderSpecification: nil,
                                                  imageBufferAttributes: attrs as CFDictionary,
                                                  outputCallback: nil, decompressionSessionOut: &s)
        guard status == noErr, let s else {
            LogStore.shared.error("Could not create decoder (\(status))")
            return false
        }
        _ = VTSessionSetProperty(s, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = s
        return true
    }

    private func invalidateSession() {
        if let s = session {
            VTDecompressionSessionInvalidate(s)
            session = nil
        }
    }

    private func makeSampleBuffer(_ payload: Data, _ fd: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: payload.count, flags: 0, blockBufferOut: &block)
        guard status == kCMBlockBufferNoErr, let block else { return nil }
        status = payload.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard status == kCMBlockBufferNoErr else { return nil }
        var sample: CMSampleBuffer?
        var size = payload.count
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                           formatDescription: fd, sampleCount: 1,
                                           sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                           sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                           sampleBufferOut: &sample)
        return status == noErr ? sample : nil
    }

    private static func withPointers<R>(_ sets: [Data],
                                        _ body: ([UnsafePointer<UInt8>], [Int]) -> R) -> R {
        // Copy into stable buffers so the pointers stay valid during `body`.
        let buffers = sets.map { d -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(d.count, 1))
            d.copyBytes(to: p, count: d.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        return body(buffers.map { UnsafePointer($0) }, sets.map { $0.count })
    }

    /// Ranges of NAL unit payloads (without start codes) in an Annex-B buffer.
    static func nalRanges(_ b: UnsafeBufferPointer<UInt8>) -> [Range<Int>] {
        var starts: [(code: Int, data: Int)] = []
        let n = b.count
        var i = 0
        while i + 2 < n {
            if b[i + 2] > 1 { i += 3; continue }
            if b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1 {
                let code = (i > 0 && b[i - 1] == 0) ? i - 1 : i
                starts.append((code, i + 3))
                i += 3
            } else {
                i += 1
            }
        }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(starts.count)
        for (k, s) in starts.enumerated() {
            let end = k + 1 < starts.count ? starts[k + 1].code : n
            if end > s.data { ranges.append(s.data..<end) }
        }
        return ranges
    }
}
