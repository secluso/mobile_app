//! SPDX-License-Identifier: GPL-3.0-or-later
import Flutter
import UIKit

/// This class bridges the native iOS UIView containing an AVSampleBufferDisplayLayer into Flutter via the FlutterPlatformView protocol.
/// It owns the demuxer actor, manages the queue-driven pump loop that feeds MP4 bytes into it,
/// and forwards debug logs and aspect ratio changes back to Dart through a FlutterMethodChannel.
/// The view instance is tied to a specific stream ID so multiple independent players can be mounted simultaneously.
final class BytePlayerPlatformView: NSObject, FlutterPlatformView {
    private let container = ByteSampleBufferView()
    private let methodChannel: FlutterMethodChannel
    private let demuxer: MP4H264Demuxer
    private var running = true
    private let streamId: Int

    /// The initializer constructs the container view, configures the method channel based on the stream ID,
    /// and attaches a small debug overlay for visibility during development.
    /// It creates a demuxer bound to the container and sets up actor callbacks for debug and aspect ratio events.
    /// Finally, it emits an initial log and launches the background pump loop that drains the byte queue for this stream.
    init(
        frame: CGRect, viewIdentifier: Int64, arguments: Any?,
        binaryMessenger: FlutterBinaryMessenger
    ) {
        self.streamId = (arguments as? [String: Any])?["streamId"] as? Int ?? -1
        self.methodChannel = FlutterMethodChannel(
            name: "byte_player_view_\(streamId)", binaryMessenger: binaryMessenger)

        container.onDebug = { [weak methodChannel] msg in
            methodChannel?.invokeMethod("debug", arguments: msg)
        }

        self.demuxer = MP4H264Demuxer(view: container)
        super.init()

        Task { [weak self] in
            guard let self else { return }
            await self.demuxer.setOnDebug { [weak self] msg in
                DispatchQueue.main.async {
                    self?.methodChannel.invokeMethod("debug", arguments: msg)
                }
            }
            await self.demuxer.setOnAspectRatio { [weak self] r in
                DispatchQueue.main.async {
                    self?.methodChannel.invokeMethod("onAspectRatio", arguments: r)
                    self?.methodChannel.invokeMethod("debug", arguments: "[MP4] aspect \(r)")
                }
            }
        }

        emit("Low-level MP4 path starting (ftyp/moov/mdat expected)")
        // start it
        Task.detached { [weak self] in
            await self?.pump()
        }
    }

    /// The pump loop is an asynchronous task responsible for consuming byte chunks from the ByteQueueManager
    /// and delivering them to the demuxer. It runs until running is cleared, adapting its backoff delay dynamically
    ///  when no data is available to avoid excessive spinning. When the queue yields an empty chunk, this is interpreted
    /// as EOF and the loop terminates after notifying the demuxer. Logs are emitted at every step so upstream Flutter code
    /// can trace stream progress.
    private func pump() async {
        var backoff: TimeInterval = 0.0
        let maxBackoff: TimeInterval = 0.02

        while running {
            if let chunk = ByteQueueManager.pop(id: streamId) {
                if chunk.isEmpty {
                    emit("[MP4] EOF from queue")
                    ByteQueueManager.drop(id: streamId)
                    break
                }
                backoff = 0.0
                emit("[MP4] pump got \(chunk.count) bytes")
                await demuxer.append(chunk)  // <— actor call
            } else {
                backoff = backoff == 0.0 ? 0.001 : min(maxBackoff, backoff * 1.5)
                let ns = UInt64(backoff * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
        emit("[MP4] pump ended")
    }

    /// This method returns the underlying UIView (the container) so Flutter can embed it in the widget hierarchy.
    /// It exposes the render surface to the platform view system without giving direct access to internal details like the demuxer.
    func view() -> UIView { container }

    //The deinitializer ensures a clean shutdown by stopping the pump loop, signaling the demuxer to finish, and flushing the container’s display layer on the main thread.
    //  This guarantees that no stale frames remain displayed and the actor is left in a stable state when the platform view is destroyed.
    deinit {
        running = false
        Task { await demuxer.finish() }
        Task { @MainActor in
            container.flush()
        }
    }

    /// This helper wraps debug string forwarding into the method channel.
    /// It always dispatches asynchronously on the main queue so Flutter’s message handling stays thread-safe
    /// allowing logs and state changes from background tasks like the pump to appear reliably on the Dart side.
    private func emit(_ s: String) {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel.invokeMethod("debug", arguments: s)
        }
    }
}
