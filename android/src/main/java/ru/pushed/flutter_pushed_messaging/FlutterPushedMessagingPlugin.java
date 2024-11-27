package ru.pushed.flutter_pushed_messaging;

import android.app.ActivityManager;
import android.app.KeyguardManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;
import android.provider.Settings;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.Observer;

import org.json.JSONObject;

import java.util.Calendar;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import ru.rustore.sdk.pushclient.RuStorePushClient;

/** FlutterPushedMessagingPlugin */
public class FlutterPushedMessagingPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

  public MethodChannel channel;
  private Context context;
  private static final String TAG = "PushedServicePlugin";
  private final int binderId = (int) (System.currentTimeMillis() / 1000);
  private Handler mainHandler;
  private final LiveData<JSONObject> liveDataMessage =
          MessageLiveData.getInstance();
  private Observer<JSONObject> messageObserver;
  private boolean mShouldUnbind = false;
  private IBackgroundServiceBinder serviceBinder;
  public ActivityPluginBinding  activityBinding=null;
  private String ruStoreToken=null;
  private SharedPreferences pref=null;
  private final ServiceConnection serviceConnection = new ServiceConnection() {

    @Override
    public void onServiceConnected(ComponentName name, IBinder service) {
      serviceBinder = IBackgroundServiceBinder.Stub.asInterface(service);
      try {
        IBackgroundService listener = new IBackgroundService.Stub() {
          @Override
          public void invoke(String data) {
            try {
              JSONObject call = new JSONObject(data);
              receiveData(call);
            } catch (Exception e) {
              e.printStackTrace();
            }
          }

          @Override
          public void stop() {
            if (context != null && serviceBinder != null) {
              mShouldUnbind = false;
              context.unbindService(serviceConnection);
            }
          }
        };

        serviceBinder.bind(binderId, listener);
      } catch (Exception e) {
        e.printStackTrace();
      }
    }

    @Override
    public void onServiceDisconnected(ComponentName name) {
      try {
        mShouldUnbind = false;
        serviceBinder.unbind(binderId);
        serviceBinder = null;
      } catch (Exception e) {
        e.printStackTrace();
      }
    }
  };

  static boolean isApplicationForeground(Context context) {
    KeyguardManager keyguardManager =
            (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);

    if (keyguardManager != null && keyguardManager.isKeyguardLocked()) {
      return false;
    }

    ActivityManager activityManager =
            (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
    if (activityManager == null) return false;

    List<ActivityManager.RunningAppProcessInfo> appProcesses =
            activityManager.getRunningAppProcesses();
    if (appProcesses == null) return false;

    final String packageName = context.getPackageName();
    for (ActivityManager.RunningAppProcessInfo appProcess : appProcesses) {
      if (appProcess.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
              && appProcess.processName.equals(packageName)) {
        return true;
      }
    }

    return false;
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    Log.v(TAG, "Pushed plugin attached to engine");
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_pushed_messaging", JSONMethodCodec.INSTANCE);
    channel.setMethodCallHandler(this);
    this.context=flutterPluginBinding.getApplicationContext();
    pref=context.getSharedPreferences("pushed", Context.MODE_PRIVATE);
    mShouldUnbind = false;
    mainHandler = new Handler(context.getMainLooper());
    try{
      RuStorePushClient.INSTANCE.getToken().addOnSuccessListener((token) -> {
      ruStoreToken=token;
    });
    } catch (Exception e){
      Log.v(TAG,"RuStore inialization Error: "+e.getMessage());
    }

    messageObserver =
            message -> {
            channel.invokeMethod("onReceiveData", message);
            };
    liveDataMessage.observeForever(messageObserver);

  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    JSONObject arg = (JSONObject) call.arguments;
    if (call.method.equals("init")) {
      long backgroundHandle;
      String title,body;
      try {
        backgroundHandle=arg.getLong("backgroundHandle");
        title=arg.getString("title");
        body=arg.getString("body");
      }
      catch (Exception e)
      {
        backgroundHandle=0;
        title="Pushed";
        body="The service active";
      }
      pref.edit().putLong("backgroundHandle", backgroundHandle).apply();
      pref.edit().putString("title", title).apply();
      pref.edit().putString("body", body).apply();
      result.success(init());
    } else if (call.method.equals("setToken")) {
      try {
        pref.edit().putString("token", arg.getString("token")).apply();
        result.success(true);
      }
      catch (Exception e)
      {
        result.error("Get params Error",e.getMessage(),e);
      }
    }
    else if (call.method.equals("setLastMessageId")) {
      try {
        pref.edit().putString("lastMessageId", arg.getString("lastMessageId")).apply();
        result.success(true);
      }
      catch (Exception e)
      {
        result.error("Get params Error",e.getMessage(),e);
      }
    }
    else if (call.method.equals("getLastMessageId")) {
      String messageId = pref.getString("lastMessageId","");
      result.success(messageId);
    }
    else if (call.method.equals("getToken")) {
      String token = pref.getString("token","");
      result.success(token);
    }
    else if (call.method.equals("getRuStoreToken")) {
      result.success(ruStoreToken);
    }
    else if (call.method.equals("getHandle")) {
      long handle = pref.getLong("backgroundHandle",0);
      result.success(handle);
    }
    else if (call.method.equalsIgnoreCase("log")) {
      String event=(String)call.argument("event");
      addLogEvent(event);
      result.success(true);
    }
    else if (call.method.equalsIgnoreCase("getlog")) {
      String log=pref.getString("log","");
      result.success(log);
    }
    else if (serviceBinder != null) {
      try {
        serviceBinder.invoke(call.arguments.toString());
        result.success(true);
      } catch (Exception ex) {
        Log.v(TAG, ex.getMessage());
        result.error("Service invoke error", ex.getMessage(), ex);
      }
    }
    else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
    if (mShouldUnbind && serviceBinder != null) {
      binding.getApplicationContext().unbindService(serviceConnection);
      mShouldUnbind = false;
    }
    liveDataMessage.removeObserver(messageObserver);

  }
  public void addLogEvent(String event) {
     String date= Calendar.getInstance().getTime().toString();
     String fEvent=date+": "+event+"\n";
     String log=pref.getString("log","");
     pref.edit().putString("log", log+fEvent).apply();

  }

  public void receiveData(JSONObject data) {



    HiddenLifecycleReference reference =
            (HiddenLifecycleReference) activityBinding.getLifecycle();
    String method=reference.getLifecycle().getCurrentState() == Lifecycle.State.RESUMED?"onReceiveData":"onReceiveDataBg";
    mainHandler.post(() -> {
      if (channel != null) {
        channel.invokeMethod(method, data);
      }
    });
  }
  private void start(boolean isForeground) {
    Intent intent = new Intent(context, BackgroundService.class);
    intent.putExtra("binder_id", binderId);
    if (isForeground) {
      ContextCompat.startForegroundService(context, intent);
    } else {
      context.startService(intent);
    }
    mShouldUnbind = context.bindService(intent, serviceConnection,Context.BIND_AUTO_CREATE);
  }

  private boolean init() {
    boolean firstRun=pref.getBoolean("first_run",true);
    if(activityBinding!=null) {
      String packageName = activityBinding.getActivity().getPackageName();
      PowerManager pm = (PowerManager) activityBinding.getActivity().getSystemService(Context.POWER_SERVICE);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        if (!pm.isIgnoringBatteryOptimizations(packageName) && firstRun) {
          Intent intent = new Intent();
          intent.setAction(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
          intent.setData(Uri.parse("package:" + packageName));
          activityBinding.getActivity().startActivity(intent);
        }
    }
    boolean foreground=false;
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      foreground=true;
      NotificationChannel channel = new NotificationChannel("pushed","Pushed", NotificationManager.IMPORTANCE_NONE);
      NotificationManager manager = context.getSystemService(NotificationManager.class);
      channel.setShowBadge(false);
      manager.createNotificationChannel(channel);
    }
    start(foreground);
    pref.edit().putBoolean("foreground",foreground).apply();
    pref.edit().putBoolean("first_run",false).apply();

    return true;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    Log.v(TAG, "Pushed plugin attached to activity");
    activityBinding=binding;

  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    Log.v(TAG, "Pushed plugin attached to activity");
    activityBinding=binding;
  }

  @Override
  public void onDetachedFromActivity() {
    Log.v(TAG, "Pushed plugin detached to activity");
    if(mShouldUnbind){
      try {
        mShouldUnbind = false;
        serviceBinder.unbind(binderId);
        serviceBinder = null;
      } catch (Exception e) {
        e.printStackTrace();
      }
    }
    activityBinding=null;

  }
}
