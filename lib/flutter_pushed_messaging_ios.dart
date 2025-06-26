import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_platform_interface.dart';

class IosFlutterPushedMessaging extends FlutterPushedMessagingPlatform {
  var active = false;
  var connected = false;
  StreamSubscription? subs;
  WebSocketChannel? webChannel;

  /// The method channel used to interact with the native platform.

  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pushed_messaging');
  Function(Map<dynamic, dynamic>)? messageCallback;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method.startsWith("onReceiveData")) {
      try {
        var data = json.decode(call.arguments["data"]);
        call.arguments["data"] = data;
      } catch (_) {}
    }
    switch (call.method) {
      case "reconnect":
        if (active) {
          await addLog("Reconnect");
          webChannel?.sink.close();
        }

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
      bool serverLoggerEnabled = false]) async {
    messageCallback = backgroundMessageHandler;
    methodChannel.setMethodCallHandler(_handle);
    var result = await methodChannel.invokeMethod<String>(
        'init', {"log": loggerEnabled, "serverlog": loggerEnabled});
    if (result != "") {
      if (askPermissions) {
        await methodChannel
            .invokeMethod<bool>('requestNotificationPermissions');
      }
      FlutterPushedMessagingPlatform.pushToken = result;
      FlutterPushedMessagingPlatform.status = ServiceStatus.disconnected;
      List<ConnectivityResult> lastConnectivity = [];
      Connectivity().onConnectivityChanged.listen((result) async {
        await addLog("Connectivity changed: $result");
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
        connect();
      });

      return true;
    }
    return false;
  }

  @override
  Future<void> askPermissions(
      [bool askNotificationPermission = true,
      bool askBackgroundPermission = true]) async {
    if (askNotificationPermission) {
      await methodChannel.invokeMethod<bool>('requestNotificationPermissions');
    }
  }

  Future<void> connect() async {
    if (!connected) return;
    if (active) return;
    await addLog("Connecting");
    active = true;
    try {
      await subs?.cancel();
      webChannel?.sink.close();
      webChannel = WebSocketChannel.connect(
        Uri.parse('wss://sub.pushed.ru/v2/open-websocket/${FlutterPushedMessagingPlatform.pushToken}'),
      );
      await webChannel?.ready;
      setNewStatus(ServiceStatus.active);
      subs = webChannel?.stream.listen((event) async {
        var message = utf8.decode(event);
        await addLog("Pushed message: $message");
        if (message != "ONLINE") {
          var payload = json.decode(message);
          var messageId = payload["messageId"];
          var traceId=payload["mfTraceId"];
          var valid=await methodChannel.invokeMethod<bool>("pushedMessage",{"messageId": messageId});
          if (valid==true) {
            await addLog("Pushed processing message");
            var response = json.encode(<String, dynamic>{"messageId": messageId,
              if(traceId!=null) "mfTraceId": traceId});
            webChannel?.sink.add(utf8.encode(response));
            try {
              var data = json.decode(payload["data"]);
              payload["data"] = data;
            } catch (_) {}
            FlutterPushedMessagingPlatform.messageController.sink
                .add(payload);
          }
        }

      }, onDone: () async {
        await addLog("Closed");
        active = false;
        setNewStatus(ServiceStatus.disconnected);
        await Future.delayed(const Duration(seconds: 1));
        connect();
      });
    } catch (e) {
      await addLog("Error: $e");
      setNewStatus(ServiceStatus.disconnected);
      await subs?.cancel();
      active = false;
      await Future.delayed(const Duration(seconds: 1));
      connect();
    }
  }

  Future<void> addLog(String event) async{
    await methodChannel.invokeMethod<bool>(
        'setLog', {"event": event});
  }

   void setNewStatus(ServiceStatus newStatus) {
    if(FlutterPushedMessaging.status!=newStatus){
      FlutterPushedMessagingPlatform.statusController.sink.add(newStatus);
   }
  }



}
