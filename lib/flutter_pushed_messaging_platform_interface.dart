import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_pushed_messaging/flutter_pushed_messaging_ios.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_android.dart';

abstract class FlutterPushedMessagingPlatform extends PlatformInterface {
  FlutterPushedMessagingPlatform() : super(token: _token);
  static final Object _token = Object();

  static FlutterPushedMessagingPlatform _instance = Platform.isIOS
      ? IosFlutterPushedMessaging()
      : AndroidFlutterPushedMessaging();
  static var messageController =
      StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  static var statusController =
      StreamController<ServiceStatus>.broadcast(sync: true);

  static ServiceStatus status = ServiceStatus.notActive;
  static String? pushToken;
  static FlutterPushedMessagingPlatform get instance => _instance;
  static Stream<Map<dynamic, dynamic>> get onMessage =>
      messageController.stream;
  static Stream<ServiceStatus> get onStatus => statusController.stream;

  static set instance(FlutterPushedMessagingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  static Future<bool> confirmDelivered(
      String token, String messageId, String transport) async {
    var result = true;
    var basicAuth = "Basic ${base64.encode(utf8.encode('$token:$messageId'))}";
    try {
      await http
          .post(
              Uri.parse(
                  'https://pub.pushed.ru/v1/confirm?transportKind=$transport'),
              headers: {
                "Content-Type": "application/json",
                "Authorization": basicAuth
              },
              body: "")
          .timeout(const Duration(seconds: 10),
              onTimeout: (() => throw Exception("TimeOut")));
    } catch (e) {
      result = false;
    }
    return (result);
  }

  Future<String> getNewToken(String token,
      {String? apnsToken, String? fcmToken, String? hpkToken}) async {
    var deviceSettings = [];
    if (apnsToken != null)
      deviceSettings.add({"deviceToken": apnsToken, "transportKind": "Apns"});
    if (fcmToken != null)
      deviceSettings.add({"deviceToken": fcmToken, "transportKind": "Fcm"});
    if (hpkToken != null)
      deviceSettings.add({"deviceToken": hpkToken, "transportKind": "Hpk"});

    final body = json.encode(<String, dynamic>{
      "clientToken": token,
      if (deviceSettings.isNotEmpty) "deviceSettings": deviceSettings
    });
    print("Body: $body");
    try {
      var response = await http
          .post(Uri.parse('https://sub.pushed.ru/tokens'),
              headers: {"Content-Type": "application/json"}, body: body)
          .timeout(const Duration(seconds: 10),
              onTimeout: (() => throw Exception("TimeOut")));
      token = json.decode(response.body)["token"];
    } catch (e) {
      token = "";
    }
    return (token);
  }

  Future<bool> init(Function(Map<dynamic, dynamic>) backgroundMessageHandler,
      [String title = "Pushed", String body = "The service active"]) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<void> reconnect() {
    throw UnimplementedError('reconnect() has not been implemented.');
  }

  Future<String?> getLog() {
    throw UnimplementedError('getLog() has not been implemented.');
  }
}
