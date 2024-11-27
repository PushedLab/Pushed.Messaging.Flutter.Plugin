import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging_platform_interface.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterPushedMessagingPlatform
    with MockPlatformInterfaceMixin
    implements FlutterPushedMessagingPlatform {


  @override
  Future<bool> init(Function(Map<String, dynamic> message) backgroundMessageHandler, [String title = "Pushed", String body = "The service active"]) {
    return Future.value(true);
  }

  @override
  Future<void> reconnect() => Future.value();

  @override
  Future<String?> getLog() {
    // TODO: implement getLog
    throw UnimplementedError();
  }

  @override
  Future<String> getNewToken(String token, {String? apnsToken,String? fcmToken,String? hpkToken,String? ruStoreToken}) {
    // TODO: implement getNewToken
    throw UnimplementedError();
  }

  @override
  Future<bool> confirmDelivered(String token,String messageId) {
    // TODO: implement confirmDelivered
    throw UnimplementedError();
  }
}

void main() {
  final FlutterPushedMessagingPlatform initialPlatform = FlutterPushedMessagingPlatform.instance;

  test('$AndroidFlutterPushedMessaging is the default instance', () {
    expect(initialPlatform, isInstanceOf<AndroidFlutterPushedMessaging>());
  });

}
