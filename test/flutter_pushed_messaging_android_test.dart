import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart';

void main() {
  AndroidFlutterPushedMessaging platform = AndroidFlutterPushedMessaging();
  const MethodChannel channel = MethodChannel('flutter_pushed_messaging');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

}