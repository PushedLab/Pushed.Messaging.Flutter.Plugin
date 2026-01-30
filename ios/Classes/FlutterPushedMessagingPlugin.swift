import Flutter
import UIKit
import UserNotifications
import PushedMessagingiOSLibrary
import CommonCrypto

public class FlutterPushedMessagingPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    
    let channel: FlutterMethodChannel
    
    // When the app is launched from a notification action, iOS can call the delegate
    // before Dart sets the method channel handler. We queue the payload and flush on init.
    private static var isDartReady: Bool = false
    private static var pendingNotificationEvent: (method: String, args: [String: Any])?
    
    internal init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pushed_messaging", binaryMessenger: registrar.messenger())
        let instance = FlutterPushedMessagingPlugin(channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // Helper for confirmExtension if used externally
    public static func confirmExtension(userInfo: [AnyHashable : Any]){
        if let messageId = userInfo["messageId"] as? String {
            // Confirm delivery using the library
            // Note: confirmDelivery might be intended for NotificationServiceExtension, 
            // but if exposed, we can use it.
            // Based on docs, it is available in PushedMessagingiOSLibrary
             PushedMessagingiOSLibrary.confirmDelivery(messageId: messageId)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            guard let delegate = UIApplication.shared.delegate else {
                result(FlutterError(code: "NO_DELEGATE", message: "UIApplication.shared.delegate is nil", details: nil))
                return
            }
            
            let args = call.arguments as? [String: Any]
            print("📣 Pushed Plugin Init Args: \(String(describing: args))")
            let logEnabled = args?["log"] as? Bool ?? false
            let appId = (args?["applicationId"] as? String)
            
            // Initialize the library
            // Assuming PushedMessagingiOSLibrary.setup matches the signature found in docs
            PushedMessagingiOSLibrary.setup(delegate, askPermissions: true, loggerEnabled: logEnabled, useAPNS: true, enableWebSocket: false, sdkVersion: "Flutter 1.7.0")
            PushedMessagingiOSLibrary.extensionHandlesConfirmation = true
            // PushedMessagingiOSLibrary.clearTokenForTesting()
            
            // Token compatibility:
            // PushedMessagingiOSLibrary.clientToken may remain nil until network refresh completes,
            // but a valid token can already exist in Keychain (encrypted).
            // For backwards compatibility with the old Flutter plugin, we return the decrypted token.
            if let token = Self.getClientTokenCompat(), !token.isEmpty {
                print("📣 Pushed Plugin: init returning token(from keychain): \(token.prefix(8))… (len: \(token.count))")
                // Trigger refresh in background (optional) — don't block init result.
                if let appId, !appId.isEmpty {
                    print("📣 Pushed Plugin: Calling refreshTokenWithApplicationId with \(appId)")
                    PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appId)
                }
                result(token)
                // Continue setting websocket callback below (non-blocking)
            } else {
                if let appId, !appId.isEmpty {
                    print("📣 Pushed Plugin: Calling refreshTokenWithApplicationId with \(appId)")
                } else {
                    print("📣 Pushed Plugin: applicationId missing or empty in args (will refresh without it)")
                }
                // If we don't have a token in keychain (first run), we must refresh to obtain it.
                PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appId)
            }
            
            // Handle WebSocket messages
            PushedMessagingiOSLibrary.onWebSocketMessageReceived = { [weak self] messageJson in
                guard let self = self else { return false }
                
                if let data = messageJson.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    let isBackground = UIApplication.shared.applicationState == .background
                    let method = isBackground ? "onReceiveDataBg" : "onReceiveData"
                    self.channel.invokeMethod(method, arguments: dict)
                    return false
                }
                return false
            }
            
            // Mark Dart ready and flush any queued notification action payload
            Self.isDartReady = true
            if let pending = Self.pendingNotificationEvent {
                print("📣 Pushed Plugin: flushing pending notification event via \(pending.method)")
                self.channel.invokeMethod(pending.method, arguments: pending.args)
                Self.pendingNotificationEvent = nil
            }
            
            // If we already returned token from keychain above, do not call result twice.
            // Otherwise, wait for library token (refresh) and fallback to keychain again.
            if Self.getClientTokenCompat() == nil || (Self.getClientTokenCompat()?.isEmpty ?? true) {
                DispatchQueue.global().async {
                    var attempts = 0
                    while (PushedMessagingiOSLibrary.clientToken == nil || (PushedMessagingiOSLibrary.clientToken?.isEmpty ?? true)) && attempts < 100 {
                        Thread.sleep(forTimeInterval: 0.1)
                        attempts += 1
                    }
                    DispatchQueue.main.async {
                        let token = PushedMessagingiOSLibrary.clientToken
                            ?? Self.getClientTokenCompat()
                            ?? ""
                        print("📣 Pushed Plugin: init returning deferred token(after \(Double(attempts) * 0.1)s): \(token.isEmpty ? "(empty)" : String(token.prefix(8)) + "…") (len: \(token.count))")
                        result(token)
                    }
                }
            }
            
        case "pushedMessage":
            // Used for confirming delivery manually from Flutter side?
            if let args = call.arguments as? [String: Any],
               let messageId = args["messageId"] as? String {
                PushedMessagingiOSLibrary.confirmDelivery(messageId: messageId)
                result(true)
            } else {
                result(false)
            }

        case "getToken":
            let token = Self.getClientTokenCompat()
                ?? PushedMessagingiOSLibrary.clientToken
                ?? ""
            print("📣 Pushed Plugin: getToken -> \(token.isEmpty ? "(empty)" : String(token.prefix(8)) + "…") (len: \(token.count))")
            result(token)
            
        case "requestNotificationPermissions":
            PushedMessagingiOSLibrary.requestNotificationPermissions()
            result(true)
            
        case "getLog":
            result(PushedMessagingiOSLibrary.getLog())
            
        case "setLog":
            // Library doesn't seem to expose external logging entry, 
            // but we can ignore or map if needed.
             result(true)
            
        case "resetToken":
            // Clear token and potentially force new registration if library supports it.
            PushedMessagingiOSLibrary.clearTokenForTesting()
            result(true)
            
        case "clearToken":
            PushedMessagingiOSLibrary.clearTokenForTesting()
            result(true)

        case "resetAll":
            // One-shot factory reset for native pushed storage:
            // - remove pushed_token from Keychain
            // - clear library token + logs
            // - clear related UserDefaults (standard + AppGroup)
            Self.deleteKeychainToken()
            PushedMessagingiOSLibrary.clearTokenForTesting()
            Self.clearPushedUserDefaults()
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Library handles confirmation
        PushedMessagingiOSLibrary.confirmMessage(response)
        
        // Pass payload to Flutter (ensure shape matches the Dart side expectations)
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        
        // Convert userInfo keys to String for standard codec
        var normalized: [String: Any] = [:]
        for (k, v) in userInfo {
            if let key = k as? String {
                normalized[key] = v
            } else {
                normalized[String(describing: k)] = v
            }
        }
        
        // Build "data" json string as expected by `flutter_pushed_messaging_ios.dart`
        // It attempts json.decode(call.arguments["data"]) for onReceiveData* methods.
        var dataJson: String = "{}"
        if let dataStr = normalized["data"] as? String {
            dataJson = dataStr
        } else if let dataDict = normalized["data"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dataDict),
                  let str = String(data: data, encoding: .utf8) {
            dataJson = str
        } else {
            // Fallback: encode whole normalized payload (minus aps) as data
            var fallback = normalized
            fallback.removeValue(forKey: "aps")
            if let data = try? JSONSerialization.data(withJSONObject: fallback),
               let str = String(data: data, encoding: .utf8) {
                dataJson = str
            }
        }
        
        // Try to extract trace id if present
        let mfTraceId = (normalized["mfTraceId"] as? String)
            ?? (normalized["MfTraceId"] as? String)
            ?? (normalized["mf-trace-id"] as? String)
        
        var args: [String: Any] = [
            "data": dataJson
        ]
        if let mfTraceId { args["mfTraceId"] = mfTraceId }
        args["buttonId"] = actionId
        
        let appState = UIApplication.shared.applicationState
        let method = (appState == .active) ? "onReceiveData" : "onReceiveDataBg"
        
        print("📣 Pushed Plugin: didReceive notification action=\(actionId) state=\(appState.rawValue) dartReady=\(Self.isDartReady)")
        
        // Old code: if url in pushedNotification, open it.
        // We should replicate that behavior if the library doesn't auto-open.
        
        // Check for click url? Old code handled it. 
        // Library might handle it?
        // Old code: if url in pushedNotification, open it.
        // We should replicate that behavior if the library doesn't auto-open.
        if let pushedNotification = userInfo["pushedNotification"] as? [AnyHashable: Any],
           let stringUrl = pushedNotification["url"] as? String,
           let url = URL(string: stringUrl) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        if Self.isDartReady {
            channel.invokeMethod(method, arguments: args)
        } else {
            // Queue until init finishes and Dart side sets the handler
            Self.pendingNotificationEvent = (method: "onReceiveDataBg", args: args)
        }
        
        completionHandler()
    }
}

// MARK: - Token compatibility helpers (Keychain + decrypt like native library)

extension FlutterPushedMessagingPlugin {
    private static let pushedKeychainAccount = "pushed_token"
    private static let pushedKeychainService = "pushed_messaging_service"

    // Must match native library crypto params
    private static let tokenCryptoKey = "Rt9n4BbW7Y97fhUkyygddZ8sr8xPNYaU"
    private static let tokenCryptoIv = "xjPamAwc7QLYQkhm"

    static func getClientTokenCompat() -> String? {
        guard let raw = readKeychainString(account: pushedKeychainAccount, service: pushedKeychainService),
              !raw.isEmpty
        else { return nil }
        return decryptTokenIfNeeded(raw) ?? raw
    }

    private static func readKeychainString(account: String, service: String) -> String? {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = account
        query[kSecAttrService] = service
        query[kSecReturnData] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false

        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        guard status == errSecSuccess, let data = ref as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainToken() {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = pushedKeychainAccount
        query[kSecAttrService] = pushedKeychainService
        query[kSecAttrSynchronizable] = false
        let status = SecItemDelete(query as CFDictionary)
        print("📣 Pushed Plugin: deleteKeychainToken status=\(status)")
    }

    private static func clearPushedUserDefaults() {
        func clear(from defaults: UserDefaults, label: String) {
            let dict = defaults.dictionaryRepresentation()
            var removed = 0
            for key in dict.keys {
                if key.hasPrefix("pushedMessaging.") || key.hasPrefix("pushedMessaging") {
                    defaults.removeObject(forKey: key)
                    removed += 1
                }
            }
            defaults.synchronize()
            print("📣 Pushed Plugin: cleared \(removed) keys from \(label)")
        }

        clear(from: UserDefaults.standard, label: "UserDefaults.standard")

        // AppGroup used by the native library
        if let shared = UserDefaults(suiteName: "group.ru.pushed.messaging") {
            clear(from: shared, label: "UserDefaults(group.ru.pushed.messaging)")
        }
    }

    private static func decryptTokenIfNeeded(_ storedValue: String) -> String? {
        // If it's not base64, it's likely a legacy/plain token.
        guard let encryptedData = Data(base64Encoded: storedValue) else {
            return storedValue
        }

        guard let decrypted = aesCrypt(data: encryptedData, operation: CCOperation(kCCDecrypt)),
              let decryptedStr = String(data: decrypted, encoding: .utf8)
        else {
            // Fallback: treat as plain
            return storedValue
        }

        if decryptedStr.hasPrefix("encrypted:") {
            return String(decryptedStr.dropFirst("encrypted:".count))
        }

        // Unknown decrypted format — fallback to stored string
        return storedValue
    }

    private static func aesCrypt(data: Data, operation: CCOperation) -> Data? {
        // Library uses AES-128 + PKCS7Padding
        let keyData = Data(tokenCryptoKey.utf8).prefix(kCCKeySizeAES128)
        let ivData = Data(tokenCryptoIv.utf8).prefix(kCCBlockSizeAES128)

        var outLength: size_t = 0
        var outData = Data(count: data.count + kCCBlockSizeAES128)
        let outDataCapacity = outData.count

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                ivData.withUnsafeBytes { ivBytes in
                    keyData.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, data.count,
                            outBytes.baseAddress, outDataCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outData.removeSubrange(outLength..<outData.count)
        return outData
    }
}
