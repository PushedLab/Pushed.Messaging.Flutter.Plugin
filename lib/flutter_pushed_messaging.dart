import 'flutter_pushed_messaging_platform_interface.dart';

enum ServiceStatus { active, disconnected, notActive }

class FlutterPushedMessaging {
  /// SDK version (package version)
  static const String sdkVersion = '1.8.0';

  ///Return current service status
  static ServiceStatus get status => FlutterPushedMessagingPlatform.status;

  ///Return current client token
  static String? get token => FlutterPushedMessagingPlatform.pushToken;

  ///Init and start background service
  static Future<bool> init(
      Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      {String? notificationChannel = "messages",
      bool loggerEnabled = false,
      bool askPermissions = true,
      bool serverLoggerEnabled = false,
      String? applicationId,
      bool enablePushOnForeground = true,

      /// Pushed backend environment: "prod", "dev", or "load". Keeps native SDK in sync with app prefs.
      String? environment}) {
    return FlutterPushedMessagingPlatform.instance.init(
        backgroundMessageHandler,
        notificationChannel,
        loggerEnabled,
        askPermissions,
        serverLoggerEnabled,
        applicationId,
        enablePushOnForeground,
        environment);
  }

  ///Ask permissions
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

  /// Get current push token.
  static Future<String?> getToken() {
    return FlutterPushedMessagingPlatform.instance.getToken();
  }

  /// Set Pushed environment.
  /// Allowed: "prod", "dev", "load"
  static Future<bool> setEnvironment(String environment) {
    return FlutterPushedMessagingPlatform.instance.setEnvironment(environment);
  }

  /// Get current Pushed environment.
  /// Returns: "prod", "dev", or "load"
  static Future<String> getEnvironment() {
    return FlutterPushedMessagingPlatform.instance.getEnvironment();
  }

  /// Re-issue Pushed token in the current environment.
  static Future<String?> resetToken() {
    return FlutterPushedMessagingPlatform.instance.resetToken();
  }

  /// Returns resolved endpoints for current environment.
  static Future<Map<dynamic, dynamic>> getEndpoints() {
    return FlutterPushedMessagingPlatform.instance.getEndpoints();
  }

  /// Reset all tokens and environment back to prod.
  static Future<bool> resetAll() {
    return FlutterPushedMessagingPlatform.instance.resetAll();
  }

  /// Send interaction event to Pushed server.
  /// [messageId] — Pushed messageId from the push payload.
  /// [interaction] — "Show", "Click", or "Close".
  static Future<bool> sendInteraction(String messageId, String interaction) {
    return FlutterPushedMessagingPlatform.instance
        .sendInteraction(messageId, interaction);
  }
}
