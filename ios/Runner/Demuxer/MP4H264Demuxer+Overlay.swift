// SPDX-License-Identifier: GPL-3.0-or-later
import CoreMedia
import QuartzCore
import UIKit

/// Collects SEI timestamps keyed by PTS and updates a small HUD in the top left corner for user to see visualized latency.
final class SeiLatencyOverlay {

    @MainActor
    func start(on view: ByteSampleBufferView) {
        guard overlayLayer == nil else { return }
        hostView = view

        let tl = CATextLayer()
        tl.contentsScale = UIScreen.main.scale
        tl.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        tl.fontSize = 14
        tl.foregroundColor = UIColor.white.cgColor
        tl.backgroundColor = UIColor.black.withAlphaComponent(0.55).cgColor
        tl.cornerRadius = 6
        tl.alignmentMode = .left
        tl.masksToBounds = true
        tl.frame = CGRect(x: 8, y: 8, width: 340, height: 40)
        overlayLayer = tl

        view.addOverlaySublayer(tl)

        displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        displayLink?.add(to: .main, forMode: .common)
        proxy.owner = self

        log("start: overlay attached and displayLink running")
    }

    @MainActor
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        overlayLayer?.removeFromSuperlayer()
        overlayLayer = nil
        hostView = nil
        index.removeAll()
        log("stop: overlay removed and index cleared")
    }

    // This function removes emulation-prevention bytes (0x03) from the RBSP data.
    private func rbspUnescape(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        var i = data.startIndex
        var zeroCount = 0
        while i < data.endIndex {
            let b = data[i]
            if zeroCount >= 2 && b == 0x03 {
                // Skip the emulation-prevention byte
                i = data.index(after: i)
                zeroCount = 0
                continue
            }
            out.append(b)
            zeroCount = (b == 0) ? (zeroCount + 1) : 0
            i = data.index(after: i)
        }
        return out
    }

    /// Process an AVCC-formatted sample
    func onAvccSample(sample: Data, nalLengthSize: Int, pts: CMTime) {
        if let unixMs = extractUnixMsFromAvccBytes(sample, nalLengthSize: nalLengthSize) {
            index.record(pts: pts, unixMs: unixMs)
            log(String(format: "onAvccSample: SEI time=%llu @ PTS %.3f", unixMs, pts.seconds))
        } else {
            log("onAvccSample: no SEI found in sample (len=\(sample.count))")
        }
    }

    /// Array of AVCC NALs
    func onAvccNalArray(nals: [Data], pts: CMTime) {
        if let unixMs = extractUnixMsFromNalArray(nals) {
            index.record(pts: pts, unixMs: unixMs)
            log(String(format: "onAvccNalArray: SEI time=%llu @ PTS %.3f", unixMs, pts.seconds))
        } else {
            log("onAvccNalArray: no SEI in AU (nals=\(nals.count))")
        }
    }

    private weak var hostView: ByteSampleBufferView?
    private var overlayLayer: CATextLayer?
    private var displayLink: CADisplayLink?
    private let proxy = DisplayLinkProxy()
    private let index = SeiTimeIndex()  // PTS -> unix_ms

    // This UUID identifies our custom SEI payload
    private static let uuid16 = Data("SECLUSO_LATENCY_".utf8)

    // Tick handler for CADisplayLink
    @objc
    @MainActor
    fileprivate func tick() {
        guard let view = hostView, let tl = overlayLayer else { return }
        let tbNow = view.timebaseNow()
        guard CMTIME_IS_VALID(tbNow), let unixMs = index.lookup(at: tbNow) else {
            tl.string = "Waiting for SEI"
            return
        }

        // Show absolute latency.
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let latency = nowMs &- unixMs

        tl.string = String(format: "Lat: %llu ms", latency)

        log(
            String(
                format: "tick: TB=%.3f unix=%llu now=%llu lat=%llu ms",
                tbNow.seconds, unixMs, nowMs, latency))
    }

    // Extract unix_ms timestamp from AVCC-formatted sample bytes
    private func extractUnixMsFromAvccBytes(_ bytes: Data, nalLengthSize: Int) -> UInt64? {
        var i = 0
        let total = bytes.count
        guard (1...4).contains(nalLengthSize) else {
            log("extract: invalid nalLengthSize=\(nalLengthSize)")
            return nil
        }

        while i + nalLengthSize <= total {
            var n = 0
            for j in 0..<nalLengthSize { n = (n << 8) | Int(bytes[i + j]) }
            i += nalLengthSize
            guard n > 0, i + n <= total else {
                log("extract: truncated NAL (n=\(n)) at i=\(i)")
                return nil
            }

            let nalStart = i
            let nalEnd = i + n
            let header = bytes[nalStart]
            let nalType = header & 0x1F

            if nalType == 6, let ts = parseUnregisteredSei(in: bytes[nalStart..<nalEnd]) {
                log("extract: SEI found (len=\(n))")
                return ts
            }

            i = nalEnd
        }
        return nil
    }

    // Extract unix_ms timestamp from array of AVCC NALs
    private func extractUnixMsFromNalArray(_ nals: [Data]) -> UInt64? {
        for (idx, box) in nals.enumerated() {
            guard box.count >= 5 else { continue }
            let len = box[0...3].reduce(0) { ($0 << 8) | Int($1) }
            guard len > 0, 4 + len <= box.count else {
                log("extractArray[\(idx)]: bad len \(len) box.count \(box.count)")
                continue
            }
            let nal = box[4..<(4 + len)]
            guard let first = nal.first else { continue }
            let nalType = first & 0x1F

            if nalType == 6, let ts = parseUnregisteredSei(in: nal) {
                log("extractArray[\(idx)]: SEI found (len=\(len))")
                return ts
            }
        }
        return nil
    }

    // Parse unregistered SEI NAL and extract unix_ms timestamp if present
    private func parseUnregisteredSei(in nal: Data) -> UInt64? {
        // Expect a full NAL (header byte + rbsp). Verify SEI type.
        guard nal.count >= 1, (nal.first! & 0x1F) == 6 else { return nil }

        // Remove NAL header and unescape RBSP
        let rbsp = rbspUnescape(nal[nal.index(after: nal.startIndex)..<nal.endIndex])

        var p = rbsp.startIndex
        let end = rbsp.endIndex

        // Helper to read variable-length 255-byte chunks
        func readVar255(_ label: String) -> Int? {
            var size = 0
            while p < end {
                let b = Int(rbsp[p])
                p = rbsp.index(after: p)
                if b == 255 {
                    size += 255
                } else {
                    size += b
                    return size
                }
            }
            log("parseSEI: \(label) ran off end")
            return nil
        }

        // Parse SEI payloads
        while p < end {
            // payloadType
            var ptype = 0
            while p < end, rbsp[p] == 255 {
                ptype += 255
                p = rbsp.index(after: p)
            }
            if p < end {
                ptype += Int(rbsp[p])
                p = rbsp.index(after: p)
            } else {
                break
            }

            // payloadSize
            guard let psz = readVar255("payloadSize"),
                rbsp.index(p, offsetBy: psz, limitedBy: end) != nil
            else {
                log("parseSEI: payload truncated (psz beyond end)")
                break
            }

            // payloadData
            if ptype == 5 && psz >= 24 {
                let uuidEnd = rbsp.index(p, offsetBy: 16)
                let uuid = rbsp[p..<uuidEnd]
                if uuid.elementsEqual(Self.uuid16) {
                    let tsStart = uuidEnd
                    let tsEnd = rbsp.index(tsStart, offsetBy: 8)
                    let tsSlice = rbsp[tsStart..<tsEnd]
                    let ts = tsSlice.reduce(0) { ($0 << 8) | UInt64($1) }
                    return ts
                } else {
                    log(
                        "parseSEI: UUID mismatch got(\(uuid.count))=\(Data(uuid).hexPrefix(16)) exp(\(Self.uuid16.count))=\(Self.uuid16.hexPrefix(16))"
                    )
                }
            }

            p = rbsp.index(p, offsetBy: psz)
        }
        return nil
    }

    // Simple logging helper
    private func log(_ s: String) { print("[SeiOverlay] \(s)") }
}

// DisplayLink proxy to avoid retain cycle
final class DisplayLinkProxy: NSObject {
    weak var owner: SeiLatencyOverlay?
    @objc func tick() {
        Task { @MainActor in self.owner?.tick() }
    }
}

// Thread-safe PTS -> unix_ms index
final class SeiTimeIndex {
    private var pairs: [(CMTime, UInt64)] = []
    private let lock = NSLock()

    func record(pts: CMTime, unixMs: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        pairs.append((pts, unixMs))
        pairs.sort { CMTimeCompare($0.0, $1.0) < 0 }
        if let last = pairs.last {
            let cutoff = CMTimeSubtract(last.0, CMTime(seconds: 10, preferredTimescale: 90000))
            pairs.removeAll { CMTimeCompare($0.0, cutoff) < 0 }
        }
    }

    func lookup(at t: CMTime) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        var ans: UInt64?
        for (pts, ts) in pairs where CMTimeCompare(pts, t) <= 0 { ans = ts }
        return ans
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        pairs.removeAll(keepingCapacity: false)
    }
}

// Helper to format Data as hex string prefix
extension Data {
    fileprivate func hexPrefix(_ n: Int) -> String {
        let k = Swift.min(n, count)
        return prefix(k).map { String(format: "%02x", $0) }.joined()
    }
}

// Extension to add overlay layer to ByteSampleBufferView
extension ByteSampleBufferView {
    @MainActor
    func addOverlaySublayer(_ layer: CALayer) {
        self.layer.addSublayer(layer)
    }
}
