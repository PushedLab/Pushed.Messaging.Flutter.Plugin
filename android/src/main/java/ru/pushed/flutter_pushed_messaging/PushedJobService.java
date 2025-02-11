package ru.pushed.flutter_pushed_messaging;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.NonNull;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class PushedJobService extends JobService implements MethodChannel.MethodCallHandler{
    private static final String TAG = "PushedJobService";
    private static volatile PushedJobService activeService=null;
    private JobParameters activeJob=null;
    private SharedPreferences pref=null;
    private FlutterEngine backgroundEngine=null;
    private MethodChannel methodChannel;
    private boolean isWebSocketActive=false;
    public static volatile PowerManager.WakeLock lockStatic = null;

    @Override
    public boolean onStartJob(JobParameters jobParameters) {

        Log.v(TAG, "Start Job "+jobParameters.getJobId());
        if(pref==null) pref=getSharedPreferences("pushed", Context.MODE_PRIVATE);
        FlutterPushedMessagingPlugin.addLogEvent(pref,"Start Job "+jobParameters.getJobId());
        boolean restarted=pref.getBoolean("restarted",false);
        if(restarted) return false;
        if(BackgroundService.active) {
            if (startMyJob(getApplicationContext(), 10000, 15000, jobParameters.getJobId() + 1)) {
                Log.v(TAG, "Scheduled");
                FlutterPushedMessagingPlugin.addLogEvent(pref,"Scheduled");
            }
            return false;
        }
        try{
            String token=pref.getString("token","");
            if(token.length()>0) {
                getApplicationContext().startService(new Intent(getApplicationContext(), BackgroundService.class));
            }
            pref.edit().putBoolean("restarted",true).apply();
            return false;
        } catch (Exception e){
            FlutterPushedMessagingPlugin.addLogEvent(pref,"Exception: "+e.getMessage());
            if(BackgroundService.active) return false;
        }
        if (activeService!=null && activeService.chkFlutter()) return false;
        activeJob=jobParameters;
        activeService=this;
        return startFlutterHandler();
    }

    @Override
    public boolean onStopJob(JobParameters jobParameters) {
        Log.v(TAG, "Stop Job");
        FlutterPushedMessagingPlugin.addLogEvent(pref,"on Stop Job "+jobParameters.getJobId());

        if(backgroundEngine!=null){
            backgroundEngine.getServiceControlSurface().detachFromService();
            backgroundEngine.destroy();
            backgroundEngine = null;
        }
        if(activeService==this) activeService=null;
        if(!BackgroundService.active)
            if (startMyJob(getApplicationContext(), 3000, 5000, jobParameters.getJobId() + 1)) {
                Log.v(TAG, "Scheduled");
                FlutterPushedMessagingPlugin.addLogEvent(pref,"Scheduled");
            }
        return false;
    }
    public static boolean startMyJob(Context  pkg, int minDelay, int deadDelay,int jobId){
        ComponentName jobService = new ComponentName(pkg, PushedJobService.class);
        JobInfo.Builder exerciseJobBuilder = new JobInfo.Builder(jobId, jobService);
        exerciseJobBuilder.setMinimumLatency(minDelay);
        exerciseJobBuilder.setOverrideDeadline(deadDelay);
        exerciseJobBuilder.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY);
        exerciseJobBuilder.setRequiresDeviceIdle(false);
        exerciseJobBuilder.setRequiresCharging(false);
        exerciseJobBuilder.setPersisted(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            exerciseJobBuilder.setPriority(JobInfo.PRIORITY_HIGH);
        }
        exerciseJobBuilder.setBackoffCriteria(20000, JobInfo.BACKOFF_POLICY_LINEAR);

        Log.i(TAG, "scheduleJob: adding job to scheduler");

        JobScheduler jobScheduler = (JobScheduler) pkg.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        return jobScheduler.schedule(exerciseJobBuilder.build()) == JobScheduler.RESULT_SUCCESS;
    }

    public boolean chkFlutter(){
        if(!isWebSocketActive){
            if(backgroundEngine!=null){
                backgroundEngine.getServiceControlSurface().detachFromService();
                backgroundEngine.destroy();
                backgroundEngine = null;
            }
            if(activeService==this) activeService=null;
            FlutterPushedMessagingPlugin.addLogEvent(pref,"Stop Job "+activeJob.getJobId());
            jobFinished(activeJob,false);
            return false;
        }
        if (methodChannel != null) {
            try {
                methodChannel.invokeMethod("data", new JSONObject("{\"method\":\"reconnect\"}"));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        return true;
    }

    public boolean startFlutterHandler() {
        Log.v(TAG, "Starting flutter engine for job service");
        FlutterPushedMessagingPlugin.addLogEvent(pref,"Starting flutter engine for job service");
        backgroundEngine = new FlutterEngine(this);
        backgroundEngine.getServiceControlSurface().attachToService(PushedJobService.this, null, false);
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
        DartExecutor.DartEntrypoint dartEntrypoint = new DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart", "entrypoint");
        Long backgroundHandle=pref.getLong("backgroundHandle", 0);
        String token=pref.getString("token","");
        final List<String> args = new ArrayList<>();
        args.add(String.valueOf(backgroundHandle));
        args.add(token);
        args.add("job");
        backgroundEngine.getDartExecutor().executeDartEntrypoint(dartEntrypoint, args);
        return true;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        String method = call.method;
        if (method.equalsIgnoreCase("lock")) {
            if(lockStatic!=null && !lockStatic.isHeld()){
                lockStatic.acquire(60*1000L);
                FlutterPushedMessagingPlugin.addLogEvent(pref,"Lock");
            }
            result.success(true);
        }
        else if (method.equalsIgnoreCase("unlock")) {
            if(lockStatic!=null && lockStatic.isHeld()) {
                FlutterPushedMessagingPlugin.addLogEvent(pref,"Unlock");
                lockStatic.release();
            }
            result.success(true);
        }
        else if (method.equalsIgnoreCase("log")) {
            String event= call.argument("event");
            FlutterPushedMessagingPlugin.addLogEvent(pref,event);
            result.success(true);
        }
        else if (method.equalsIgnoreCase("data")) {
            isWebSocketActive=((int)call.argument("status"))==2;
            FlutterPushedMessagingPlugin.addLogEvent(pref,"Status changed: "+isWebSocketActive);

            result.success(true);
        }
        else if (method.equalsIgnoreCase("error")) {

            isWebSocketActive=false;
            if (startMyJob(getApplicationContext(), 3000, 5000, activeJob.getJobId() + 1)) {
                Log.v(TAG, "Scheduled");
                FlutterPushedMessagingPlugin.addLogEvent(pref,"Scheduled");
            }
            result.success(true);
        }
        else {
            result.notImplemented();
        }
    }
}
