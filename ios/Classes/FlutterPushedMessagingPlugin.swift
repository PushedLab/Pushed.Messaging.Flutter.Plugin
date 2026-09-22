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
    
    // Environment + per-env tokens
    private static let envKey = "pushed_plugin_environment"
    private static let tokenKeyPrefix = "pushed_plugin_token_"
    private static let pluginKeychainService = "pushed_messaging_plugin"
    
    private static var sharedDefaults: UserDefaults {
        return UserDefaults(suiteName: "group.ru.pushed.messaging") ?? UserDefaults.standard
    }

    internal init(channel: FlutterMethodChannel) {
        self.channel = channel
        Self.migrateUserDefaultsToKeychainIfNeeded()
    }
    
    // MARK: - Environment helpers
    
    private static func migrateUserDefaultsToKeychainIfNeeded() {
        let migratedKey = "pushed_plugin_keychain_migrated"
        if sharedDefaults.bool(forKey: migratedKey) { return }
        
        let defaultsList = [UserDefaults.standard, sharedDefaults]
        for defaults in defaultsList {
            if let env = defaults.string(forKey: envKey) {
                writeKeychainString(account: envKey, service: pluginKeychainService, value: env)
            }
            for e in ["prod", "dev", "load"] {
                if let t = defaults.string(forKey: tokenKeyPrefix + e) {
                    writeKeychainString(account: tokenKeyPrefix + e, service: pluginKeychainService, value: t)
                }
            }
        }
        sharedDefaults.set(true, forKey: migratedKey)
        sharedDefaults.synchronize()
    }
    
    private static func getCurrentEnvironment() -> String {
        return readKeychainString(account: envKey, service: pluginKeychainService) ?? "prod"
    }

    private static func setCurrentEnvironment(_ env: String) {
        writeKeychainString(account: envKey, service: pluginKeychainService, value: env)
    }

    private static func saveTokenForEnv(_ env: String, _ token: String) {
        writeKeychainString(account: tokenKeyPrefix + env, service: pluginKeychainService, value: token)
    }

    private static func loadTokenForEnv(_ env: String) -> String? {
        return readKeychainString(account: tokenKeyPrefix + env, service: pluginKeychainService)
    }

    private static func clearTokenForEnv(_ env: String) {
        deleteKeychainString(account: tokenKeyPrefix + env, service: pluginKeychainService)
    }

    private static func getPushedEnvironment(_ env: String) -> PushedMessaging.PushedEnvironment {
        switch env.lowercased() {
        case "prod": return .prod
        case "dev": return .dev
        case "load": return .load
        default: return .prod
        }
    }

    private static func getApplicationIdForEnv(_ env: String) -> String? {
        switch env.lowercased() {
        case "prod": return ""
        case "dev": return "690b72be907c4d493670ed68"
        case "load": return "66eac3a88164a8e82897405e"
        default: return "66eac3a88164a8e82897405e"
        }
    }

    /// Maps `applicationId` from Flutter to Pushed env when `environment` is omitted (prod/load share the same id → prod).
    private static func inferredEnvFromApplicationId(_ appId: String?) -> String? {
        guard let appId = appId?.trimmingCharacters(in: .whitespacesAndNewlines), !appId.isEmpty else { return nil }
        switch appId {
        case "690b72be907c4d493670ed68": return "dev"
        case "66eac3a88164a8e82897405e": return "prod"
        default: return nil
        }
    }

    private static func normalizedEnvFromDart(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        switch s {
        case "prod", "dev", "load": return s
        default: return nil
        }
    }

    /// If Flutter prefs / `applicationId` disagree with keychain (e.g. old dev session + fresh install defaulting to prod), align before `setup`.
    private static func syncKeychainEnvironmentFromInitArgs(_ args: [String: Any]?) {
        let explicit = normalizedEnvFromDart(args?["environment"] as? String)
        let appId = args?["applicationId"] as? String
        let targetStr = explicit ?? inferredEnvFromApplicationId(appId) ?? getCurrentEnvironment()
        let oldStr = getCurrentEnvironment()
        guard targetStr != oldStr else { return }
        // tokenDiag: the compat/legacy token slot isn't itself namespaced by
        // environment — it's whatever the SDK last physically held, which
        // isn't reliably `oldStr`'s token (e.g. right after a reinstall the
        // env-preference keychain item and the raw token item have no
        // guaranteed correlation). Per-env buckets are the source of truth;
        // never backfill a bucket from this raw slot — only `init()`'s own
        // per-env-bucket lookup and `onClientTokenReceived` (which saves a
        // freshly-issued token under the environment that was actually live
        // when it arrived) are trustworthy writers of per-env storage.
        print("📣 Pushed Plugin: [tokenDiag] sync: oldStr=\(oldStr) targetStr=\(targetStr) compatToken=\(getClientTokenCompat() ?? "nil") "
            + "existingOldBucket=\(loadTokenForEnv(oldStr) ?? "nil") existingTargetBucket=\(loadTokenForEnv(targetStr) ?? "nil")")
        setCurrentEnvironment(targetStr)
        print("📣 Pushed Plugin: init synced keychain env \(oldStr) -> \(targetStr) (Dart / applicationId)")
    }

    /// Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before it returns (iOS 13+).
    /// `BGTaskScheduler` handlers must be registered at launch; Flutter runs plugin `setup()` later.
    public static func registerBackgroundTasksAtLaunch() {
        if #available(iOS 13.0, *) {
            PushedMessaging.registerBackgroundTaskHandlersAtLaunch()
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pushed_messaging", binaryMessenger: registrar.messenger())
        let instance = FlutterPushedMessagingPlugin(channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public static func confirmExtension(userInfo: [AnyHashable : Any]){
        if let messageId = userInfo["messageId"] as? String {
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
            let preSyncEnv = Self.getCurrentEnvironment()
            let dartEnvRaw = args?["environment"] as? String
            let dartAppIdRaw = args?["applicationId"] as? String
            print("📣 Pushed Plugin: [tokenDiag] init IN: Dart environment=\(dartEnvRaw ?? "nil") applicationId=\(dartAppIdRaw ?? "nil") keychainEnv(before sync)=\(preSyncEnv)")
            
            if let appId, !appId.isEmpty {
                UserDefaults.standard.set(appId, forKey: "pushed_plugin_applicationId")
            }

            Self.syncKeychainEnvironmentFromInitArgs(args)
            
            let currentEnvStr = Self.getCurrentEnvironment()
            let currentEnv = Self.getPushedEnvironment(currentEnvStr)
            let appIdToUse = Self.getApplicationIdForEnv(currentEnvStr)
            print("📣 Pushed Plugin: [tokenDiag] init OUT: keychain env=\(currentEnvStr) setup applicationId=\(appIdToUse ?? "nil") (Dart was env=\(dartEnvRaw ?? "nil") appId=\(dartAppIdRaw ?? "nil"))")
            print("📣 Pushed Plugin: Using environment: \(currentEnvStr), applicationId: \(appIdToUse ?? "nil")")
            
            PushedMessagingiOSLibrary.setup(delegate, askPermissions: true, loggerEnabled: logEnabled, useAPNS: false, enableWebSocket: true, environment: currentEnv, sdkVersion: "Flutter 1.7.1.2")
            // PushedMessagingiOSLibrary.clearTokenForTesting()
            PushedMessagingiOSLibrary.extensionHandlesConfirmation = true

            // Registering the BGTask handlers (done by the host app at launch via
            // registerBackgroundTasksAtLaunch) only tells iOS *what* to run — the tasks
            // still have to be submitted to BGTaskScheduler, otherwise they never fire.
            // The native example does this explicitly; do the same here so Flutter apps
            // get background WebSocket processing without extra AppDelegate code.
            PushedMessagingiOSLibrary.enableBackgroundWebSocketTasks()
            
            PushedMessagingiOSLibrary.onClientTokenReceived = { token in
                let envStr = PushedMessagingiOSLibrary.currentEnvironment.rawValue
                print("📣 Pushed Plugin: onClientTokenReceived -> saving token for \(envStr)")
                Self.saveTokenForEnv(envStr, token)
            }
            
            // Check for saved per-env token first
            let savedEnvToken = Self.loadTokenForEnv(currentEnvStr)
            let keychainToken = Self.getClientTokenCompat()
            
            print("📣 Pushed Plugin: [MIGRATION DEBUG] currentEnvStr=\(currentEnvStr)")
            print("📣 Pushed Plugin: [MIGRATION DEBUG] savedEnvToken=\(savedEnvToken ?? "nil")")
            print("📣 Pushed Plugin: [MIGRATION DEBUG] keychainToken=\(keychainToken ?? "nil")")
            print("📣 Pushed Plugin: [MIGRATION DEBUG] libraryToken=\(PushedMessagingiOSLibrary.clientToken ?? "nil")")
            
            if let saved = savedEnvToken, !saved.isEmpty {
                // Per-env storage is the source of truth (it's only ever written by
                // onClientTokenReceived, tied to whichever environment was actually
                // live at receipt time). The raw/compat keychain slot is just a
                // working copy the SDK reads at runtime — if it disagrees, it's
                // stale (e.g. left over from a previous environment), not the SDK
                // "live" value; always re-sync it FROM the per-env bucket.
                let tokenToReturn = saved
                if let kc = keychainToken, !kc.isEmpty, kc != saved {
                    print("📣 Pushed Plugin: init per-env saved token != keychain; keychain is stale, restoring saved token for \(currentEnvStr)")
                } else {
                    print("📣 Pushed Plugin: init restored saved token for \(currentEnvStr): \(saved.prefix(8))…")
                }
                Self.writeKeychainToken(saved)
                // Only refresh if we don't have a token in the library yet, or if we need to register APNS.
                // Calling it unconditionally causes the server to issue a new token.
                if PushedMessagingiOSLibrary.clientToken == nil || PushedMessagingiOSLibrary.clientToken!.isEmpty {
                    PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
                } else {
                    print("📣 Pushed Plugin: init using existing library token for \(currentEnvStr)")
                }
                result(tokenToReturn)
            } else if let token = keychainToken, !token.isEmpty {
                // We have a token in keychain, but no saved token for the current environment.
                // This happens on update from an older version where per-env tokens weren't saved properly.
                // Old plugin tokens are equivalent to 'prod' environment.
                print("📣 Pushed Plugin: init using keychain token for \(currentEnvStr) (migration): \(token) (len: \(token.count))")
                
                if currentEnvStr == "prod" {
                    Self.saveTokenForEnv(currentEnvStr, token)
                    if PushedMessagingiOSLibrary.clientToken == nil || PushedMessagingiOSLibrary.clientToken!.isEmpty {
                        PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
                    }
                } else {
                    // If we are migrating but the requested env is NOT prod, we shouldn't use the old prod token.
                    // We must request a new token for this new environment.
                    print("📣 Pushed Plugin: init migration token is for prod, but current env is \(currentEnvStr). Requesting new token.")
                    Self.saveTokenForEnv("prod", token) // Save it for prod just in case
                    Self.deleteKeychainToken()
                    PushedMessagingiOSLibrary.clearTokenForTesting()
                    PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
                }
                result(token)
            } else {
                print("📣 Pushed Plugin: init no saved token, requesting new one")
                PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
            }
            
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
            
            Self.isDartReady = true
            if let pending = Self.pendingNotificationEvent {
                print("📣 Pushed Plugin: flushing pending notification event via \(pending.method)")
                self.channel.invokeMethod(pending.method, arguments: pending.args)
                Self.pendingNotificationEvent = nil
            }
            
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
             result(true)
            
        case "resetToken":
            let currentEnvStr = Self.getCurrentEnvironment()
            let appIdToUse = Self.getApplicationIdForEnv(currentEnvStr)
            print("📣 Pushed Plugin: resetToken start, env=\(currentEnvStr), appId=\(appIdToUse ?? "nil")")
            let oldToken = Self.getClientTokenCompat() ?? ""
            Self.deleteKeychainToken()
            PushedMessagingiOSLibrary.clearTokenForTesting()
            
            PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
            
            DispatchQueue.global().async {
                var attempts = 0
                while (PushedMessagingiOSLibrary.clientToken == nil || (PushedMessagingiOSLibrary.clientToken?.isEmpty ?? true)) && attempts < 100 {
                    Thread.sleep(forTimeInterval: 0.1)
                    attempts += 1
                }
                DispatchQueue.main.async {
                    let newToken = PushedMessagingiOSLibrary.clientToken
                        ?? Self.getClientTokenCompat()
                    let env = Self.getCurrentEnvironment()
                    if let t = newToken, !t.isEmpty {
                        Self.saveTokenForEnv(env, t)
                        print("📣 Pushed Plugin: resetToken done, new=\(t.prefix(8))… old=\(oldToken.prefix(8))…")
                        result(t)
                    } else {
                        print("📣 Pushed Plugin: resetToken done, new token is nil/empty")
                        result(nil as String?)
                    }
                }
            }
            
        case "clearToken":
            PushedMessagingiOSLibrary.clearTokenForTesting()
            result(true)

        case "resetAll":
            print("📣 Pushed Plugin: resetAll — clearing keychain, library, per-env tokens, resetting env to prod")
            Self.deleteKeychainToken()
            PushedMessagingiOSLibrary.clearTokenForTesting()
            Self.clearPushedUserDefaults()
            for env in ["prod", "dev", "load"] {
                Self.clearTokenForEnv(env)
            }
            Self.setCurrentEnvironment("prod")
            result(true)
            
        case "setEnvironment":
            guard let args = call.arguments as? [String: Any],
                  let envName = args["environment"] as? String else {
                result(false)
                return
            }
            let oldEnv = Self.getCurrentEnvironment()
            // tokenDiag: per-env buckets are the source of truth (only ever
            // written by onClientTokenReceived, tied to whichever environment
            // was actually live at receipt time) — don't backfill oldEnv's
            // bucket from the raw/compat slot here; that's how a stale token
            // from an earlier environment previously leaked into another
            // environment's bucket.
            print("📣 Pushed Plugin: [tokenDiag] setEnvironment: oldEnv=\(oldEnv) newEnv=\(envName) compatToken=\(Self.getClientTokenCompat() ?? "nil") "
                + "existingOldBucket=\(Self.loadTokenForEnv(oldEnv) ?? "nil") existingNewBucket=\(Self.loadTokenForEnv(envName) ?? "nil")")

            Self.setCurrentEnvironment(envName)
            print("📣 Pushed Plugin: setEnvironment \(oldEnv) -> \(envName)")
            
            PushedMessagingiOSLibrary.currentEnvironment = Self.getPushedEnvironment(envName)
            
            if let savedToken = Self.loadTokenForEnv(envName), !savedToken.isEmpty {
                print("📣 Pushed Plugin: restored saved token for \(envName): \(savedToken.prefix(8))…")
                Self.writeKeychainToken(savedToken)
                if PushedMessagingiOSLibrary.clientToken == nil || PushedMessagingiOSLibrary.clientToken!.isEmpty {
                    let appIdToUse = Self.getApplicationIdForEnv(envName)
                    PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
                }
                result(true)
            } else {
                Self.deleteKeychainToken()
                PushedMessagingiOSLibrary.clearTokenForTesting()
                
                let appId = UserDefaults.standard.string(forKey: "pushed_plugin_applicationId")
                
                let appIdToUse = Self.getApplicationIdForEnv(envName)
                print("📣 Pushed Plugin: setEnvironment new token needed, appId=\(appIdToUse ?? "nil")")
                
                PushedMessagingiOSLibrary.refreshTokenWithApplicationId(appIdToUse)
                
                DispatchQueue.global().async {
                    var attempts = 0
                    while (PushedMessagingiOSLibrary.clientToken == nil || (PushedMessagingiOSLibrary.clientToken?.isEmpty ?? true)) && attempts < 100 {
                        Thread.sleep(forTimeInterval: 0.1)
                        attempts += 1
                    }
                    DispatchQueue.main.async {
                        result(true)
                    }
                }
            }
            
        case "getEnvironment":
            let env = Self.getCurrentEnvironment()
            print("📣 Pushed Plugin: getEnvironment -> \(env)")
            result(env)
            
        case "getEndpoints":
            let env = Self.getCurrentEnvironment()
            let payload: [String: Any] = [
                "environment": env
            ]
            print("📣 Pushed Plugin: getEndpoints -> \(payload)")
            result(payload)

        case "sendInteraction":
            guard let args = call.arguments as? [String: Any],
                  let messageId = args["messageId"] as? String,
                  let interaction = args["interaction"] as? String else {
                result(false)
                return
            }
            print("📣 Pushed Plugin: sendInteraction messageId=\(messageId) interaction=\(interaction)")
            let clientToken = Self.getClientTokenCompat() ?? PushedMessagingiOSLibrary.clientToken ?? ""
            guard !clientToken.isEmpty else {
                print("📣 Pushed Plugin: sendInteraction skipped — no token")
                result(false)
                return
            }
            let basicAuth = "Basic " + Data("\(clientToken):\(messageId)".utf8).base64EncodedString()
            let urlString = "https://\(PushedMessagingiOSLibrary.endpoints.apiHost)/v2/mobile-push/confirm-client-interaction?clientInteraction=\(interaction)"
            guard let url = URL(string: urlString) else {
                result(false)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(basicAuth, forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("📣 Pushed Plugin: sendInteraction \(interaction) response: HTTP \(status) body=\(body)")
            }.resume()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let appState = UIApplication.shared.applicationState
        
        if appState == .active {
            print("📣 Pushed Plugin: willPresent foreground push — forwarding data to Dart")
            
            var normalized: [String: Any] = [:]
            for (k, v) in userInfo {
                if let key = k as? String {
                    normalized[key] = v
                } else {
                    normalized[String(describing: k)] = v
                }
            }
            
            var dataJson: String = "{}"
            if let dataStr = normalized["data"] as? String {
                dataJson = dataStr
            } else if let dataDict = normalized["data"] as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dataDict),
                      let str = String(data: data, encoding: .utf8) {
                dataJson = str
            } else {
                var fallback = normalized
                fallback.removeValue(forKey: "aps")
                if let data = try? JSONSerialization.data(withJSONObject: fallback),
                   let str = String(data: data, encoding: .utf8) {
                    dataJson = str
                }
            }
            
            let mfTraceId = (normalized["mfTraceId"] as? String)
                ?? (normalized["MfTraceId"] as? String)
                ?? (normalized["mf-trace-id"] as? String)
            
            var args: [String: Any] = ["data": dataJson]
            if let mfTraceId { args["mfTraceId"] = mfTraceId }
            
            print("📣 Pushed Plugin: willPresent forwarding onReceiveData: \(args)")
            channel.invokeMethod("onReceiveData", arguments: args)

            if notification.request.trigger is UNPushNotificationTrigger,
               let messageId = userInfo["messageId"] as? String,
               !messageId.isEmpty {
                PushedMessagingiOSLibrary.confirmDelivery(messageId: messageId)
            }

            completionHandler([])
            return
        }
        
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        PushedMessagingiOSLibrary.confirmMessage(response)
        
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        
        var normalized: [String: Any] = [:]
        for (k, v) in userInfo {
            if let key = k as? String {
                normalized[key] = v
            } else {
                normalized[String(describing: k)] = v
            }
        }
        
        var dataJson: String = "{}"
        if let dataStr = normalized["data"] as? String {
            dataJson = dataStr
        } else if let dataDict = normalized["data"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dataDict),
                  let str = String(data: data, encoding: .utf8) {
            dataJson = str
        } else {
            var fallback = normalized
            fallback.removeValue(forKey: "aps")
            if let data = try? JSONSerialization.data(withJSONObject: fallback),
               let str = String(data: data, encoding: .utf8) {
                dataJson = str
            }
        }
        
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
        
        if let pushedNotification = userInfo["pushedNotification"] as? [AnyHashable: Any],
           let stringUrl = pushedNotification["url"] as? String,
           let url = URL(string: stringUrl) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        if Self.isDartReady {
            channel.invokeMethod(method, arguments: args)
        } else {
            Self.pendingNotificationEvent = (method: "onReceiveDataBg", args: args)
        }
        
        completionHandler()
    }
}

// MARK: - Token compatibility helpers (Keychain + decrypt like native library)

extension FlutterPushedMessagingPlugin {
    private static let pushedKeychainAccount = "pushed_token"
    private static let pushedKeychainService = "pushed_messaging_service"

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

    private static func writeKeychainString(account: String, service: String, value: String) {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = account
        query[kSecAttrService] = service
        query[kSecAttrSynchronizable] = false
        SecItemDelete(query as CFDictionary)
        
        guard let data = value.data(using: .utf8) else { return }
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private static func deleteKeychainString(account: String, service: String) {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = account
        query[kSecAttrService] = service
        query[kSecAttrSynchronizable] = false
        SecItemDelete(query as CFDictionary)
    }

    private static func writeKeychainToken(_ token: String) {
        deleteKeychainToken()
        guard let data = token.data(using: .utf8) else { return }
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = pushedKeychainAccount
        query[kSecAttrService] = pushedKeychainService
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        print("📣 Pushed Plugin: writeKeychainToken status=\(status)")
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

        if let shared = UserDefaults(suiteName: "group.ru.pushed.messaging") {
            clear(from: shared, label: "UserDefaults(group.ru.pushed.messaging)")
        }
    }

    private static func decryptTokenIfNeeded(_ storedValue: String) -> String? {
        guard let encryptedData = Data(base64Encoded: storedValue) else {
            return storedValue
        }

        guard let decrypted = aesCrypt(data: encryptedData, operation: CCOperation(kCCDecrypt)),
              let decryptedStr = String(data: decrypted, encoding: .utf8)
        else {
            return storedValue
        }

        if decryptedStr.hasPrefix("encrypted:") {
            return String(decryptedStr.dropFirst("encrypted:".count))
        }

        return storedValue
    }

    private static func aesCrypt(data: Data, operation: CCOperation) -> Data? {
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
