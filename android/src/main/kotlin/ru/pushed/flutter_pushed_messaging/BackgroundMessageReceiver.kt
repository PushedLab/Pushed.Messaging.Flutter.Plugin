package ru.pushed.flutter_pushed_messaging

import android.content.Context
import android.os.PowerManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.JSONMethodCodec
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import ru.pushed.messaginglibrary.BackgroundService
import ru.pushed.messaginglibrary.MessageReceiver
import ru.pushed.messaginglibrary.PushedService


class BackgroundMessageReceiver : MessageReceiver(){
    //private var backgroundEngine: FlutterEngine? = null
    companion object {
        @Volatile
        var backgroundEngine: FlutterEngine? = null
    }

    override fun onBackgroundMessage(context: Context?, message: JSONObject) {
        if(context==null) return
        PushedService.addLogEvent(context,"Engine: ${backgroundEngine!=null}")
        val pref= context.getSharedPreferences("pushed", Context.MODE_PRIVATE)
        backgroundEngine?.destroy()
        backgroundEngine = FlutterEngine(context)
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(context.applicationContext)
        }
        flutterLoader.ensureInitializationComplete(context.applicationContext, null)
        val dartEntrypoint = DartEntrypoint(
            flutterLoader.findAppBundlePath(),
            "package:flutter_pushed_messaging/flutter_pushed_messaging_android.dart",
            "entrypoint"
        )
        val backgroundHandle: Long = pref.getLong("backgroundHandle", 0)
        val args: MutableList<String> = ArrayList()
        args.add(backgroundHandle.toString())
        args.add(message.toString())
        backgroundEngine?.dartExecutor?.executeDartEntrypoint(dartEntrypoint, args)
    }
}