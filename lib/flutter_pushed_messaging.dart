import 'flutter_pushed_messaging_platform_interface.dart';

enum ServiceStatus { notActive, disconnected, active }

class FlutterPushedMessaging {
  ///Return current service status
  static ServiceStatus get status => FlutterPushedMessagingPlatform.status;

  ///Return current client token
  static String? get token => FlutterPushedMessagingPlatform.pushToken;

  ///Forcibly resets the connection to the server
  static Future<void> reconnect() {
    return FlutterPushedMessagingPlatform.instance.reconnect();
  }

  ///Init and start background service
  static Future<bool> init(
      Function(Map<dynamic, dynamic>) backgroundMessageHandler,
      [String title = "Pushed",
      String body = "The service active"]) {
    return FlutterPushedMessagingPlatform.instance
        .init(backgroundMessageHandler, title, body);
  }

  ///Returns a Stream that is called when changing service status
  static Stream<ServiceStatus> onStatus() {
    return FlutterPushedMessagingPlatform.onStatus;
  }

  ///Returns a Stream that is called when an incoming new message
  static Stream<Map<dynamic, dynamic>> onMessage() {
    return FlutterPushedMessagingPlatform.onMessage;
  }

  ///Returns the service log(debug only)
  static Future<String?> getLog() {
    return FlutterPushedMessagingPlatform.instance.getLog();
  }
}
