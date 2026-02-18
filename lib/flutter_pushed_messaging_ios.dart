import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_platform_interface.dart';

class IosFlutterPushedMessaging extends FlutterPushedMessagingPlatform {
  /// The method channel used to interact with the native platform.

  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pushed_messaging');
  Function(Map<dynamic, dynamic>)? messageCallback;

  Future<dynamic> _handle(MethodCall call) async {
    print("[PushedPlugin][iOS][Dart] _handle method=${call.method} args=${call.arguments}");
    if (call.method.startsWith("onReceiveData")) {
      try {
        var data = json.decode(call.arguments["data"]);
        call.arguments["data"] = data;
        print(
            "[PushedPlugin][iOS][Dart] decoded data for ${call.method}: ${call.arguments["data"]}");
      } catch (_) {}
    }
    switch (call.method) {
      case "onReceiveData":
        FlutterPushedMessagingPlatform.messageController.sink
            .add(call.arguments);
        break;
      case "onReceiveDataBg":
        if (messageCallback != null) {
          await messageCallback!(call.arguments);
        }
        break;
      default:
    }
  }

  @override
  Future<String?> getLog() async {
    return await methodChannel.invokeMethod<String>('getLog');
  }

  @override
  Future<bool> init(Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      [String? notificationChannel = "messages",
      bool loggerEnabled = false,
      bool askPermissions = true,
      bool serverLoggerEnabled = false,
      String? applicationId,
      bool enablePushOnForeground = true]) async {
    messageCallback = backgroundMessageHandler;
    methodChannel.setMethodCallHandler(_handle);
    print(
        "[PushedPlugin][iOS][Dart] init loggerEnabled=$loggerEnabled askPermissions=$askPermissions applicationId=$applicationId");
    var result = await methodChannel.invokeMethod<String>('init', {
      "log": loggerEnabled,
      "serverlog": serverLoggerEnabled,
      "enablePushOnForeground": enablePushOnForeground,
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId
    });
    if (result != "") {
      final safeResult = result ?? "";
      final tokenPrefix =
          safeResult.substring(0, safeResult.length > 8 ? 8 : safeResult.length);
      print("[PushedPlugin][iOS][Dart] init success tokenPrefix=$tokenPrefix");
      if (askPermissions) {
        await methodChannel
            .invokeMethod<bool>('requestNotificationPermissions');
      }
      FlutterPushedMessagingPlatform.pushToken = result;
      FlutterPushedMessagingPlatform.status = ServiceStatus.active;
      return true;
    }
    return false;
  }

  @override
  Future<Map<dynamic, dynamic>?> getInitialMessage() async {
    return null;
  }

  @override
  Future<void> askPermissions(
      [bool askNotificationPermission = true,
      bool askBackgroundPermission = true]) async {
    if (askNotificationPermission) {
      await methodChannel.invokeMethod<bool>('requestNotificationPermissions');
    }
  }

  Future<void> addLog(String event) async {
    await methodChannel.invokeMethod<bool>('setLog', {"event": event});
  }
}
