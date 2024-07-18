import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';

import 'flutter_pushed_messaging_platform_interface.dart';

/// An implementation of [FlutterPushedMessagingPlatform] that uses method channels.
class IosFlutterPushedMessaging extends FlutterPushedMessagingPlatform {
  String? apnsToken;
  Function(Map<dynamic, dynamic>)? messageCallback;

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pushed_messaging');

  Future<dynamic> _handle(MethodCall call) async {
    var confirmResult = false;
    if (call.method.startsWith("onReceiveData")) {
      try {
        var data = json.decode(call.arguments["data"]);
        call.arguments["data"] = data;
      } catch (_) {}
      var token = (await methodChannel.invokeMethod<String>('getToken')) ?? "";
      confirmResult =
          await confirmDelivered(token, call.arguments["messageId"]);
    }
    switch (call.method) {
      case "onReceiveData":
        FlutterPushedMessagingPlatform.messageController.sink
            .add(call.arguments);
        break;
      case "onReceiveDataBg":
        await messageCallback!(call.arguments);
        break;
      case "apnsToken":
        apnsToken = call.arguments;
        break;
      default:
    }
    if (call.method.startsWith("onReceiveData")) {
      await methodChannel
          .invokeMethod("messageDone", {"confirmed": confirmResult});
    }
  }

  @override
  Future<bool> init(Function(Map<dynamic, dynamic>) backgroundMessageHandler,
      [String title = "Pushed", String body = "The service active"]) async {
    apnsToken = null;
    messageCallback = backgroundMessageHandler;
    methodChannel.setMethodCallHandler(_handle);

    await methodChannel.invokeMethod('configure');
    await requestNotificationPermissions();
    for (var counter = 0; counter < 30; counter++) {
      if (apnsToken != null) break;
      await Future.delayed(Duration(milliseconds: 100));
    }
    if (apnsToken != null) {
      var token = await methodChannel.invokeMethod<String>('getToken');
      var newToken = await getNewToken(token ?? "", apnsToken: apnsToken);

      if (token != newToken && newToken != "") {
        token = newToken;
        await methodChannel.invokeMethod<bool>('setToken', {"token": token});
      }
      if (token != "") {
        FlutterPushedMessagingPlatform.pushToken = token;
        FlutterPushedMessagingPlatform.status = ServiceStatus.active;
        return true;
      }
    }
    return false;
  }

  Future<bool> requestNotificationPermissions(
      [IosNotificationSettings iosSettings =
          const IosNotificationSettings()]) async {
    final bool? result = await methodChannel.invokeMethod<bool>(
        'requestNotificationPermissions', iosSettings.toMap());
    return result ?? false;
  }
}

class IosNotificationSettings {
  const IosNotificationSettings({
    this.sound = true,
    this.alert = true,
    this.badge = true,
  });

  IosNotificationSettings._fromMap(Map<String, bool> settings)
      : sound = settings['sound'],
        alert = settings['alert'],
        badge = settings['badge'];

  final bool? sound;
  final bool? alert;
  final bool? badge;

  Map<String, dynamic> toMap() {
    return <String, bool?>{'sound': sound, 'alert': alert, 'badge': badge};
  }

  @override
  String toString() => 'PushNotificationSettings ${toMap()}';
}
