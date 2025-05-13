import Flutter
import UIKit
import NetworkExtension
import Firebase
import workmanager
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
         FirebaseApp.configure()  // Native Firebase init BEFORE plugins

        // REQUIRED so iOS knows which task id belongs to Workmanager
        WorkmanagerPlugin.registerTask(withIdentifier: "com.privastead.task")

        // Ensures all plugins (http, path_provider …) are available
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }

        // Can put custom channels here
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let wifi = FlutterMethodChannel(name: "privastead.com/wifi",
                                        binaryMessenger: controller.binaryMessenger)
        wifi.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            
            // Other methods aren't implemented
            guard call.method == "connectToWifi" else {
                result(FlutterMethodNotImplemented)
                return
            }
            
            let args = call.arguments as! [String: String] // Given we control this, there should never be any non-String instances.
            let ssid = args["ssid"]! // Given we control this, there should never be any cases of no string being passed
            let password = args["password"] ?? "" // Passwords are optional.
            let config = password.isEmpty ? NEHotspotConfiguration(ssid: ssid) : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
            config.joinOnce = true
            
            NEHotspotConfigurationManager.shared.apply(config) { error in
                if let error = error {
                    result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result("connected")
                }
            }
        })
        let thumb = FlutterMethodChannel(
            name: "privastead.com/thumbnail",
            binaryMessenger: controller.binaryMessenger
        )
        thumb.setMethodCallHandler { call, result in
            guard call.method == "generateThumbnail",
                let args  = call.arguments as? [String: Any],
                let path  = args["path"] as? String else {
                result(FlutterMethodNotImplemented)
                return
            }

            let fullSize = args["fullSize"] as? Bool ?? false

            DispatchQueue.global(qos: .userInitiated).async {
                let asset  = AVAsset(url: URL(fileURLWithPath: path))
                let gen    = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true

                if !fullSize {
                    gen.maximumSize = CGSize(width: 80, height: 80)
                }

                let time   = CMTime(seconds: 7, preferredTimescale: 600)

                do {
                    let cgImg   = try gen.copyCGImage(at: time, actualTime: nil)
                    let uiImg   = UIImage(cgImage: cgImg)
                    if let jpeg = uiImg.jpegData(compressionQuality: 0.7) {
                        result(FlutterStandardTypedData(bytes: jpeg))
                    } else {
                        result(FlutterError(code: "JPEG_ERROR",
                                            message: "Could not encode JPEG",
                                            details: nil))
                    }
                } catch {
                    result(FlutterError(code: "THUMBNAIL_ERROR",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }


        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
