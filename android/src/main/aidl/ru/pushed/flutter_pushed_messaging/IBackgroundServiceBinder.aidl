// IBackgroundServiceBinder.aidl
package ru.pushed.flutter_pushed_messaging;

import ru.pushed.flutter_pushed_messaging.IBackgroundService;

interface IBackgroundServiceBinder {
       void bind(int id, IBackgroundService service);
       void unbind(int id);
       void invoke(String data);
}