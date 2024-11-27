package ru.pushed.flutter_pushed_messaging;

import androidx.lifecycle.LiveData;

import org.json.JSONObject;

public class MessageLiveData extends LiveData<JSONObject> {
    private static MessageLiveData instance;

    public static MessageLiveData getInstance() {
        if (instance == null) {
            instance = new MessageLiveData();
        }
        return instance;
    }

    public void postRemoteMessage(JSONObject message) {
        postValue(message);
    }
}
