import 'package:flutter/services.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AndroidFlutterPushedMessaging platform = AndroidFlutterPushedMessaging();
  const MethodChannel channel = MethodChannel('flutter_pushed_messaging');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

}
