package ru.pushed.flutter_pushed_messaging;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.List;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodChannel;
import ru.rustore.sdk.pushclient.messaging.model.RemoteMessage;
import ru.rustore.sdk.pushclient.messaging.service.RuStoreMessagingService;

public class RuStorePushService extends RuStoreMessagingService {
    private static final String TAG = "RuStoreService";

    private FlutterEngine backgroundEngine=null;
    @Override
    public void onMessageReceived(@NonNull RemoteMessage message){

        Log.v(TAG,"RuStore Message: "+message);
        Map<String,Object> msg= new HashMap<>();
        Map<String,Object> data= new HashMap<>(message.getData());


        msg.put("transport","ruStore");
        msg.put("type","message");
        msg.put("data",data);
        if(message.getNotification() != null) {
            String tittle=message.getNotification().getTitle();
            String body=message.getNotification().getBody();
            if(tittle!=null) msg.put("title", message.getNotification().getTitle());
            if(body!=null) msg.put("body", message.getNotification().getTitle());
        }
        JSONObject json=new JSONObject(msg);
        if(FlutterPushedMessagingPlugin.isApplicationForeground(getApplicationContext())){
            MessageLiveData.getInstance().postRemoteMessage(json);
        }
        else startFlutterHandler(json.toString());
    }
    public void startFlutterHandler(String msg) {

        Handler mainHandler = new Handler(Looper.getMainLooper());
        mainHandler.post(() ->{
            try {
                if(backgroundEngine!=null)
                    backgroundEngine.destroy();
                backgroundEngine = new FlutterEngine(getApplicationContext());
                FlutterLoader flutterLoader = FlutterInjector.instance().flutterLoader();
                if (!flutterLoader.initialized()) {
                    flutterLoader.startInitialization(getApplicationContext());
                }
                flutterLoader.ensureInitializationComplete(getApplicationContext(), null);
                DartExecutor.DartEntrypoint dartEntrypoint = new DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart", "ruStoreEntrypoint");
                SharedPreferences pref = getSharedPreferences("pushed", Context.MODE_PRIVATE);
                Long backgroundHandle=pref.getLong("backgroundHandle", 0);
                String token=pref.getString("token","");
                final List<String> args = new ArrayList<>();
                args.add(msg);
                backgroundEngine.getDartExecutor().executeDartEntrypoint(dartEntrypoint, args);
            } catch (Exception e){
                e.printStackTrace();
            }
        });




    }


}
