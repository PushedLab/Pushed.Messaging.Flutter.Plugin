package ru.pushed.flutter_pushed_messaging;

import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class BackgroundService extends Service implements MethodChannel.MethodCallHandler{
    private static final String TAG = "PushedBackgroundService";
    private MethodChannel methodChannel;
    private Handler mainHandler;
    private FlutterEngine backgroundEngine;
    private DartExecutor.DartEntrypoint dartEntrypoint;
    private SharedPreferences pref=null;
    private boolean foreground=false;
    final Map<Integer, IBackgroundService> listeners = new HashMap<>();
    public static volatile PowerManager.WakeLock lockStatic = null;
    private final IBackgroundServiceBinder.Stub binder = new IBackgroundServiceBinder.Stub() {

        @Override
        public void bind(int id, IBackgroundService service) {
            synchronized (listeners) {
                listeners.put(id, service);
            }
        }

        @Override
        public void unbind(int id) {
            synchronized (listeners) {
                listeners.remove(id);
            }
        }

        @Override
        public void invoke(String data) {
            try {
                JSONObject call = new JSONObject(data);
                receiveData(call);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    };

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public boolean onUnbind(Intent intent) {
        final int binderId = intent.getIntExtra("binder_id", 0);
        if (binderId != 0) {
            synchronized (listeners) {
                listeners.remove(binderId);
            }
        }
        return super.onUnbind(intent);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        pref=getSharedPreferences("pushed", Context.MODE_PRIVATE);

        mainHandler = new Handler(Looper.getMainLooper());
        foreground=pref.getBoolean("foreground",false);
        if(foreground) {

            String packageName = getApplicationContext().getPackageName();
            Intent i = getPackageManager().getLaunchIntentForPackage(packageName);

            int flags = PendingIntent.FLAG_CANCEL_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_MUTABLE;
            }
            PendingIntent pi = PendingIntent.getActivity(BackgroundService.this, 11, i, flags);
            NotificationCompat.Builder mBuilder = new NotificationCompat.Builder(this, "pushed")
                    .setSmallIcon(R.drawable.ic_bg_service_small)
                    .setAutoCancel(true)
                    .setOngoing(false)
                    .setContentTitle(pref.getString("title","Pushed"))
                    .setContentText(pref.getString("body","The service is active"))
                    .setCategory("")
                    .setVisibility(NotificationCompat.VISIBILITY_SECRET)
                    .setContentIntent(pi);
            startForeground(101, mBuilder.build());
        }
    }
    @Override
    public void onDestroy() {
        stopForeground(true);
        methodChannel = null;
        if (backgroundEngine != null) {
            backgroundEngine.getServiceControlSurface().detachFromService();
            backgroundEngine.destroy();
            backgroundEngine = null;
        }
        dartEntrypoint=null;
        lockStatic=null;
        super.onDestroy();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if(WatchdogReceiver.numPlaned<=0) WatchdogReceiver.enqueue(this);
        if (backgroundEngine != null && backgroundEngine.getDartExecutor().isExecutingDart()) {
            Log.v(TAG, "!Service already running, using existing service!");
            try{
                receiveData(new JSONObject("{\"method\":\"reconnect\"}"));}
            catch (Exception e){
                e.printStackTrace();
            }
            return START_STICKY;
        }
        Log.v(TAG, "Starting flutter engine for background service");
        backgroundEngine = new FlutterEngine(this);
        backgroundEngine.getServiceControlSurface().attachToService(BackgroundService.this, null, foreground);
        if(lockStatic==null) {
            PowerManager mgr = (PowerManager) getApplicationContext()
                    .getSystemService(Context.POWER_SERVICE);
            lockStatic = mgr.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
                    BackgroundService.class.getName());
            lockStatic.setReferenceCounted(true);
        }
        methodChannel = new MethodChannel(backgroundEngine.getDartExecutor().getBinaryMessenger(), "flutter_pushed_messaging_bg", JSONMethodCodec.INSTANCE);
        methodChannel.setMethodCallHandler(this);

        FlutterLoader flutterLoader = FlutterInjector.instance().flutterLoader();
        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(getApplicationContext());
        }
        flutterLoader.ensureInitializationComplete(getApplicationContext(), null);
        dartEntrypoint = new DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "package:flutter_pushed/flutter_pushed_platform_interface.dart", "entrypoint");

        Long backgroundHandle=pref.getLong("backgroundHandle", 0);
        String token=pref.getString("token","");
        final List<String> args = new ArrayList<>();
        args.add(String.valueOf(backgroundHandle));
        args.add(token);
        backgroundEngine.getDartExecutor().executeDartEntrypoint(dartEntrypoint, args);
        return START_STICKY;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        String method = call.method;
        if (method.equalsIgnoreCase("data")) {
            try {
                synchronized (listeners) {
                    if(listeners.size()>0) {
                        for (Integer key : listeners.keySet()) {
                            IBackgroundService listener = listeners.get(key);
                            if (listener != null) {
                                Log.v(TAG, call.arguments.toString());
                                listener.invoke(call.arguments.toString());
                            }
                        }
                        result.success(true);
                    }
                    else result.success(false);
                }
            } catch (Exception e) {
                result.error("send-data-failure", e.getMessage(), e);
            }
        }
        else if (method.equalsIgnoreCase("lock")) {
            if(lockStatic!=null && !lockStatic.isHeld())
                lockStatic.acquire(60*1000L);
            result.success(true);
        }
        else if (method.equalsIgnoreCase("unlock")) {
            if(lockStatic!=null && lockStatic.isHeld()) {
                lockStatic.release();
            }
            result.success(true);
        }
        else {
            result.notImplemented();
        }

    }
    public void receiveData(JSONObject data) {
        if (methodChannel != null) {
            try {
                final JSONObject arg = data;
                mainHandler.post(() -> methodChannel.invokeMethod("data", arg));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

}
