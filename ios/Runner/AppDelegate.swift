//! SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Flutter
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import UIKit
import UserNotifications
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // REQUIRED so iOS knows which task id belongs to Workmanager
        WorkmanagerPlugin.registerTask(withIdentifier: "com.secluso.task")

        // Ensures all plugins (http, path_provider …) are available
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }

        if let registrar = self.registrar(forPlugin: "byte_player_view") {
            // Platform-view factory
            let factory = BytePlayerViewFactory(messenger: registrar.messenger())
            registrar.register(factory, withId: "byte_player_view")

            // MethodChannel that mirrors Android
            BytePlayerChannel.register(with: registrar.messenger())
        }

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        IosPushRelayBridge.shared.register(with: controller)
        let wifi = FlutterMethodChannel(
            name: "secluso.com/wifi",
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
                        let nsError = error as NSError
                        if nsError.domain == NEHotspotConfigurationErrorDomain,
                            nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
                        {
                            result("connected")
                            return
                        }
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
                        if let info = CNCopyCurrentNetworkInfo(interface as CFString)
                            as? [String: AnyObject],
                            let ssid = info["SSID"] as? String
                        {
                            result(ssid)
                            return
                        }
                    }
                }
                result("")  // Return empty string if not connected
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
            name: "secluso.com/thumbnail",
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

                let durationSeconds = CMTimeGetSeconds(asset.duration)
                let targetSeconds: Double
                if durationSeconds.isFinite && durationSeconds > 0 {
                    targetSeconds = min(max(durationSeconds * 0.25, 0.25), 1.0)
                } else {
                    targetSeconds = 0.5
                }
                let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)

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
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        IosPushRelayBridge.shared.setApnsToken(deviceToken)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[IOS PUSH] Failed to register for remote notifications: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(userInfo)

        if userInfo["body"] != nil {
            completionHandler([])
        } else {
            super.userNotificationCenter(
                center,
                willPresent: notification,
                withCompletionHandler: completionHandler
            )
        }
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(response.notification.request.content.userInfo)
        super.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )
    }
}
