import 'package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterPushedMessagingPlatform
    with MockPlatformInterfaceMixin
    implements FlutterPushedMessagingPlatform {

  @override
  Future<bool> init(Function(Map<dynamic, dynamic>)? backgroundMessageHandler,
      [String? notificationChannel="messages",
        bool loggerEnabled=false,
        bool askPermissions=true,
        bool serverLoggerEnabled=false,
        String? applicationId,
        bool enablePushOnForeground =true]) {
    return Future.value(true);
  }

  @override
  Future<String?> getLog() => Future.value();

  @override
  Future<void> reconnect() {
    // TODO: implement reconnect
    throw UnimplementedError();
  }

  @override
  Future<void> askPermissions([bool askNotificationPermission = true, bool askBackgroundPermission = true]) {
    // TODO: implement askPermissions
    throw UnimplementedError();
  }

  @override
  Future<Map?> getInitialMessage() {
    // TODO: implement getInitialMessage
    throw UnimplementedError();
  }
}

void main() {
  final FlutterPushedMessagingPlatform initialPlatform = FlutterPushedMessagingPlatform.instance;

  test('$AndroidFlutterPushedMessaging is the default instance', () {
    expect(initialPlatform, isInstanceOf<AndroidFlutterPushedMessaging>());
  });


}
