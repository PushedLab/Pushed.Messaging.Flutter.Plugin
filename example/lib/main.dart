import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

@pragma('vm:entry-point')
Future<void> backgroundMessage(Map<String,dynamic> message) async {
  WidgetsFlutterBinding.ensureInitialized();
  var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  String title=message["title"]??"";
  String body=message["body"]??"";
  if(title!="" || body!="") {
    await flutterLocalNotificationsPlugin.show(
      8888,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
            'push_channel', // id
            'MY CHANNEL FOR PUSH',
            icon: 'launch_background',
            ongoing: false,
            importance: Importance.max,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            enableLights: true

        ),
      ),
    );
  }

}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'push_channel', // id
    'MY CHANNEL FOR PUSH', // title
    description:
    'This channel is used for push messages', // description
    importance: Importance.max, // importance must be at low or higher level
  );
  var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  await perm.Permission.notification.request();
  await FlutterPushedMessaging.init(backgroundMessage);
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

  Future<void> initPlatformState() async {
    FlutterPushedMessaging.onMessage().listen((message) {
      var title=message["title"]??"";
      String body=message["body"]??"";
      if(title!="" || body!="") {
        setState(() {
          _title=title;
          _body=body;
        });
      }
    });
    FlutterPushedMessaging.onStatus().listen((status) {
      setState(() {
        _status=status;
      });
    });
    if (!mounted) return;
    setState(() {
      _title = '';
      _token=FlutterPushedMessaging.token??"";
      _status=FlutterPushedMessaging.status;
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
              children: [Text("Service status: $_status",style: Theme.of(context).textTheme.titleMedium),
                Text(_title,style: Theme.of(context).textTheme.titleMedium),
                Text(_body,style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center, maxLines: 3,),
                Text(_token,style: Theme.of(context).textTheme.titleMedium,),
                TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _token));
                    },
                    child: Text("Copy token",style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                    onPressed: () async {
                      await FlutterPushedMessaging.reconnect();
                    },
                    child: Text("Reconnect",style: Theme.of(context).textTheme.titleMedium))],
            )
        ),
      ),
    );
  }
}
