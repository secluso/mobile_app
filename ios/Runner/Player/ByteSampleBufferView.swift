//! SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import CoreMedia
import UIKit

/// A lightweight view that wraps AVSampleBufferDisplayLayer and exposes a few
/// conveniences for scheduling and debugging. The view owns a private timebase
/// that starts paused and is anchored to the PTS of the first enqueued frame.
/// This makes it trivial to feed already-timestamped samples without having to
/// manage host-time conversions on the caller side. The display layer is sized
/// to the view’s bounds and uses resizeAspectFill so the feed fills the wider
/// livestream frame instead of preserving letterbox bars.
///
/// Logging focuses on the relationship between each sample’s PTS and the layer’s
/// timebase so late or early frames are immediately visible in the console. The
/// first sample after a flush sets the timebase’s current time and starts the
/// clock running. If the layer reports a failure or requires a flush to resume,
/// the view performs a flush automatically before accepting new samples.
final class ByteSampleBufferView: UIView {
    /// Optional callback for clients that want to react to coded aspect changes.
    var onAspectRatio: ((Double) -> Void)?
    var onDebug: ((String) -> Void)?
    var onFirstFrame: (() -> Void)?

    private func debug(_ s: String) { onDebug?(s) }

    let displayLayer = AVSampleBufferDisplayLayer()

    private var timebase: CMTimebase?
    private var hasAnchored = false
    private var hasDeliveredFirstFrame = false
    private var isObservingDisplayLayer = false
    private(set) var isShuttingDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black
        layer.addSublayer(displayLayer)

        // Observe status and error to surface layer state changes in logs.
        displayLayer.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        displayLayer.addObserver(self, forKeyPath: "error", options: [.new], context: nil)
        isObservingDisplayLayer = true

        displayLayer.videoGravity = .resizeAspectFill

        // Create a paused timebase and bind it to the layer. It will be started
        // when the first sample arrives so scheduling aligns to that PTS.
        var tb: CMTimebase?
        CMTimebaseCreateWithMasterClock(
            allocator: kCFAllocatorDefault,
            masterClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb
        )
        timebase = tb
        displayLayer.controlTimebase = tb
        if let tb = tb {
            CMTimebaseSetRate(tb, rate: 0.0)
            CMTimebaseSetTime(tb, time: .zero)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        removeDisplayLayerObserversIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }

    /// Clears the current image, resets and pauses the timebase, and drops the
    /// anchor flag so the next frame will re-anchor the clock. Use this when
    /// recovering from decoder failures or when seeking.
    func flush() {
        guard !isShuttingDown else { return }
        displayLayer.flushAndRemoveImage()
        if let tb = timebase {
            CMTimebaseSetRate(tb, rate: 0.0)
            CMTimebaseSetTime(tb, time: .zero)
        }
        hasAnchored = false
        hasDeliveredFirstFrame = false
        debug("[SBDisplayLayer] flush() reset TB and cleared anchor")
    }

    /// Enqueues a ready CMSampleBuffer into the display layer. If the layer is
    /// failed or requires a flush to resume decoding, a flush is performed first.
    /// The first buffer after a flush anchors the timebase at its PTS and starts
    /// playback. Attachment keys are updated so sync frames are correctly marked
    /// and the first frame may bypass scheduling when requested.
    func enqueue(_ sbuf: CMSampleBuffer, isIDR: Bool, isFirst: Bool = false) {
        guard !isShuttingDown else { return }
        // If the layer has failed, or if the (read-only) flag says we must flush to resume, do it.
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            flush()
        }

        // Log PTS vs timebase for visibility. A positive "late" means the frame is behind TB.
        let pts = CMSampleBufferGetPresentationTimeStamp(sbuf)
        let tbNow = timebase.map { CMTimebaseGetTime($0) } ?? .invalid
        if CMTIME_IS_VALID(pts), CMTIME_IS_VALID(tbNow) {
            let late = CMTimeSubtract(tbNow, pts)
            debug(
                "[SBDisplayLayer] will enqueue  PTS=\(pts.seconds) tbNow=\(tbNow.seconds) late=\(late.seconds) first=\(isFirst) idr=\(isIDR)"
            )
        }

        // Anchor the timebase on the very first frame after a flush/start.
        if isFirst {
            anchorClockIfNeeded(firstPTS: pts)
        }

        // Attachments: mark sync properly and only bypass scheduling on the first frame.
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(isIDR ? kCFBooleanFalse : kCFBooleanTrue).toOpaque()
            )
            if isFirst {
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
        }

        if displayLayer.status == .failed {
            // Safety: if status flipped to failed after tweaks, flush and try again.
            flush()
        }
        displayLayer.enqueue(sbuf)
        if !hasDeliveredFirstFrame {
            hasDeliveredFirstFrame = true
            onFirstFrame?()
        }

        #if DEBUG
            debug("[SWIFT] AVSampleBufferDisplayLayer status=\(displayLayer.status.rawValue)")
        #endif

        let tbNow2 = timebase.map { CMTimebaseGetTime($0) } ?? .invalid
        debug(
            "[SBDisplayLayer] did enqueue   status=\(displayLayer.status.rawValue) ready=\(displayLayer.isReadyForMoreMediaData) tbNow=\(tbNow2.seconds)"
        )
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        onDebug = nil
        onAspectRatio = nil
        onFirstFrame = nil
        removeDisplayLayerObserversIfNeeded()
        displayLayer.flushAndRemoveImage()
        displayLayer.removeFromSuperlayer()
        if let tb = timebase {
            CMTimebaseSetRate(tb, rate: 0.0)
            CMTimebaseSetTime(tb, time: .zero)
        }
        hasAnchored = false
        hasDeliveredFirstFrame = false
        timebase = nil
    }

    /// Returns the current time of the internal timebase or .invalid if none
    /// has been created yet. Callers use this to schedule PTS with a lead.
    func timebaseNow() -> CMTime {
        guard let tb = timebase else { return .invalid }
        return CMTimebaseGetTime(tb)
    }

    /// Indicates whether the timebase has been anchored to the first frame. This
    /// lets the scheduler decide when to request DisplayImmediately.
    func isAnchored() -> Bool { hasAnchored }

    /// Anchors the internal timebase to firstPTS and starts it running. This
    /// is only performed once after a flush; subsequent calls are ignored.
    /// Logging includes host time to help correlate scheduling with system time.
    private func anchorClockIfNeeded(firstPTS: CMTime) {
        guard !hasAnchored, let tb = timebase else { return }
        CMTimebaseSetTime(tb, time: firstPTS)  // set TB timeline origin to the first sample’s PTS
        CMTimebaseSetRate(tb, rate: 1.0)  // start running
        hasAnchored = true

        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
        debug("[SBDisplayLayer] anchored TB: tbTime=\(firstPTS.seconds) hostNow=\(hostNow.seconds)")
    }

    /// Surfaces AVSampleBufferDisplayLayer status and errors through simple
    /// console debugs. This keeps failure modes visible during development
    /// without introducing a dependency on a logging framework.
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard !isShuttingDown else { return }
        if keyPath == "status" {
            debug("[SBDisplayLayer] status -> \(displayLayer.status.rawValue)")
        } else if keyPath == "error" {
            debug("[SBDisplayLayer] error -> \(String(describing: displayLayer.error))")
        }
    }

    private func removeDisplayLayerObserversIfNeeded() {
        guard isObservingDisplayLayer else { return }
        displayLayer.removeObserver(self, forKeyPath: "status")
        displayLayer.removeObserver(self, forKeyPath: "error")
        isObservingDisplayLayer = false
    }
}
