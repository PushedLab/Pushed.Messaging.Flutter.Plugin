import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_platform_interface.dart';

WebSocketChannel? webChannel;
var active=false;
StreamSubscription? subs;
var connected=false;
var currentStatus=ServiceStatus.disconnected;

@pragma('vm:entry-point')
Future<void> entrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MethodChannel channel = const MethodChannel(
    'flutter_pushed_messaging_bg',
    JSONMethodCodec(),
  );
  await channel.invokeMethod<dynamic>("lock");
  await setNewStatus(channel, currentStatus);
  final int rawHandle = int.parse(args[0]);
  final String token=args[1];
  final callbackHandle = CallbackHandle.fromRawHandle(rawHandle);
  final onMessage = PluginUtilities.getCallbackFromHandle(callbackHandle);

  Connectivity().onConnectivityChanged.listen((result) async{
    await channel.invokeMethod<dynamic>("lock");
    if(result==ConnectivityResult.wifi) webChannel?.sink.close();
    if(result==ConnectivityResult.none) {
      connected=false;
    } else {
      connected = true;
    }
    connect(token,channel,onMessage);
  });

  channel.setMethodCallHandler((call) async {
    if(call.arguments["method"]=="reconnect" && active) {
      await channel.invokeMethod<dynamic>("lock");
      await setNewStatus(channel, currentStatus);
      webChannel?.sink.close();
    }
  });
  await Future.delayed(const Duration(seconds: 5));
  await channel.invokeMethod<dynamic>("unlock");
}

@pragma('vm:entry-point')
Future<void> setNewStatus(MethodChannel channel,ServiceStatus newStatus) async {
  currentStatus=newStatus;
  await channel.invokeMethod<dynamic>("data", {"type":"status","status":newStatus.index});
}


@pragma('vm:entry-point')
Future<void> connect(String token,MethodChannel channel,Function? onMessage) async {
  if(!connected) {
    await channel.invokeMethod<dynamic>("unlock");
    return;
  }
  if(active) return;
  active=true;
  try {
    await subs?.cancel();
    webChannel?.sink.close();
    webChannel = WebSocketChannel.connect(
      Uri.parse('wss://sub.pushed.ru/v1/$token'),
    );
    await webChannel?.ready;
    await setNewStatus(channel, ServiceStatus.active);
    subs=webChannel?.stream.listen((event) async {
      await channel.invokeMethod<dynamic>("lock");
      var message = utf8.decode(event);
      if (message != "ONLINE") {
        Map<String,dynamic> data={"type":"message","message":json.decode(message)};
        var res = await channel.invokeMethod<dynamic>(
            "data", data)??false;
        if (!res && onMessage != null) await onMessage(json.decode(message));
      }
      await Future.delayed(const Duration(seconds: 5));
      await channel.invokeMethod<dynamic>("unlock");
    },
        onDone: () async {
          await channel.invokeMethod<dynamic>("lock");
          active=false;
          await setNewStatus(channel, ServiceStatus.disconnected);
          await Future.delayed(const Duration(seconds: 1));
          connect(token,channel,onMessage);
        });
  }
  catch (e) {
    await channel.invokeMethod<dynamic>("lock");
    await setNewStatus(channel, ServiceStatus.disconnected);
    await subs?.cancel();
    active=false;
    await Future.delayed(const Duration(seconds: 1));
    connect(token,channel,onMessage);
  }

}

class AndroidFlutterPushedMessaging extends FlutterPushedMessagingPlatform {

  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pushed_messaging',JSONMethodCodec());
  Function(Map<String,dynamic>)? messageCallback;


  Future<dynamic> _handle(MethodCall call) async {
    if(call.arguments["type"]=="message") {
      switch (call.method) {
        case "onReceiveData":
          FlutterPushedMessagingPlatform.messageController.sink.add(
              call.arguments["message"]);
          break;
        case "onReceiveDataBg":
          await messageCallback!(call.arguments["message"]);
          break;
        default:
      }
    }
    if(call.arguments["type"]=="status") {
      var newStatus=ServiceStatus.values[call.arguments["status"]];
      if(FlutterPushedMessagingPlatform.status!=newStatus) {
        FlutterPushedMessagingPlatform.statusController.sink.add(newStatus);
        FlutterPushedMessagingPlatform.status=newStatus;
      }
    }
  }
  Future<String> getNewToken() async {
    dynamic token;
    try {
      var response = await http.get(
          Uri.parse('https://sub.pushed.ru/tokens')).timeout(const Duration(seconds: 10),onTimeout: (() => throw Exception("TimeOut")));
      token=json.decode(response.body)["token"];
    }
    catch (e) {
      token="";
    }
    return(token??"");
  }
  @override
  Future<void> reconnect() async{
    if(FlutterPushedMessagingPlatform.status!=ServiceStatus.notActive) {
      await methodChannel.invokeMethod<dynamic>('data',{"method":"reconnect"});
    }
  }

  @override
  Future<bool> init(Function(Map<String,dynamic>) backgroundMessageHandler,[String title="Pushed",String body="The service active"]) async {
    methodChannel.setMethodCallHandler(_handle);
    var token = await methodChannel.invokeMethod<String>('getToken');
    if(token=="") {
      token = await getNewToken();
      if (token == "") return false;
      await methodChannel.invokeMethod<bool>('setToken', {
        "token": token
      });
    }
    messageCallback=backgroundMessageHandler;
    final CallbackHandle? handle =
    PluginUtilities.getCallbackHandle(backgroundMessageHandler);
    final result = await methodChannel.invokeMethod<dynamic>('init',{
      "backgroundHandle":handle?.toRawHandle(),
      "title":title,
      "body":body
    })??false;
    if(!result) {
      await methodChannel.invokeMethod<String>('setToken', {
        "token": ""
      });
      return false;
    }
    FlutterPushedMessagingPlatform.pushToken=token;
    return true;
  }

}