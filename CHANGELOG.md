## 1.8.3
* The `applicationId` stored for the native APNs callback is now cleared when the
  host app passes an empty/absent value, instead of keeping the id from a previous
  environment. A stale id made `/v2/tokens` answer `Application Not Found` (4041)
  on every request that carried the APNs device token, so the APNs transport was
  never registered and pushes silently stopped arriving.
* No environment carries a built-in `applicationId` any more — the value comes from
  the host app only; the per-environment table is an empty fallback.
* Android: same handling, so both platforms resolve `applicationId` identically.
* iOS: bumped PushedMessagingiOSLibrary to 1.2.2 — the client now adopts the token the
  server returns instead of keeping one the server no longer knows. The stale token made
  the WebSocket handshake fail (`HTTPUpgradeError`) and publishes to it silently
  undelivered, which only a manual token reset worked around.

## 1.8.2
* Android: the client token is now delivered to Dart as soon as it arrives. Previously
  `PushedService.start()` returned null on a first run (the token is fetched on a
  background thread) and nothing notified Dart afterwards, so the token only showed up
  on the next app launch. Also fixes `resetToken()` returning null on Android.

## 1.8.1
* Android: fixed `Project with path ':messaginglibrary' could not be found` — the
  published package pointed at a local Gradle module instead of the JitPack
  artifact (`com.github.PushedLab:Pushed.Messaging.Android.Library:1.5.8.1`)
* The `applicationId` passed to `init()` is now used as-is on both platforms.
  Previously it was discarded and replaced by an id derived from `environment`,
  so apps on `prod` registered with an empty `applicationId`

## 1.8.0
* iOS: fixed WebSocket not connecting after a cold start — connecting is no longer
  tied to a connectivity-change event, the native library connects as soon as the
  client token is available
* iOS: background tasks are now scheduled for WebSocket mode
  (`FlutterPushedMessagingPlugin.registerBackgroundTasksAtLaunch()` must be called
  from `AppDelegate.didFinishLaunchingWithOptions` — see README)
* Added `getToken()`, `resetToken()`, `resetAll()`, `setEnvironment()`,
  `getEnvironment()`, `getEndpoints()` and `sendInteraction()` to the public API
* Per-environment token storage moved to Keychain
* Android: reworked native plugin (environment support, token handling)

## 1.7.0
* Pass ios part of plugin to native SWIFT Pushed Lib

## 1.6.9
* Pass current sdk version on app init
* Improved control of duplicate messages

## 1.6.8
* Tracking push clicks 

## 1.6.7
* Fixed a bug on FCM and RuStore initialization

## 1.6.6

* Updated Android native library to version 1.4.6:
  * Added dynamic SDK version support
  * Improved security by setting android:exported to false for internal components
  * Added platform field in API requests
  * Various code improvements and optimizations

## 1.6.5

* Now you can use your application Id when initializing the plugin.
* Improved support RuStore.

## 1.6.3

* Added support iOS extensions.
* Improved support for collecting device statistics.

## 1.6.2

* The work of the background services has been improved.
* Added support for collecting device statistics.

## 1.6.1

* Added support for new statuses.

## 1.6.0

* Added the ability to display notifications.
* Added the ability to manage permission requests.
* Removed dependencies on some third-party plugins.

## 1.5.1

* Fixed a bug that occurs on some devices when working with Hpk.

## 1.5.0

* The principle of operation of the plugin in the backround has been changed.

## 1.4.0

* Added RuStore support.

## 1.3.0

* Added Fcm and Hpk support.


## 1.2.0

* Added iOS support.
* The SHEDULE_EXACT_ALARM permission is no longer required for the plugin to work for Android.

## 1.1.0

* Bumped `compileSdk` to 34.
* Updated `compileSdk` and `targetSdkVersion` of example app to 34.
* Flutter SDK version will be bumped to make it easier to maintain the plugin.
* Update a dependency to the latest release.
* Added a mechanism for confirming the delivery of a message.
* ClientTokens can now be deleted if they are not used for a long time. And in this case, they will be updated.
* Added logging of the service in the debug mode (FlutterPushedMessaging.getLog()).

## 1.0.4

* Minor fixes

## 1.0.1

* Initial release.
