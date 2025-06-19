import AVFoundation
import Firebase
import Flutter
import NetworkExtension
import UIKit
import workmanager
import SystemConfiguration.CaptiveNetwork

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

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let wifi = FlutterMethodChannel(
            name: "privastead.com/wifi",
            binaryMessenger: controller.binaryMessenger)
        wifi.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

            if call.method == "connectToWifi" {
                guard let args = call.arguments as? [String: String],
                      let ssid = args["ssid"]
                else {
                    result(
                        FlutterError(code: "INVALID_ARGS", message: "Missing SSID", details: nil))
                    return
                }
                
                let password = args["password"] ?? ""
                let config =
                password.isEmpty
                ? NEHotspotConfiguration(ssid: ssid)
                : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
                config.joinOnce = true
                
                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error = error {
                        result(
                            FlutterError(
                                code: "FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        result("connected")
                    }
                }
            } else if call.method == "getCurrentSSID" {
                if let interfaces = CNCopySupportedInterfaces() as? [String] {
                    for interface in interfaces {
                        if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject],
                           let ssid = info["SSID"] as? String {
                            result(ssid)
                            return
                        }
                    }
                }
                result("") // Return empty string if not connected
            } else if call.method == "disconnectFromWifi" {
                guard let args = call.arguments as? [String: String],
                    let ssid = args["ssid"]
                else {
                    result(
                        FlutterError(code: "INVALID_ARGS", message: "Missing SSID", details: nil))
                    return
                }

                NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
                result("disconnected")
            } else {
                result(FlutterMethodNotImplemented)
            }
        })

        let thumb = FlutterMethodChannel(
            name: "privastead.com/thumbnail",
            binaryMessenger: controller.binaryMessenger
        )
        thumb.setMethodCallHandler { call, result in
            guard call.method == "generateThumbnail",
                let args = call.arguments as? [String: Any],
                let path = args["path"] as? String
            else {
                result(FlutterMethodNotImplemented)
                return
            }

            let fullSize = args["fullSize"] as? Bool ?? false

            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: URL(fileURLWithPath: path))
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true

                if !fullSize {
                    gen.maximumSize = CGSize(width: 80, height: 80)
                }

                let time = CMTime(seconds: 7, preferredTimescale: 600)

                do {
                    let cgImg = try gen.copyCGImage(at: time, actualTime: nil)
                    let uiImg = UIImage(cgImage: cgImg)
                    if let jpeg = uiImg.jpegData(compressionQuality: 0.7) {
                        result(FlutterStandardTypedData(bytes: jpeg))
                    } else {
                        result(
                            FlutterError(
                                code: "JPEG_ERROR",
                                message: "Could not encode JPEG",
                                details: nil))
                    }
                } catch {
                    result(
                        FlutterError(
                            code: "THUMBNAIL_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                }
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
