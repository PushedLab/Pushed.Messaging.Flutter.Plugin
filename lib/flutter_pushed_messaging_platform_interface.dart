import 'dart:async';
import 'dart:io';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_pushed_messaging.dart';
import 'flutter_pushed_messaging_android.dart';
import 'flutter_pushed_messaging_ios.dart';

abstract class FlutterPushedMessagingPlatform extends PlatformInterface {
  /// Constructs a FlutterPushedMessagingPlatform.
  FlutterPushedMessagingPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPushedMessagingPlatform _instance = Platform.isIOS
      ? IosFlutterPushedMessaging()
      : AndroidFlutterPushedMessaging();

  static var messageController =
      StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  static var statusController =
      StreamController<ServiceStatus>.broadcast(sync: true);
  static var onMessageOpenedAppController =
      StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);

  static ServiceStatus status = ServiceStatus.notActive;
  static String? pushToken;
  static Stream<Map<dynamic, dynamic>> get onMessage =>
      messageController.stream;
  static Stream<ServiceStatus> get onStatus => statusController.stream;
  static Stream<Map<dynamic, dynamic>> get onMessageOpenedApp =>
      onMessageOpenedAppController.stream;

  static FlutterPushedMessagingPlatform get instance => _instance;

  static set instance(FlutterPushedMessagingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<Map<dynamic, dynamic>?> getInitialMessage() {
    throw UnimplementedError('getInitialMessage() has not been implemented.');
  }

  Future<bool> init(Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      [String? notificationChannel = "messages",
      bool loggerEnabled = false,
      bool askPermissions = true,
      bool serverLoggerEnabled = false,
      String? applicationId,
      bool enablePushOnForeground = true,
      String? environment]) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<void> reconnect() {
    throw UnimplementedError('reconnect() has not been implemented.');
  }

  Future<void> askPermissions(
      [bool askNotificationPermission = true,
      bool askBackgroundPermission = true]) {
    throw UnimplementedError('reconnect() has not been implemented.');
  }

  Future<String?> getLog() {
    throw UnimplementedError('getLog() has not been implemented.');
  }

  Future<String?> getToken() {
    throw UnimplementedError('getToken() has not been implemented.');
  }

  /// Set Pushed environment.
  /// Allowed: "prod", "dev", "load"
  Future<bool> setEnvironment(String environment) {
    throw UnimplementedError('setEnvironment() has not been implemented.');
  }

  /// Get current Pushed environment.
  Future<String> getEnvironment() {
    throw UnimplementedError('getEnvironment() has not been implemented.');
  }

  /// Re-issue Pushed token in the current environment.
  Future<String?> resetToken() {
    throw UnimplementedError('resetToken() has not been implemented.');
  }

  /// Returns resolved endpoints for current environment.
  Future<Map<dynamic, dynamic>> getEndpoints() {
    throw UnimplementedError('getEndpoints() has not been implemented.');
  }

  /// Reset all tokens and environment back to prod.
  Future<bool> resetAll() {
    throw UnimplementedError('resetAll() has not been implemented.');
  }

  /// Send interaction event (Show/Click/Close) for a Pushed messageId.
  Future<bool> sendInteraction(String messageId, String interaction) {
    throw UnimplementedError('sendInteraction() has not been implemented.');
  }
}
