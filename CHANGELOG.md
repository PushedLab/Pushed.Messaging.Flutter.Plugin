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
