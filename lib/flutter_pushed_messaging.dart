import 'flutter_pushed_messaging_platform_interface.dart';

enum ServiceStatus { active, disconnected, notActive }

class FlutterPushedMessaging {
  ///Return current service status
  static ServiceStatus get status => FlutterPushedMessagingPlatform.status;

  ///Return current client token
  static String? get token => FlutterPushedMessagingPlatform.pushToken;

  ///Init and start background service
  ///notificationChannel - (Android only) notification channel (if cahnnel == null The library will not show notifications)
  ///loggerEnabled - Allows the library to save a local log for debugging purposes
  ///askPermissions -  If set to true, permissions are automatically requested.
  ///applicationId - Custom identifier passed to backend when issuing client token (optional).
  static Future<bool> init(
      Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      {String? notificationChannel = "messages",
      bool loggerEnabled = false,
      bool askPermissions = true,
      bool serverLoggerEnabled = false,
      String? applicationId}) {
    return FlutterPushedMessagingPlatform.instance.init(
        backgroundMessageHandler,
        notificationChannel,
        loggerEnabled,
        askPermissions,
        serverLoggerEnabled,
        applicationId);
  }

  ///Ask permissions
  ///askNotificationPermission - Ask permissions to display notifications.
  ///askBackgroundPermission - Ask permissions to work in the background(Android only)
  static Future<void> askPermissions(
      {bool askNotificationPermission = true,
      bool askBackgroundPermission = true}) {
    return FlutterPushedMessagingPlatform.instance
        .askPermissions(askNotificationPermission, askBackgroundPermission);
  }

  ///Returns a Stream that is called when changing service status
  static Stream<ServiceStatus> onStatus() {
    return FlutterPushedMessagingPlatform.onStatus;
  }

  ///Returns a Stream that is called when an incoming new message
  static Stream<Map<dynamic, dynamic>> onMessage() {
    return FlutterPushedMessagingPlatform.onMessage;
  }

  ///Returns a Stream that is called when a user clicks on a notification
  static Stream<Map<dynamic, dynamic>> onMessageOpenedApp() {
    return FlutterPushedMessagingPlatform.onMessageOpenedApp;
  }

  ///Returns a message that opened the app from a terminated state
  static Future<Map<dynamic, dynamic>?> getInitialMessage() {
    return FlutterPushedMessagingPlatform.instance.getInitialMessage();
  }

  ///Returns the service log(debug only)
  static Future<String?> getLog() {
    return FlutterPushedMessagingPlatform.instance.getLog();
  }
}
