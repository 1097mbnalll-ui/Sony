// SPDX-License-Identifier: AGPL-3.0-only
import AVFoundation
import SwiftUI
import UIKit

/// Shows decoded frames with AVSampleBufferDisplayLayer.
final class PreviewRenderer {
    let layer = AVSampleBufferDisplayLayer()
    private let lock = NSLock()
    private var pending: CMSampleBuffer?
    private var scheduled = false

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    /// Thread-safe. Drops frames if the main thread is behind.
    func display(_ pixelBuffer: CVPixelBuffer) {
        guard let sample = Self.wrap(pixelBuffer) else { return }
        lock.lock()
        pending = sample
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let s = self.pending
            self.pending = nil
            self.scheduled = false
            self.lock.unlock()
            guard let s else { return }
            if self.layer.status == .failed { self.layer.flush() }
            self.layer.enqueue(s)
        }
    }

    func clear() {
        DispatchQueue.main.async { self.layer.flushAndRemoveImage() }
    }

    private static func wrap(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var fd: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb,
                                                           formatDescriptionOut: &fd) == noErr,
              let fd else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb,
                                                       formatDescription: fd, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// SwiftUI host for the renderer's layer.
struct StreamPreview: UIViewRepresentable {
    let renderer: PreviewRenderer

    final class HostView: UIView {
        var videoLayer: CALayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer?.frame = bounds
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.backgroundColor = .black
        v.layer.addSublayer(renderer.layer)
        v.videoLayer = renderer.layer
        // The stream is never mirrored, even in right-to-left layouts.
        v.semanticContentAttribute = .forceLeftToRight
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {}
}
