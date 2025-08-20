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
    switch (call.method) {
      case "onReceiveData":
        await methodChannel.invokeMethod<dynamic>(
            "log", {"event": "Flutter FG Message: ${call.arguments}"});
        FlutterPushedMessagingPlatform.messageController.sink
            .add(call.arguments);
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
      String? applicationId]) async {
    methodChannel.setMethodCallHandler(_handle);
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
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId,
    });
    if (result) {
      FlutterPushedMessagingPlatform.status =
          ServiceStatus.values[await methodChannel.invokeMethod("getStatus")];
      FlutterPushedMessagingPlatform.pushToken =
          await methodChannel.invokeMethod("getToken");
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
}
