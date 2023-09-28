// IBackgroundService.aidl
package ru.pushed.flutter_pushed_messaging;

interface IBackgroundService {
       void invoke(String data);
       void stop();
}