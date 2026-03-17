import CryptoKit
import DeviceCheck
import Flutter
import Foundation
import UIKit
import UserNotifications

final class IosPushRelayBridge {
    static let shared = IosPushRelayBridge()

    private let channelName = "secluso.com/ios_push_relay"
    private let pendingPayloadsKey = "secluso.pending_remote_push_payloads"
    private let apnsTokenKey = "secluso.apns_device_token"
    private let appAttestKeyIdKey = "secluso.app_attest_key_id"

    private var channel: FlutterMethodChannel?

    private init() {}

    func register(with controller: FlutterViewController) {
        let methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.binaryMessenger
        )
        methodChannel.setMethodCallHandler(handleMethodCall)
        channel = methodChannel
        log("Registered Flutter method channel")
    }

    func registerForRemoteNotifications() {
        log("Requesting remote notification registration")
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func setApnsToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: apnsTokenKey)
        log("Updated APNs token token=\(summarize(token))")
        channel?.invokeMethod("apnsTokenUpdated", arguments: token)
    }

    func recordIncomingRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard let normalized = normalizeDictionary(userInfo) else {
            return
        }

        var payloads = loadPendingPayloads()
        payloads.append(normalized)
        UserDefaults.standard.set(payloads, forKey: pendingPayloadsKey)
        log("Recorded incoming remote notification keys=\(normalized.keys.sorted().joined(separator: ","))")

        channel?.invokeMethod("pushPayload", arguments: normalized)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        log("Handling method call method=\(call.method)")
        switch call.method {
        case "registerForRemoteNotifications":
            registerForRemoteNotifications()
            result(nil)
        case "getApnsToken":
            let token = UserDefaults.standard.string(forKey: apnsTokenKey)
            result(token)
        case "drainPendingPushPayloads":
            let payloads = loadPendingPayloads()
            UserDefaults.standard.removeObject(forKey: pendingPayloadsKey)
            result(payloads)
        case "ensureAppAttestKey":
            ensureAppAttestKey(result: result)
        case "rotateAppAttestKey":
            rotateAppAttestKey(result: result)
        case "attestKey":
            guard
                let args = call.arguments as? [String: Any],
                let challenge = args["challenge"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing challenge", details: nil))
                return
            }
            attestKey(challenge: challenge, result: result)
        case "generateAssertion":
            guard
                let args = call.arguments as? [String: Any],
                let challenge = args["challenge"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing challenge", details: nil))
                return
            }
            generateAssertion(challenge: challenge, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func ensureAppAttestKey(result: @escaping FlutterResult) {
        guard #available(iOS 14.0, *) else {
            log("App Attest unavailable because iOS is below 14")
            result(
                FlutterError(
                    code: "UNSUPPORTED_IOS",
                    message: "App Attest requires iOS 14 or newer",
                    details: nil
                )
            )
            return
        }

        let service = DCAppAttestService.shared
        guard service.isSupported else {
            log("App Attest is not supported on this device")
            result(
                FlutterError(
                    code: "APP_ATTEST_UNSUPPORTED",
                    message: "App Attest is not supported on this device",
                    details: nil
                )
            )
            return
        }

        if let existingKeyId = storedAppAttestKeyId() {
            log("Reusing stored App Attest key key=\(summarize(existingKeyId))")
            result(existingKeyId)
            return
        }

        log("Generating new App Attest key")
        service.generateKey { [weak self] keyId, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("App Attest key generation failed error=\(error.localizedDescription)")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_KEY_GENERATION_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                    return
                }

                guard let keyId = keyId else {
                    self?.log("App Attest key generation returned no key id")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_KEY_MISSING",
                            message: "App Attest did not return a key identifier",
                            details: nil
                        )
                    )
                    return
                }

                self?.storeAppAttestKeyId(keyId)
                self?.log("Generated App Attest key key=\(self?.summarize(keyId) ?? "unknown")")
                result(keyId)
            }
        }
    }

    private func rotateAppAttestKey(result: @escaping FlutterResult) {
        guard #available(iOS 14.0, *) else {
            log("App Attest unavailable because iOS is below 14")
            result(
                FlutterError(
                    code: "UNSUPPORTED_IOS",
                    message: "App Attest requires iOS 14 or newer",
                    details: nil
                )
            )
            return
        }

        let service = DCAppAttestService.shared
        guard service.isSupported else {
            log("App Attest is not supported on this device")
            result(
                FlutterError(
                    code: "APP_ATTEST_UNSUPPORTED",
                    message: "App Attest is not supported on this device",
                    details: nil
                )
            )
            return
        }

        let previousKeyId = storedAppAttestKeyId()
        log("Rotating App Attest key old=\(summarize(previousKeyId))")
        service.generateKey { [weak self] keyId, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("App Attest key rotation failed error=\(error.localizedDescription)")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_KEY_ROTATION_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                    return
                }

                guard let keyId = keyId else {
                    self?.log("App Attest key rotation returned no key id")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_KEY_MISSING",
                            message: "App Attest did not return a rotated key identifier",
                            details: nil
                        )
                    )
                    return
                }

                self?.storeAppAttestKeyId(keyId)
                self?.log(
                    "Rotated App Attest key old=\(self?.summarize(previousKeyId) ?? "unknown") new=\(self?.summarize(keyId) ?? "unknown")"
                )
                result(keyId)
            }
        }
    }

    private func attestKey(challenge: String, result: @escaping FlutterResult) {
        guard #available(iOS 14.0, *) else {
            result(
                FlutterError(
                    code: "UNSUPPORTED_IOS",
                    message: "App Attest requires iOS 14 or newer",
                    details: nil
                )
            )
            return
        }

        guard let keyId = storedAppAttestKeyId() else {
            log("Cannot attest because App Attest key is missing")
            result(
                FlutterError(
                    code: "APP_ATTEST_KEY_MISSING",
                    message: "App Attest key is not initialized",
                    details: nil
                )
            )
            return
        }

        log("Creating App Attest attestation key=\(summarize(keyId)) challenge=\(summarize(challenge))")
        let challengeHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        DCAppAttestService.shared.attestKey(keyId, clientDataHash: challengeHash) {
            attestationObject,
            error in
            DispatchQueue.main.async {
                if let error = error {
                    self.log("App Attest attestation failed key=\(self.summarize(keyId)) error=\(error.localizedDescription)")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                    return
                }

                guard let attestationObject = attestationObject else {
                    self.log("App Attest attestation returned no object key=\(self.summarize(keyId))")
                    result(
                        FlutterError(
                            code: "APP_ATTEST_OBJECT_MISSING",
                            message: "App Attest did not return an attestation object",
                            details: nil
                        )
                    )
                    return
                }

                self.log(
                    "Created App Attest attestation key=\(self.summarize(keyId)) attestationObjectLen=\(attestationObject.count)"
                )
                result([
                    "keyId": keyId,
                    "attestationObject": attestationObject.base64EncodedString(),
                ])
            }
        }
    }

    private func generateAssertion(challenge: String, result: @escaping FlutterResult) {
        guard #available(iOS 14.0, *) else {
            result(
                FlutterError(
                    code: "UNSUPPORTED_IOS",
                    message: "App Attest requires iOS 14 or newer",
                    details: nil
                )
            )
            return
        }

        guard let keyId = storedAppAttestKeyId() else {
            log("Cannot generate assertion because App Attest key is missing")
            result(
                FlutterError(
                    code: "APP_ATTEST_KEY_MISSING",
                    message: "App Attest key is not initialized",
                    details: nil
                )
            )
            return
        }

        log("Generating App Attest assertion key=\(summarize(keyId)) challenge=\(summarize(challenge))")
        let clientData: [String: String] = ["challenge": challenge]

        let clientDataJson: Data
        do {
            clientDataJson = try JSONSerialization.data(withJSONObject: clientData)
        } catch {
            log("Failed to encode App Attest clientData JSON error=\(error.localizedDescription)")
            result(
                FlutterError(
                    code: "CLIENT_DATA_JSON_FAILED",
                    message: error.localizedDescription,
                    details: nil
                )
            )
            return
        }

        let clientDataHash = Data(SHA256.hash(data: clientDataJson))
        DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) {
            assertion,
            error in
            DispatchQueue.main.async {
                if let error = error {
                    self.log("App Attest assertion failed key=\(self.summarize(keyId)) error=\(error.localizedDescription)")
                    result(
                        FlutterError(
                            code: "APP_ASSERTION_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                    return
                }

                guard let assertion = assertion else {
                    self.log("App Attest assertion returned no assertion key=\(self.summarize(keyId))")
                    result(
                        FlutterError(
                            code: "APP_ASSERTION_MISSING",
                            message: "App Attest did not return an assertion",
                            details: nil
                        )
                    )
                    return
                }

                self.log(
                    "Generated App Attest assertion key=\(self.summarize(keyId)) assertionLen=\(assertion.count) clientDataJsonLen=\(clientDataJson.count)"
                )
                result([
                    "keyId": keyId,
                    "assertion": assertion.base64EncodedString(),
                    "clientDataJson": clientDataJson.base64EncodedString(),
                ])
            }
        }
    }

    private func loadPendingPayloads() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: pendingPayloadsKey) as? [[String: Any]] ?? []
    }

    private func storedAppAttestKeyId() -> String? {
        UserDefaults.standard.string(forKey: appAttestKeyIdKey)
    }

    private func storeAppAttestKeyId(_ keyId: String) {
        UserDefaults.standard.set(keyId, forKey: appAttestKeyIdKey)
    }

    private func log(_ message: String) {
        print("[IOS RELAY] \(message)")
    }

    private func summarize(_ value: String?) -> String {
        guard let value else {
            return "null"
        }
        if value.isEmpty {
            return "empty"
        }
        if value.count <= 12 {
            return "\(value)(len=\(value.count))"
        }
        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)...\(suffix)(len=\(value.count))"
    }

    private func normalizeDictionary(_ dictionary: [AnyHashable: Any]) -> [String: Any]? {
        var normalized: [String: Any] = [:]

        for (key, value) in dictionary {
            guard let stringKey = key as? String else {
                continue
            }

            guard let normalizedValue = normalizeValue(value) else {
                continue
            }

            normalized[stringKey] = normalizedValue
        }

        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeValue(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let data as Data:
            return data.base64EncodedString()
        case let dictionary as [AnyHashable: Any]:
            return normalizeDictionary(dictionary)
        case let array as [Any]:
            return array.compactMap(normalizeValue)
        default:
            return String(describing: value)
        }
    }
}
