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
    var log=UserDefaults.standard.string(forKey: "pushedLog") ?? ""
    print("Log: \(log)")
    let channel = FlutterMethodChannel(name: "flutter_pushed_messaging", binaryMessenger: registrar.messenger())
    let instance = FlutterPushedMessagingPlugin(channel: channel)
    instance.addLog("Plugin Created")
    registrar.addApplicationDelegate(instance)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
    
  let channel: FlutterMethodChannel
  var lastNotification: [AnyHashable: Any]?
  var isBackground = true
  var messageHandler: ((UIBackgroundFetchResult) -> Void)?
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      addLog("Invoked: \(call.method)")
    switch call.method {
    case "requestNotificationPermissions":
        requestNotificationPermissions(call, result: result)
    case "setToken":
        UserDefaults.standard.setValue((call.arguments as? [String: Any])?["token"] as? String ?? "", forKey: "clientToken")
        addLog("Set Token Done")
        result(true)
    case "getToken":
        result(UserDefaults.standard.string(forKey: "clientToken") ?? "")
    case "getLog":
        result(UserDefaults.standard.string(forKey: "pushedLog") ?? "")
    case "messageDone":
        addLog("Confirtmed: \((call.arguments as? [String: Any])?["confirmed"] as? Bool ?? false)")
        if(messageHandler != nil){
            addLog("Free Handler")
            messageHandler!(.noData)
            messageHandler=nil
        }
        result(lastNotification)
    case "configure":
        UIApplication.shared.registerForRemoteNotifications()
        addLog("Configure Done")
        result(nil)
    default:
        assertionFailure(call.method)
        result(FlutterMethodNotImplemented)
    }
  }
    
  func requestNotificationPermissions(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

    let center = UNUserNotificationCenter.current()
    let application = UIApplication.shared
        
    func readBool(_ key: String) -> Bool {
        (call.arguments as? [String: Any])?[key] as? Bool ?? false
    }
    assert(center.delegate != nil)
    var options = [UNAuthorizationOptions]()
    if readBool("sound") {
        options.append(.sound)
    }
    if readBool("badge") {
        options.append(.badge)
    }
    if readBool("alert") {
        options.append(.alert)
    }
    var provisionalRequested = false
    if #available(iOS 12.0, *) {
        if readBool("provisional") {
            options.append(.provisional)
            provisionalRequested = true
        }
    }
    let optionsUnion = UNAuthorizationOptions(options)
    center.requestAuthorization(options: optionsUnion) { (granted, error) in
        if let error = error {
            result(getFlutterError(error))
            return
        }
        center.getNotificationSettings { (settings) in
            let map = [
                "sound": settings.soundSetting == .enabled,
                "badge": settings.badgeSetting == .enabled,
                "alert": settings.alertSetting == .enabled,
                "provisional": granted && provisionalRequested
            ]
            self.channel.invokeMethod("onIosSettingsRegistered", arguments: map)
        }
        result(granted)
    }
    application.registerForRemoteNotifications()
    addLog("Request Permission DONE")
  }
  func addLog(_ event: String){
  #if DEBUG
      
    print(event)
    var log=UserDefaults.standard.string(forKey: "pushedLog") ?? ""
    UserDefaults.standard.set(log+"\(Date()): \(event)\n", forKey: "pushedLog")
    //UserDefaults.standard.set("", forKey: "pushedLog")
  #endif
  }

  public func applicationDidEnterBackground(_ application: UIApplication) {
    addLog("Background On")
    isBackground = true
  }
    
  public func applicationDidBecomeActive(_ application: UIApplication) {
    addLog("Background Off")
    isBackground = false
  }

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    addLog("Apns token: \(deviceToken.hexString)")
    channel.invokeMethod("apnsToken", arguments: deviceToken.hexString)
  }

  public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
    addLog("Message: \(userInfo)")
    messageHandler=completionHandler
    lastNotification=userInfo
    if isBackground {
        self.channel.invokeMethod("onReceiveDataBg", arguments: userInfo)
    } else {
        channel.invokeMethod("onReceiveData", arguments: userInfo)
    }
    return true
  }
}

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}
