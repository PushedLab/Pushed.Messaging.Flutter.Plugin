package ru.pushed.flutter_pushed_messaging;

import static android.content.Context.ALARM_SERVICE;
import static android.os.Build.VERSION.SDK_INT;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;




import java.util.Objects;

public class WatchdogReceiver extends BroadcastReceiver {
    private static final int QUEUE_REQUEST_ID = 111;
    private static final String ACTION_RESPAWN = "pushed.background_service.RESPAWN";
    public static int numPlaned=0;
    public static void enqueue(Context context) {
        enqueue(context, 900000);
    }
    public static void enqueue(Context context, int millis) {
        numPlaned++;
        Intent intent = new Intent(context, WatchdogReceiver.class);
        intent.setAction(ACTION_RESPAWN);
        AlarmManager manager = (AlarmManager) context.getSystemService(ALARM_SERVICE);

        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (SDK_INT >= Build.VERSION_CODES.S) {
            flags |= PendingIntent.FLAG_MUTABLE;
        }

        PendingIntent pIntent = PendingIntent.getBroadcast(context, QUEUE_REQUEST_ID, intent, flags);
        manager.set(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + millis, pIntent);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (Objects.equals(intent.getAction(), ACTION_RESPAWN)) {
            if(numPlaned>0) numPlaned--;
            SharedPreferences pref=context.getSharedPreferences("pushed", Context.MODE_PRIVATE);
            String token=pref.getString("token","");
            if(token.length()>0) {
                try{
                    context.startService(new Intent(context, BackgroundService.class));
                    if(!BackgroundService.active) pref.edit().putBoolean("restarted",true).apply();
                    FlutterPushedMessagingPlugin.addLogEvent(pref,"Alarm start service");
                }
                catch (Exception e) {
                    if(!BackgroundService.active){
                        pref.edit().putBoolean("restarted",false).apply();
                        boolean result=PushedJobService.startMyJob(context,3000,5000,1);
                        FlutterPushedMessagingPlugin.addLogEvent(pref,"Scheduled: "+result);
                    }
                    e.printStackTrace();
                }
            }

        }


    }
}
