import Flutter
import UIKit

func getFlutterError(_ error: Error) -> FlutterError {
    let e = error as NSError
    return FlutterError(code: "Error: \(e.code)", message: e.domain, details: error.localizedDescription)
}

public class FlutterPushedMessagingPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    
    internal init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pushed_messaging", binaryMessenger: registrar.messenger())
        let instance = FlutterPushedMessagingPlugin(channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    public static func confirmExtension(userInfo: [AnyHashable : Any]){
        let messageId=userInfo["messageId"] as? String
        let clientToken=getSecToken()
        if(messageId != nil && clientToken != nil){
            confirmMessageAction(messageId!, clientToken: clientToken, action: "Show")
            confirmMessage(messageId!,clientToken: clientToken)
        }
    }
    private func addLog(_ event: String){
        print("\(Date()): \(event)")
        if(UserDefaults.standard.bool(forKey: "pushedMessaging.logEnabled")){
            let log=UserDefaults.standard.string(forKey: "pushedMessaging.pushedLog") ?? ""
            UserDefaults.standard.set(log+"\(Date()): \(event)\n", forKey: "pushedMessaging.pushedLog")
        }
    }
    let sdkVersion = "Flutter 1.6.9"
    let operatingSystem = "iOS \(UIDevice.current.systemVersion)"
    var phoneModel = ""
    var apnsToken: String?
    var pushedToken: String?
    let channel: FlutterMethodChannel
    var initNotification: [AnyHashable: Any]?
    var isBackground = true
    var isInited=false
    var applicationId: String? = UserDefaults.standard.string(forKey: "pushedMessaging.applicationId")
 


    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            case "init":
                UserDefaults.standard.set((call.arguments as? [String: Any])?["log"] as? Bool ?? false,forKey: "pushedMessaging.logEnabled")
                UserDefaults.standard.set((call.arguments as? [String: Any])?["serverlog"] as? Bool ?? false,forKey: "pushedMessaging.serverlogEnabled")
                if let appId = (call.arguments as? [String: Any])?["applicationId"] as? String, !appId.isEmpty {
                    applicationId = appId
                    UserDefaults.standard.set(appId, forKey: "pushedMessaging.applicationId")
                }
                initialize(result: result)
            case "pushedMessage":
                let messageId=(call.arguments as? [String: Any])?["messageId"] as? String
                if(messageId != nil && needMessageProcess(messageId!)){
                    result(true)
                }
                else {
                    result(false)
                }
            case "requestNotificationPermissions":
                requestNotificationPermissions(result: result)
            case "getToken":
            result(FlutterPushedMessagingPlugin.getSecToken() ?? "")
            case "getLog":
                result(UserDefaults.standard.string(forKey: "pushedMessaging.pushedLog") ?? "")
            case "setLog":
                addLog((call.arguments as? [String: Any])?["event"] as? String ?? "")
                result(true)
            case "resetToken":
                resetToken(result: result)
            case "clearToken":
                // Remove stored token without requesting a new one (testing purpose)
                deleteSecToken()
                UserDefaults.standard.removeObject(forKey: "pushedMessaging.clientToken")
                pushedToken = nil
                addLog("Token cleared manually")
                result(true)
            default:
                result(FlutterMethodNotImplemented)
        }
    }
    
    func requestNotificationPermissions(result: @escaping FlutterResult) {
        
        let alerts = UserDefaults.standard.bool(forKey: "pushedMessaging.alertEnabled")
        let serverLog = UserDefaults.standard.bool(forKey: "pushedMessaging.serverlogEnabled")
        let center = UNUserNotificationCenter.current()
        // Ensure the notification center delegate is assigned to avoid a runtime crash.
        if center.delegate == nil {
            center.delegate = self
        }
        var options = [UNAuthorizationOptions]()
        options.append(.sound)
        options.append(.badge)
        options.append(.alert)

        let optionsUnion = UNAuthorizationOptions(options)
        center.requestAuthorization(options: optionsUnion) { (granted, error) in
            if let error = error {
                result(getFlutterError(error))
                return
            }
            if(granted != alerts){
                UserDefaults.standard.set(granted,forKey: "pushedMessaging.alertEnabled")
                self.refreshToken(result: nil,alerts: granted)
                if(serverLog){
                    if(self.pushedToken==nil){
                        self.pushedToken=FlutterPushedMessagingPlugin.getSecToken()
                    }
                    if(granted){
                        self.addServerLog(message: "The user has allowed notification messages", properties: ["ClientToken" : self.pushedToken ?? ""])

                    }
                    else{
                        self.addServerLog(message: "The user rejected the notification messages", properties: ["ClientToken" : self.pushedToken ?? ""])
                    }

                }
            }
            result(granted)
        }
        addLog("Request Permission DONE")
    }
    func needMessageProcess(_ messageId: String) -> Bool {
        var processed = UserDefaults.standard.array(forKey: "pushedMessaging.processedMessageIds") as? [String] ?? []
        let lastMessageId=UserDefaults.standard.string(forKey: "pushedMessaging.lastMessageId") ?? ""
        if(processed.isEmpty && !lastMessageId.isEmpty){
            processed.append(lastMessageId)
            UserDefaults.standard.set(processed, forKey: "pushedMessaging.processedMessageIds")
        }
        let already = processed.contains(messageId)
        addLog("[Dedup] Check processed for messageId: \(messageId) в†’ \(already)")
        if already {
            return false
        }
        processed.append(messageId)
        if(processed.count>10){
            processed.removeFirst()
        }
        UserDefaults.standard.set(processed, forKey: "pushedMessaging.processedMessageIds")
        return true
    }
    func initialize(result: @escaping FlutterResult) {
        UIApplication.shared.registerForRemoteNotifications()
        if(initNotification != nil) {
            addLog("Send initial Message")
            if isBackground {
                self.channel.invokeMethod("onReceiveDataBg", arguments: initNotification)
            } else {
                channel.invokeMethod("onReceiveData", arguments: initNotification)
            }
            initNotification=nil
        }
        isInited=true
        addLog("Configure Done")
        let center = UNUserNotificationCenter.current()
        if(center.delegate != nil){
            center.getNotificationSettings { (settings) in
                UserDefaults.standard.set(settings.alertSetting == .enabled,forKey: "pushedMessaging.alertEnabled")
                self.refreshToken(result: result,alerts: nil)
                
            }
        }
        else {
            refreshToken(result: result,alerts: nil)
        }
    }
    
    func saveSecToken(_ token:String)->Bool{
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = "pushed_token"
        query[kSecAttrService] = "pushed_messaging_service"
        query[kSecReturnData] = false
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false
        var status = SecItemCopyMatching(query as CFDictionary, nil)
        query[kSecReturnData] = true
        if status == errSecSuccess {
            SecItemDelete(query as CFDictionary)
        }
        query[kSecValueData] = token.data(using: .utf8)
        status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
        
    }
    public static func getSecToken()->String?{
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = "pushed_token"
        query[kSecAttrService] = "pushed_messaging_service"
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
    
    func refreshToken(result: FlutterResult?,alerts: Bool?){
        if(pushedToken==nil){
            pushedToken=FlutterPushedMessagingPlugin.getSecToken()
        }
        if(pushedToken==nil){
            pushedToken=UserDefaults.standard.string(forKey: "pushedMessaging.clientToken")
        }
        var sysinfo = utsname()
        uname(&sysinfo) 
        phoneModel=String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)!.trimmingCharacters(in: .controlCharacters)

        var parameters: [String: Any] = ["clientToken": pushedToken ?? ""]
        if let appId = applicationId, !appId.isEmpty {
            parameters["applicationId"] = appId
        }
        if(UserDefaults.standard.string(forKey: "pushedMessaging.operatingSystem") != operatingSystem){
            parameters["operatingSystem"] = operatingSystem
        }
        if(alerts != nil) {
            parameters["displayPushNotificationsPermission"] = alerts

        }
        if(UserDefaults.standard.string(forKey: "pushedMessaging.sdkVersion") != sdkVersion){
            parameters["sdkVersion"] = sdkVersion
        }
        if(UserDefaults.standard.string(forKey: "pushedMessaging.phoneModel") != phoneModel){
            parameters["mobileDeviceName"] = phoneModel
        }
        if(apnsToken != nil) {
            parameters["deviceSettings"]=[["deviceToken": apnsToken, "transportKind": "Apns"]]
        }
        let url = URL(string: "https://sub.multipushed.ru/v2/tokens")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        addLog("Post Request body: \(parameters)")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch let error {
            addLog(error.localizedDescription)
            result?(pushedToken ?? "")
            return
        }
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.addLog("Post Request Error: \(error.localizedDescription)")
                result?(self.pushedToken ?? "")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                self.addLog("Invalid Response received from the server")
                result?(self.pushedToken ?? "")
                return
            }
            guard let responseData = data else {
                self.addLog("nil Data received from the server")
                result?(self.pushedToken ?? "")
                return
            }
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: responseData, options: .mutableContainers) as? [String: Any] {
                    guard let model=jsonResponse["model"] as? [String: Any] else{
                        self.addLog("Some wrong with model")
                        result?(self.pushedToken ?? "")
                        return
                    }
                    guard let clientToken=model["clientToken"] as? String else{
                        self.addLog("Some wrong with clientToken")
                        result?(self.pushedToken ?? "")
                        return
                    }
                    
                    if(self.saveSecToken(clientToken)){
                        self.pushedToken=clientToken
                    }
                    UserDefaults.standard.set(self.sdkVersion, forKey: "pushedMessaging.sdkVersion")
                    UserDefaults.standard.set(self.operatingSystem, forKey: "pushedMessaging.operatingSystem")
                    UserDefaults.standard.set(self.phoneModel, forKey: "pushedMessaging.phoneModel")
                    result?(self.pushedToken ?? "")
                    self.addLog("ClientToken: \(self.pushedToken!)")

                } else {
                    self.addLog("data maybe corrupted or in wrong format")
                    result?(self.pushedToken ?? "")
                }
            } catch let error {
                self.addLog(error.localizedDescription)
                result?(self.pushedToken ?? "")
            }
        }
        // perform the task
        task.resume()

    }
    
    func addServerLog(message : String, properties : [String: String]){
        let df = ISO8601DateFormatter()
        var parameters: [String: Any] = ["message": message]
        parameters["incidentTime"] = df.string(from: Date())
        parameters["properties"] = properties
        let url = URL(string: "https://api.multipushed.ru/v2/log")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        addLog("Post Request body: \(parameters)")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch let error {
            addLog(error.localizedDescription)
            return
        }
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.addLog("Post Request Error: \(error.localizedDescription)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                self.addLog("\((response as? HTTPURLResponse)?.statusCode ?? 0): Invalid Response received from the server")
                return
            }
            self.addLog("\((response as? HTTPURLResponse)?.statusCode ?? 0): Response received from the server")

            self.addLog("Server log done")
        }
        // perform the task
        task.resume()
    }
    public static func confirmMessage(_ messageId : String,clientToken: String?){
        if(clientToken==nil) {
            return
        }
        let loginString = String(format: "%@:%@", clientToken!, messageId).data(using: String.Encoding.utf8)!.base64EncodedString()
        let url = URL(string: "https://pub.multipushed.ru/v2/confirm?transportKind=Apns")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(loginString)", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                return
            }
        }
        // perform the task
        task.resume()

    }
    
    public static func confirmMessageAction(_ messageId : String, clientToken: String?, action : String){
       
        if(clientToken==nil) {
            return
        }
        let loginString = String(format: "%@:%@", clientToken!, messageId).data(using: String.Encoding.utf8)!.base64EncodedString()
        let url = URL(string: "https://api.multipushed.ru/v2/mobile-push/confirm-client-interaction?clientInteraction=\(action)")!
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(loginString)", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                return
            }
        }
        // perform the task
        task.resume()

    }
    
    public func applicationDidEnterBackground(_ application: UIApplication) {
      addLog("Background On")
      isBackground = true
    }
      
    public func applicationDidBecomeActive(_ application: UIApplication) {
        addLog("Background Off")
        if(isInited){
            channel.invokeMethod("reconnect",arguments: nil)
        }
        isBackground = false
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        addLog("Apns token: \(deviceToken.hexString)")
        if(apnsToken != deviceToken.hexString){
            apnsToken=deviceToken.hexString
            refreshToken(result: nil,alerts: nil)
            
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        var userInfo = response.notification.request.content.userInfo
      var clickurl: URL?
        
        if let messageId=userInfo["messageId"] as? String {
            addLog("Click MessageId: \(messageId) - \(response.actionIdentifier)")
            if let pusheNotification=userInfo["pushedNotification"] as? [AnyHashable: Any] {
                if let stringUrl = pusheNotification["url"] as? String {
                    if let url = URL(string: stringUrl){
                        clickurl=url
                    }
                }
            }
            if(pushedToken==nil){
                pushedToken=FlutterPushedMessagingPlugin.getSecToken()
            }
            if(needMessageProcess(messageId)){
                FlutterPushedMessagingPlugin.confirmMessage(messageId, clientToken: pushedToken)
                FlutterPushedMessagingPlugin.confirmMessageAction(messageId, clientToken: pushedToken, action: "Show")
            }
            FlutterPushedMessagingPlugin.confirmMessageAction(messageId, clientToken: pushedToken, action: "Click")
            userInfo["buttonId"] = response.actionIdentifier
            addLog("Message click: \(userInfo)")
            if(isInited){
                addLog("Send click Message")
                if isBackground {
                    self.channel.invokeMethod("onReceiveDataBg", arguments: userInfo)
                } else {
                    channel.invokeMethod("onReceiveData", arguments: userInfo)
                }
            }
            else{
                addLog("Save as initial Message")
                      initNotification=userInfo
            }

      }
      if(clickurl != nil){
          UIApplication.shared.open(clickurl!, options: [:], completionHandler: nil)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.addLog("Done click Message")
            completionHandler()
      }

      
    }

    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
        addLog("Message: \(userInfo)")

        if let messageId=userInfo["messageId"] as? String {
            addLog("MessageId: \(messageId)")
            let alertBody = (userInfo["aps"] as? [AnyHashable: Any])?["alert"]
            let alerts = UserDefaults.standard.bool(forKey: "pushedMessaging.alertEnabled")
            if(pushedToken==nil){
                pushedToken=FlutterPushedMessagingPlugin.getSecToken()
            }
            if(needMessageProcess(messageId)){
                FlutterPushedMessagingPlugin.confirmMessage(messageId, clientToken: pushedToken)
                if(alerts && isBackground && ((alertBody as? [AnyHashable: Any]) !=  nil ||  (alertBody as? String) != nil)){
                    FlutterPushedMessagingPlugin.confirmMessageAction(messageId, clientToken: pushedToken, action: "Show")
                }
                if(isInited){
                    addLog("Send Message")
                    if isBackground {
                        self.channel.invokeMethod("onReceiveDataBg", arguments: userInfo)
                    } else {
                        channel.invokeMethod("onReceiveData", arguments: userInfo)
                    }
                  }
                  else{
                        addLog("Save as initial Message")
                        initNotification=userInfo
                  }

            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.addLog("Done Message")
            completionHandler(.newData)
        }
        return true
    }

    // Remove saved token from keychain
    private func deleteSecToken() {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = "pushed_token"
        query[kSecAttrService] = "pushed_messaging_service"
        SecItemDelete(query as CFDictionary)
    }

    // Reset stored token and request a new one from the backend
    private func resetToken(result: @escaping FlutterResult) {
        addLog("Reset token requested")
        // Remove from key-chain and user defaults
        deleteSecToken()
        UserDefaults.standard.removeObject(forKey: "pushedMessaging.clientToken")
        pushedToken = nil

        // Request new token
        refreshToken(result: { newToken in
            // Tell flutter layer to reconnect once token obtained
            self.channel.invokeMethod("reconnect", arguments: nil)
            result(newToken)
        }, alerts: nil)
    }
}

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}

