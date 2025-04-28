import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';

@pragma('vm:entry-point')
Future<void> backgroundMessage(Map<dynamic, dynamic> message) async {
  WidgetsFlutterBinding.ensureInitialized();
  print("Backgroung message: $message");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterPushedMessaging.init(backgroundMessage,notificationChannel: "messages", askPermissions: true, loggerEnabled: false);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ServiceStatus _status = FlutterPushedMessaging.status;
  String _title = '';
  String _body = '';
  String _token = '';



  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    FlutterPushedMessaging.onMessage().listen((message){
      print("Message: $message");
      var title = (message["data"]["title"]) ?? "";
      var body = (message["data"]["body"]) ?? "";
      if (title != "" || body != "") {
        setState(() {
          _title = title;
          _body = body;
        });
      }
    });
    FlutterPushedMessaging.onStatus().listen((status){
      setState(() {
        _status = status;
      });
    });

    if (!mounted) return;

    setState(() {
      _title = '';
      _token = FlutterPushedMessaging.token ?? "";
      _status = FlutterPushedMessaging.status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pushed messaging plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              Text("Service status: $_status",
              style: Theme.of(context).textTheme.titleMedium),
              Text(_title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                _body,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
              Text(
                _token,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _token));
                  },
                  child: Text("Copy token",
                      style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: await FlutterPushedMessaging.getLog() ?? ""));
                    },
                    child: Text("Get Log",
                        style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
