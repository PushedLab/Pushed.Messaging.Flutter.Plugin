import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_platform_interface.dart';
import 'package:huawei_push/huawei_push.dart' as huawei;

WebSocketChannel? webChannel;
var active = false;
StreamSubscription? subs;
var connected = false;
var currentStatus = ServiceStatus.disconnected;

@pragma('vm:entry-point')
Future<void> entrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MethodChannel channel = const MethodChannel(
    'flutter_pushed_messaging_bg',
    JSONMethodCodec(),
  );
  await channel.invokeMethod<dynamic>("lock");
  addLog(channel, "Start entrypoint");
  await setNewStatus(channel, currentStatus);
  final int rawHandle = int.parse(args[0]);
  final String token = args[1];
  addLog(channel, "Token: $token");
  final callbackHandle = CallbackHandle.fromRawHandle(rawHandle);
  final onMessage = PluginUtilities.getCallbackFromHandle(callbackHandle);
  List<ConnectivityResult> lastConnectivity = [];
  Connectivity().onConnectivityChanged.listen((result) async {
    await channel.invokeMethod<dynamic>("lock");
    await addLog(channel, "Connectivity changed: $result");
    if (result.contains(ConnectivityResult.wifi) &&
        !lastConnectivity.contains(ConnectivityResult.wifi)) {
      webChannel?.sink.close();
    }
    if (result.contains(ConnectivityResult.none)) {
      connected = false;
    } else {
      connected = true;
    }
    lastConnectivity = result;
    connect(token, channel, onMessage);
  });

  channel.setMethodCallHandler((call) async {
    if (call.arguments["method"] == "reconnect" && active) {
      await channel.invokeMethod<dynamic>("lock");
      await addLog(channel, "Reconnect");
      await setNewStatus(channel, currentStatus);
      webChannel?.sink.close();
    }
  });
  await Future.delayed(const Duration(seconds: 5));
  await channel.invokeMethod<dynamic>("unlock");
}

@pragma('vm:entry-point')
Future<void> setNewStatus(
    MethodChannel channel, ServiceStatus newStatus) async {
  currentStatus = newStatus;
  await channel.invokeMethod<dynamic>(
      "data", {"type": "status", "status": newStatus.index});
}

@pragma('vm:entry-point')
Future<void> addLog(MethodChannel channel, String event) async {
  if (kReleaseMode) return;
  var fullEvent = "${DateTime.now()}: $event";
  print(fullEvent);
  await channel.invokeMethod<dynamic>("log", {"event": event});
}

@pragma('vm:entry-point')
Future<void> connect(
    String token, MethodChannel channel, Function? onMessage) async {
  if (!connected) {
    await channel.invokeMethod<dynamic>("unlock");
    return;
  }
  if (active) return;
  await addLog(channel, "Connecting");
  active = true;
  try {
    await subs?.cancel();
    webChannel?.sink.close();
    webChannel = WebSocketChannel.connect(
      Uri.parse('wss://sub.pushed.ru/v2/open-websocket/$token'),
    );
    await webChannel?.ready;
    await setNewStatus(channel, ServiceStatus.active);
    subs = webChannel?.stream.listen((event) async {
      await channel.invokeMethod<dynamic>("lock");
      var message = utf8.decode(event);
      await addLog(channel, "Pushed message: $message");
      if (message != "ONLINE") {
        var payload = json.decode(message);
        var messageId = payload["messageId"];
        var traceId = payload["mfTraceId"];
        var lastMessageId =
            await channel.invokeMethod<String>("getLastMessageId");
        if (lastMessageId != messageId) {
          await addLog(channel, "Pushed processing message");
          await channel.invokeMethod<dynamic>(
              "setLastMessageId", {"lastMessageId": messageId});
          var response = json.encode(<String, dynamic>{
            "messageId": messageId,
            if (traceId != null) "mfTraceId": traceId
          });
          webChannel?.sink.add(utf8.encode(response));
          try {
            var data = json.decode(payload["data"]);
            payload["data"] = data;
          } catch (_) {}
          Map<String, dynamic> data = {"type": "message", "message": payload};
          var res = await channel.invokeMethod<dynamic>("data", data) ?? false;
          if (!res && onMessage != null) await onMessage(payload);
        }
      }
      await Future.delayed(const Duration(seconds: 5));
      await channel.invokeMethod<dynamic>("unlock");
    }, onDone: () async {
      await channel.invokeMethod<dynamic>("lock");
      await addLog(channel, "Closed");
      active = false;
      await setNewStatus(channel, ServiceStatus.disconnected);
      await Future.delayed(const Duration(seconds: 1));
      connect(token, channel, onMessage);
    });
  } catch (e) {
    await channel.invokeMethod<dynamic>("lock");
    await addLog(channel, "Error: $e");
    await setNewStatus(channel, ServiceStatus.disconnected);
    await subs?.cancel();
    active = false;
    await Future.delayed(const Duration(seconds: 1));
    connect(token, channel, onMessage);
  }
}

@pragma('vm:entry-point')
Future<void> messagingBackgroundHandler(
    Map<dynamic, dynamic> pushedMessage, String platform) async {
  var methodChannel =
      const MethodChannel('flutter_pushed_messaging', JSONMethodCodec());
  await addLog(methodChannel, "$platform background message: $pushedMessage");
  var token = await methodChannel.invokeMethod<String>('getToken');
  var rawHandle = await methodChannel.invokeMethod<int>('getHandle');
  await FlutterPushedMessagingPlatform.confirmDelivered(token ?? "",
      pushedMessage["messageId"], platform, pushedMessage["mfTraceId"]);
  var lastMessageId =
      await methodChannel.invokeMethod<String>('getLastMessageId');
  if (lastMessageId != pushedMessage["messageId"]) {
    await addLog(methodChannel, "$platform processing message");
    if (rawHandle != null && rawHandle != 0) {
      final callbackHandle = CallbackHandle.fromRawHandle(rawHandle);
      final onMessage = PluginUtilities.getCallbackFromHandle(callbackHandle);
      if (onMessage != null) onMessage(pushedMessage);
    }
    await methodChannel.invokeMethod<bool>(
        'setLastMessageId', {"lastMessageId": pushedMessage["messageId"]});
  }
}

@pragma('vm:entry-point')
void huaweiMessagingBackgroundHandler(huawei.RemoteMessage message) async {
  var messageOfMap = message.toMap();
  messageOfMap["data"] = message.dataOfMap;
  await messagingBackgroundHandler(
      AndroidFlutterPushedMessaging.convertMessage(messageOfMap), "Hpk");
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await messagingBackgroundHandler(
      AndroidFlutterPushedMessaging.convertMessage(message.toMap()), "Fcm");
}

@pragma('vm:entry-point')
Future<void> ruStoreEntrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await messagingBackgroundHandler(
      AndroidFlutterPushedMessaging.convertMessage(json.decode(args[0])),
      "RuStore");
}

class AndroidFlutterPushedMessaging extends FlutterPushedMessagingPlatform {
  @visibleForTesting
  final methodChannel =
      const MethodChannel('flutter_pushed_messaging', JSONMethodCodec());
  Function(Map<dynamic, dynamic>)? messageCallback;
  Map<dynamic, dynamic>? initialPush;

  static Map<dynamic, dynamic> convertMessage(Map<String, dynamic> message) {
    var result = message;
    var data = message["data"]?["data"];
    var messageId = message["data"]?["messageId"];
    var buttonId = message["data"]?["buttonId"];
    var traceId = message["data"]?["mfTraceId"];
    if (traceId != null) {
      result["mfTraceId"] = traceId;
    }
    if (buttonId != null) {
      result["buttonId"] = buttonId;
    }
    if (messageId != null) {
      result["messageId"] = messageId;
    }
    if (data != null) {
      try {
        var tData = json.decode(data);
        result["data"] = tData;
      } catch (_) {
        result["data"] = data;
      }
    }
    return result;
  }

  Future<void> clickOnPush(
      Map<dynamic, dynamic> pushedMessage, String platform) async {
    if (pushedMessage["buttonId"] == null) {
      pushedMessage["buttonId"] = "DEFAULT";
    }
    await addLog(methodChannel, '$platform click on push: $pushedMessage');
    var token = await methodChannel.invokeMethod<String>('getToken');
    await FlutterPushedMessagingPlatform.confirmDelivered(token ?? "",
        pushedMessage["messageId"], "Hpk", pushedMessage["mfTraceId"]);
    FlutterPushedMessagingPlatform.messageController.sink.add(pushedMessage);
    await methodChannel.invokeMethod<bool>(
        'setLastMessageId', {"lastMessageId": pushedMessage["messageId"]});
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.arguments["type"] == "message") {
      dynamic msg;
      if (call.arguments["transport"] == "ruStore") {
        var lastMessageId =
            await methodChannel.invokeMethod<String>('getLastMessageId');
        msg = convertMessage(call.arguments);
        if (lastMessageId == msg["messageId"]) return;
        await addLog(methodChannel, "RuStore processing message");
        await FlutterPushedMessagingPlatform.confirmDelivered(
            FlutterPushedMessaging.token ?? "",
            msg["messageId"],
            "RuStore",
            msg["mfTraceId"]);
      } else {
        msg = call.arguments["message"];
      }
      switch (call.method) {
        case "onReceiveData":
          FlutterPushedMessagingPlatform.messageController.sink.add(msg);
          break;
        case "onReceiveDataBg":
          await messageCallback!(msg);
          break;
        default:
      }
    }
    if (call.arguments["type"] == "status") {
      var newStatus = ServiceStatus.values[call.arguments["status"]];
      if (FlutterPushedMessagingPlatform.status != newStatus) {
        FlutterPushedMessagingPlatform.statusController.sink.add(newStatus);
        FlutterPushedMessagingPlatform.status = newStatus;
      }
    }
  }

  @override
  Future<void> reconnect() async {
    if (FlutterPushedMessagingPlatform.status != ServiceStatus.notActive) {
      await methodChannel
          .invokeMethod<dynamic>('data', {"method": "reconnect"});
    }
  }

  @override
  Future<String?> getLog() async {
    return await methodChannel.invokeMethod<String>('getlog');
  }

  @override
  Future<bool> init(Function(Map<dynamic, dynamic>) backgroundMessageHandler,
      [String title = "Pushed", String body = "The service active"]) async {
    //hpk
    String? hpkToken;
    try {
      await huawei.Push.turnOnPush();
      huawei.Push.getTokenStream.listen((event) async {
        hpkToken = event;
        await addLog(methodChannel, 'HpkDeviceToken: $hpkToken');
      });
      huawei.Push.onMessageReceivedStream.listen((event) async {
        var messageOfMap = event.toMap();
        messageOfMap["data"] = event.dataOfMap;
        var pushedMessage =
            AndroidFlutterPushedMessaging.convertMessage(messageOfMap);
        await addLog(methodChannel, 'Hpk onMessage: $pushedMessage');
        var token = await methodChannel.invokeMethod<String>('getToken');
        await FlutterPushedMessagingPlatform.confirmDelivered(token ?? "",
            pushedMessage["messageId"], "Hpk", pushedMessage["mfTraceId"]);
        var lastMessageId =
            await methodChannel.invokeMethod<String>('getLastMessageId');
        if (lastMessageId != pushedMessage["messageId"]) {
          await addLog(methodChannel, "Hpk processing message");
          FlutterPushedMessagingPlatform.messageController.sink
              .add(pushedMessage);
          await methodChannel.invokeMethod<bool>('setLastMessageId',
              {"lastMessageId": pushedMessage["messageId"]});
        }
      });

      huawei.Push.onNotificationOpenedApp.listen((event) async {
        var message = <String, dynamic>{};
        message["data"] = event["extras"];
        var pushedMessage =
            AndroidFlutterPushedMessaging.convertMessage(message);
        await clickOnPush(pushedMessage, "Hpk");
      });

      huawei.Push.registerBackgroundMessageHandler(
          huaweiMessagingBackgroundHandler);
      huawei.Push.getToken('');

      var initialHpkPush = await huawei.Push.getInitialNotification();
      if (initialHpkPush != null) {
        var message = <String, dynamic>{};
        message["data"] = initialHpkPush["extras"];
        initialPush = AndroidFlutterPushedMessaging.convertMessage(message);
        //await clickOnPush(pushedMessage, "Hpk");
      }
      for (var counter = 0; counter < 30; counter++) {
        if (hpkToken != null) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      await addLog(methodChannel, "Cant initialize Hpk");
    }
    //***********

    //Fcm
    String? fbToken;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      fbToken = await (FirebaseMessaging.instance.getToken());
    } catch (_) {
      await addLog(methodChannel, "Cant initialize Fcm");
    }
    if (fbToken != null) {
      await addLog(methodChannel, 'firebaseDeviceToken: $fbToken');
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        var pushedMessage =
            AndroidFlutterPushedMessaging.convertMessage(message.toMap());
        await addLog(methodChannel, 'Firebase onMessage: $pushedMessage');
        var token = await methodChannel.invokeMethod<String>('getToken');
        await FlutterPushedMessagingPlatform.confirmDelivered(token ?? "",
            pushedMessage["messageId"], "Fcm", pushedMessage["mfTraceId"]);
        var lastMessageId =
            await methodChannel.invokeMethod<String>('getLastMessageId');
        if (lastMessageId != pushedMessage["messageId"]) {
          await addLog(methodChannel, "Fcm processing message");
          FlutterPushedMessagingPlatform.messageController.sink
              .add(pushedMessage);
          await methodChannel.invokeMethod<bool>('setLastMessageId',
              {"lastMessageId": pushedMessage["messageId"]});
        }
      });
    }
    //***********
    methodChannel.setMethodCallHandler(_handle);
    var token = await methodChannel.invokeMethod<String>('getToken');
    var ruStoreToken =
        await methodChannel.invokeMethod<String?>('getRuStoreToken');
    var newToken = await getNewToken(token ?? "",
        fcmToken: fbToken, hpkToken: hpkToken, ruStoreToken: ruStoreToken);
    if (token != newToken && newToken != "") {
      token = newToken;
      await methodChannel.invokeMethod<bool>('setToken', {"token": token});
    }
    if (token == "") return false;
    messageCallback = backgroundMessageHandler;
    final CallbackHandle? handle =
        PluginUtilities.getCallbackHandle(backgroundMessageHandler);
    final result = await methodChannel.invokeMethod<dynamic>('init', {
          "backgroundHandle": handle?.toRawHandle(),
          "title": title,
          "body": body
        }) ??
        false;
    if (!result) {
      await methodChannel.invokeMethod<bool>('setToken', {"token": ""});
      return false;
    }
    FlutterPushedMessagingPlatform.pushToken = token;
    if (initialPush != null) {
      clickOnPush(initialPush!, "Hpk");
    }
    return true;
  }
}
