package ru.pushed.flutter_pushed_messaging;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import java.util.Objects;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Objects.equals(intent.getAction(), Intent.ACTION_BOOT_COMPLETED) || Objects.equals(intent.getAction(), "android.intent.action.QUICKBOOT_POWERON")) {
            SharedPreferences pref=context.getSharedPreferences("pushed", Context.MODE_PRIVATE);
            String token=pref.getString("token","");
            if(token.length()>0) {
                try{
                    context.startService(new Intent(context, BackgroundService.class));
                    if(!BackgroundService.active) pref.edit().putBoolean("restarted",true).apply();
                    FlutterPushedMessagingPlugin.addLogEvent(pref,"Boot start service");
                }
                catch (Exception e) {
                    if(!BackgroundService.active){
                        pref.edit().putBoolean("restarted",false).apply();
                        boolean result= PushedJobService.startMyJob(context,3000,5000,1);
                        FlutterPushedMessagingPlugin.addLogEvent(pref,"Scheduled: "+result);
                    }
                    e.printStackTrace();}
            }

        }
    }
}
