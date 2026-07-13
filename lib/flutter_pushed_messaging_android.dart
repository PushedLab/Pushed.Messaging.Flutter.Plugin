import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';

import 'flutter_pushed_messaging_platform_interface.dart';

@pragma('vm:entry-point')
Future<void> entrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  var methodChannel =
      const MethodChannel('flutter_pushed_messaging', JSONMethodCodec());

  try {
    final int rawHandle = int.parse(args[0]);
    final message = json.decode(args[1]);
    await methodChannel.invokeMethod<dynamic>(
        "log", {"event": "Flutter BG Message: $message"});
    if (rawHandle != 0) {
      final callbackHandle = CallbackHandle.fromRawHandle(rawHandle);
      final onMessage = PluginUtilities.getCallbackFromHandle(callbackHandle);
      if (onMessage != null) await onMessage(message);
    }
  } catch (e) {
    await methodChannel
        .invokeMethod<dynamic>("log", {"event": "BG Message: $e"});
  }
}

class AndroidFlutterPushedMessaging extends FlutterPushedMessagingPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel =
      const MethodChannel('flutter_pushed_messaging', JSONMethodCodec());

  Future<dynamic> _handle(MethodCall call) async {
    print(
        "[PushedPlugin][Android][Dart] _handle method=${call.method} args=${call.arguments}");
    switch (call.method) {
      case "onReceiveData":
        await methodChannel.invokeMethod<dynamic>(
            "log", {"event": "Flutter FG Message: ${call.arguments}"});
        FlutterPushedMessagingPlatform.messageController.sink
            .add(call.arguments);
        break;
      case "Token":
        FlutterPushedMessagingPlatform.pushToken = call.arguments["Token"];
        break;
      case "Status":
        await methodChannel.invokeMethod<dynamic>(
            "log", {"event": "Flutter Status: ${call.arguments}"});
        FlutterPushedMessagingPlatform.status =
            ServiceStatus.values[call.arguments["Status"]];
        FlutterPushedMessagingPlatform.statusController.sink
            .add(FlutterPushedMessagingPlatform.status);
        break;
      case "onMessageOpenedApp":
        await methodChannel.invokeMethod<dynamic>(
            "log", {"event": "Flutter onMessageOpenedApp: ${call.arguments}"});
        FlutterPushedMessagingPlatform.onMessageOpenedAppController.sink
            .add(call.arguments);
        break;
      default:
    }
  }

  @override
  Future<String?> getLog() async {
    return await methodChannel.invokeMethod<dynamic>("getLog");
  }

  @override
  Future<String?> getToken() async {
    return await methodChannel.invokeMethod<String?>("getToken");
  }

  @override
  Future<Map<dynamic, dynamic>?> getInitialMessage() async {
    return await methodChannel
        .invokeMethod<Map<dynamic, dynamic>?>('getInitialMessage');
  }

  @override
  Future<bool> init(Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      [String? notificationChannel = "messages",
      bool loggerEnabled = false,
      bool askPermissions = true,
      bool serverLoggerEnabled = false,
      String? applicationId,
      bool enablePushOnForeground = true,
      String? environment]) async {
    methodChannel.setMethodCallHandler(_handle);
    print(
        "[PushedPlugin][Android][Dart] init loggerEnabled=$loggerEnabled askPermissions=$askPermissions applicationId=$applicationId environment=$environment");
    var rawHandle = 0;
    if (backgroundMessageHandler != null) {
      rawHandle = PluginUtilities.getCallbackHandle(backgroundMessageHandler)
              ?.toRawHandle() ??
          0;
    }
    final result = await methodChannel.invokeMethod("init", {
      "backgroundHandle": rawHandle,
      "channel": notificationChannel,
      "logger": loggerEnabled,
      "askpermissions": askPermissions,
      "serverLoggerEnabled": serverLoggerEnabled,
      "enablePushOnForeground": enablePushOnForeground,
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId,
      if (environment != null && environment.isNotEmpty) "environment": environment,
    });
    if (result) {
      FlutterPushedMessagingPlatform.status =
          ServiceStatus.values[await methodChannel.invokeMethod("getStatus")];
      FlutterPushedMessagingPlatform.pushToken =
          await methodChannel.invokeMethod("getToken");
      print(
          "[PushedPlugin][Android][Dart] init success status=${FlutterPushedMessagingPlatform.status} token=${FlutterPushedMessagingPlatform.pushToken}");
    }
    return result;
  }

  @override
  Future<void> askPermissions(
      [bool askNotificationPermission = true,
      bool askBackgroundPermission = true]) async {
    await methodChannel.invokeMethod("askPermissions", {
      "askNotification": askNotificationPermission,
      "askBackgroundWork": askBackgroundPermission
    });
  }

  @override
  Future<bool> setEnvironment(String environment) async {
    final result = await methodChannel.invokeMethod<bool>("setEnvironment", {
      "environment": environment,
    });
    return result ?? false;
  }

  @override
  Future<String> getEnvironment() async {
    final result = await methodChannel.invokeMethod<String>("getEnvironment");
    return result ?? "prod";
  }

  @override
  Future<String?> resetToken() async {
    final result = await methodChannel.invokeMethod<String?>("resetToken");
    if (result != null && result.isNotEmpty) {
      FlutterPushedMessagingPlatform.pushToken = result;
      return result;
    }
    return null;
  }

  @override
  Future<Map<dynamic, dynamic>> getEndpoints() async {
    final result =
        await methodChannel.invokeMethod<Map<dynamic, dynamic>>("getEndpoints");
    return result ?? <dynamic, dynamic>{};
  }

  @override
  Future<bool> resetAll() async {
    await methodChannel.invokeMethod("setEnvironment", {"environment": "prod"});
    final newToken = await methodChannel.invokeMethod<String?>("resetToken");
    FlutterPushedMessagingPlatform.pushToken = newToken;
    return true;
  }

  @override
  Future<bool> sendInteraction(String messageId, String interaction) async {
    final result = await methodChannel.invokeMethod<bool>("sendInteraction", {
      "messageId": messageId,
      "interaction": interaction,
    });
    return result ?? false;
  }
}
