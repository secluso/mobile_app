import AVFoundation
import Flutter
import UIKit

final class BytePlayerPlatformView: NSObject, FlutterPlatformView {

    private let containerView = PlayerContainerView()
    private let methodChannel: FlutterMethodChannel
    private let player = AVPlayer()
    private var playerItem: AVPlayerItem?
    private let loader: ByteQueueResourceLoader
    private var statusObservingCtx = 0
    private var asset: AVURLAsset?

    init(
        frame: CGRect,
        viewIdentifier: Int64,
        arguments: Any?,
        binaryMessenger: FlutterBinaryMessenger
    ) {
        let streamId = (arguments as? [String: Any])?["streamId"] as? Int ?? -1
        self.methodChannel = FlutterMethodChannel(
            name: "byte_player_view_\(streamId)",
            binaryMessenger: binaryMessenger)

        self.loader = ByteQueueResourceLoader(streamId: streamId)
        self.loader.methodChannel = methodChannel
        super.init()
        let assetURL = URL(string: "streaming://live/\(streamId)")!

        // no special options needed for latest iOS
        let asset = AVURLAsset(
            url: assetURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        self.asset = asset  // retain strongly

        // Attach custom resource loader delegate early
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "loader.queue"))
        asset.resourceLoader.preloadsEligibleContentKeys = false
        print(
            "[SWIFT] Loader delegate set: \(String(describing: asset.resourceLoader.delegate))")

        // Wrap player setup in DispatchQueue.main.async to ensure delegate is ready
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let item = AVPlayerItem(asset: asset)
            self.playerItem = item

            item.addObserver(
                self,
                forKeyPath: "status",
                options: [.initial, .new],
                context: &self.statusObservingCtx)

            self.player.replaceCurrentItem(with: item)
            self.containerView.playerLayer.player = self.player
            self.player.play()

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                print("[SWIFT] AVPlayer status: \(self.player.status.rawValue)")
                print(
                    "[SWIFT] AVPlayer error: \(self.player.error?.localizedDescription ?? "none")")
                if let currentItem = self.player.currentItem {
                    print("[SWIFT] Item duration: \(CMTimeGetSeconds(currentItem.duration))")
                } else {
                    print("[SWIFT] No current item on AVPlayer")
                }
            }
        }

    }

    //  KVO for playerItem.status
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &statusObservingCtx,
            keyPath == "status",
            let item = object as? AVPlayerItem
        else { return }

        if item.status == .readyToPlay {
            sendAspectRatioIfPossible()
        } else if item.status == .failed {
            print("[SWIFT] PlayerItem failed: \(item.error?.localizedDescription ?? "unknown")")
        }
    }

    // Aspect ratio callback (fallback only)
    private func sendAspectRatioIfPossible() {
        guard
            let track = playerItem?
                .asset
                .tracks(withMediaType: .video)
                .first
        else {
            print("[SWIFT] Aspect ratio: track not ready")
            return
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        let ratio = abs(size.width / size.height)
        print("[SWIFT] Aspect ratio \(ratio)")
        methodChannel.invokeMethod("onAspectRatio", arguments: ratio)
    }

    func view() -> UIView { containerView }

    deinit {
        playerItem?.removeObserver(
            self, forKeyPath: "status",
            context: &statusObservingCtx)
        player.replaceCurrentItem(with: nil)
    }
}

/// Simple UIView
private final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
