import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_android.dart';

abstract class FlutterPushedMessagingPlatform extends PlatformInterface {

  FlutterPushedMessagingPlatform() : super(token: _token);
  static final Object _token = Object();

  static FlutterPushedMessagingPlatform _instance = AndroidFlutterPushedMessaging();
  static var messageController =StreamController<Map<String,dynamic>>.broadcast(sync: true);
  static var statusController =StreamController<ServiceStatus>.broadcast(sync: true);

  static ServiceStatus status=ServiceStatus.notActive;
  static String? pushToken;
  static FlutterPushedMessagingPlatform get instance => _instance;
  static Stream<Map<String,dynamic>> get onMessage => messageController.stream;
  static Stream<ServiceStatus> get onStatus => statusController.stream;

  static set instance(FlutterPushedMessagingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> init(Function(Map<String,dynamic>) backgroundMessageHandler,[String title="Pushed",String body="The service active"]) {
    throw UnimplementedError('init() has not been implemented.');
  }
  Future<void> reconnect() {
    throw UnimplementedError('reconnect() has not been implemented.');
  }
  Future<String?> getLog() {
    throw UnimplementedError('reconnect() has not been implemented.');
  }

}

