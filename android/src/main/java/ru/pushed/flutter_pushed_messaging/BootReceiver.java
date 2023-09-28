package ru.pushed.flutter_pushed_messaging;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import androidx.core.content.ContextCompat;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent.getAction().equals(Intent.ACTION_BOOT_COMPLETED) || intent.getAction().equals("android.intent.action.QUICKBOOT_POWERON")) {
            SharedPreferences pref=context.getSharedPreferences("pushed", Context.MODE_PRIVATE);
            String token=pref.getString("token","");
            if(token.length()>0) {
                if(pref.getBoolean("foreground",false))
                    ContextCompat.startForegroundService(context, new Intent(context, BackgroundService.class));
                else
                    context.startService(new Intent(context, BackgroundService.class));
            }
        }
    }
}
