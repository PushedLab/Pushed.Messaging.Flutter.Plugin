# Pushed Messaging Plugin for Flutter

A Flutter plugin to use the Pushed Messaging.

To learn more about Pushed Messaging, please visit the [Pushed website](https://pushed.ru)

## Getting Started

```yaml
# add this line to your dependencies
flutter_pushed_messaging: ^1.3.0
```

```dart
import 'flutter_pushed_messaging/flutter_pushed_messaging.dart';
```

On iOS, make sure you have correctly configured your app to support push notifications:
You need to add push notifications capability and remote notification background mode.

On iOS, add the following lines to the didFinishLaunchingWithOptions method in the 
AppDelegate.m/AppDelegate.swift file of your iOS project

```swift
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
}
```

On Android, to support Fcm, you must follow these steps:

**Step 1.** Add it in your root build.gradle add this dependencies 

```gradle
buildscript {
...
    dependencies {
        classpath 'com.google.gms:google-services:4.3.15'
        classpath 'com.google.firebase:firebase-crashlytics-gradle:2.8.1'
        ...
    }
}

```

**Step 2.** Place your google-services.json in Android/app folder

**Step 3.** Add it in your app/build.gradle add this plugins 

```gradle
...
apply plugin: 'com.google.gms.google-services'
apply plugin: 'com.google.firebase.crashlytics'
```

On Android, to support Hpk, you must follow these steps:

**Step 1.** Add it in your root build.gradle add this 

```gradle
buildscript {
...
    repositories {
        ...
        maven { url 'https://developer.huawei.com/repo/' }
    }
    dependencies {
        classpath 'com.huawei.agconnect:agcp:1.5.2.300'
        ...
    }
}
allprojects {
    repositories {
        ...
        maven { url 'https://developer.huawei.com/repo/' }
    }
}

```

**Step 2.** Place your agconnect-services.json in Android/app folder

**Step 3.** Add it in your app/build.gradle add this 

```gradle
...
dependencies {
    ...
    implementation 'com.huawei.agconnect:agconnect-core:1.5.2.300'
}
...
apply plugin: 'com.huawei.agconnect' 
```

### Implementation

```dart
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
// ...

//Messages can be handled via the backgroundMessage handler. 
//When received, an isolate is spawned allowing you to handle messages even when your application is not running.
@pragma('vm:entry-point')
Future<void> backgroundMessage(Map<String,dynamic> message) async {
	print("Handling a background message: $message");
}

void main() {
// Initializes plugin and sets backgroundMessage handler.
  await FlutterPushedMessaging.init(backgroundMessage);

// To send a message to a specific user, you need to know his Client token.
  print("Client token: ${FlutterPushedMessaging.token}");

// Listen to messages whilst your application is in the foreground
  FlutterPushedMessaging.onMessage().listen((message) {
	print("Got a message whilst in the foreground: $message");
  });

// Listen to the changes plugin status.
// ServiceStatus.notActive - The plugin is not initialized or something went wrong.
// ServiceStatus.disconnected - The plugin is initialized, but there is no connection to the server.
// ServiceStatus.active - Everything works correctly.
  FlutterPushedMessaging.onStatus().listen((status) {
	print("Plugin status: $status");
  });

  runApp(const MyApp());
}
```
