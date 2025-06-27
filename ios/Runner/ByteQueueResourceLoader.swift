import AVFoundation
import Flutter

final class ByteQueueResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    private let streamId: Int
    private var leftover = Data()  // queued but not yet consumed
    private var headerSent = false  // FTYP, MOOV delivered
    private var aspectRatioSent = false
    var methodChannel: FlutterMethodChannel?

    init(streamId: Int) {
        self.streamId = streamId
    }

    // Delegate registration
    func resourceLoader(_ rl: AVAssetResourceLoader, canHandle lr: AVAssetResourceLoadingRequest)
        -> Bool
    {
        guard let url = lr.request.url else { return false }
        let match = url.scheme == "streaming"
        print("[SWIFT] canHandle called with URL: \(url) → \(match)")
        return match
    }

    // Main loader
    func resourceLoader(
        _ rl: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource lr: AVAssetResourceLoadingRequest
    ) -> Bool {

        print(
            "[SWIFT] shouldWaitForLoading called: offset = \(lr.dataRequest?.requestedOffset ?? -1), length = \(lr.dataRequest?.requestedLength ?? -1)"
        )

        // Tell AVPlayer this is an MP4 live stream (length unknown, no byte-range support)
        if let info = lr.contentInformationRequest {
            info.contentType = AVFileType.mp4.rawValue
            info.isByteRangeAccessSupported = false
            // contentLength not set (for live stream purposes)
        }

        guard let dr = lr.dataRequest else { return false }

        // Handle the request on a background queue
        DispatchQueue.global(qos: .userInitiated).async { [self] in

            //First request: send FTYP + MOOV header
            if !headerSent && dr.requestedOffset == 0 {
                print("[SWIFT] buffering until MOOV complete …")
                let header = bufferUntilMoovPlusSomeMdat()
                print("[SWIFT]  MOOV done, header \(header.count) B")

                // Respond with the full header once
                dr.respond(with: header)
                lr.finishLoading()
                headerSent = true
                return
            }

            // Subsequent range requests
            print("[SWIFT] range req offset=\(dr.requestedOffset) len=\(dr.requestedLength)")
            stream(
                bytesNeeded: dr.requestedLength,
                offset: dr.requestedOffset,
                to: dr)
            lr.finishLoading()
        }

        return true  // tell AVFoundation we are handling this request
    }

    // Buffer FTYP + complete MOOV
    private func bufferUntilMoovPlusSomeMdat(minBytes: Int = 128 * 1024) -> Data {
        var buf = Data()

        while true {
            if !leftover.isEmpty {
                buf.append(leftover)
                leftover.removeAll(keepingCapacity: true)
            } else {
                var chunk = ByteQueueManager.pop(id: streamId)
                while chunk == nil {
                    Thread.sleep(forTimeInterval: 0.02)
                    chunk = ByteQueueManager.pop(id: streamId)
                }
                let data = chunk!
                if data.isEmpty { break }  // EOF
                buf.append(data)
            }

            // Try to find MOOV atom and include MDAT immediately after
            if let moov = buf.range(of: Data([0x6d, 0x6f, 0x6f, 0x76])) {  // "moov"
                if moov.lowerBound >= 4 {
                    let sizeData = buf.subdata(in: moov.lowerBound - 4..<moov.lowerBound)
                    let moovSize = Int(
                        UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                    let moovEnd = moov.lowerBound + moovSize

                    if buf.count >= moovEnd && buf.count >= minBytes {
                        print("[SWIFT] detected full MOOV + enough MDAT (\(buf.count) B)")
                        print("[SWIFT] Header hex dump:")
                        print(
                            buf.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
                        )
                        if !aspectRatioSent {
                            aspectRatioSent = true
                            let moovData = buf.subdata(in: moov.lowerBound - 4..<moovEnd)
                            extractAspectRatio(from: moovData)
                        }
                        return buf
                    }
                }
            }

            if buf.count > 4 * 1024 * 1024 {
                print("[SWIFT] Gave up after 4 MB without full MOOV + MDAT")
                return buf
            }
        }

        return buf
    }

    // Extract aspect ratio
    private func extractAspectRatio(from moovData: Data) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "aspect_\(streamId).mp4")
        try? moovData.write(to: url)

        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            guard let self = self else { return }

            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            guard status == .loaded else {
                print("[SWIFT] aspect extract error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            guard let track = asset.tracks(withMediaType: .video).first else {
                print("[SWIFT] no video track found")
                return
            }

            let size = track.naturalSize.applying(track.preferredTransform)
            let aspect = abs(size.width / size.height)

            DispatchQueue.main.async {
                print("[SWIFT] Aspect ratio from MOOV: \(aspect)")
                self.methodChannel?.invokeMethod("onAspectRatio", arguments: aspect)
            }
        }
    }

    // Serve exactly bytesNeeded
    private func stream(
        bytesNeeded: Int,
        offset requestedOffset: Int64,
        to dr: AVAssetResourceLoadingDataRequest
    ) {
        var remain = bytesNeeded

        // Serve from leftover
        if !leftover.isEmpty {
            let slice = leftover.prefix(remain)
            dr.respond(with: slice)

            if requestedOffset != 0 {
                leftover.removeFirst(slice.count)
            }
            remain -= slice.count
        }

        // Pop new chunks until satisfied
        while remain > 0 {
            var chunk = ByteQueueManager.pop(id: streamId)
            while chunk == nil {
                Thread.sleep(forTimeInterval: 0.02)
                chunk = ByteQueueManager.pop(id: streamId)
            }
            let data = chunk!
            if data.isEmpty { break }

            let slice = data.prefix(remain)
            dr.respond(with: slice)
            remain -= slice.count

            if slice.count < data.count {
                leftover.append(data.dropFirst(slice.count))
            }
        }

        print("[SWIFT] sent \(bytesNeeded - remain) B (remain \(remain))")
    }
}
