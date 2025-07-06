package ru.pushed.flutter_pushed_messaging

import android.R.attr.data
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.JSONMethodCodec
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject
import ru.pushed.messaginglibrary.PushedService


/** FlutterPushedMessagingPlugin */
class FlutterPushedMessagingPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private var pushedService: PushedService?=null
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private var pref: SharedPreferences? = null
  private var token:String?=null
  private var bindedActivity:ActivityPluginBinding?=null
  private var mainHandler: Handler? = null

  fun initPlugin(arguments:JSONObject):Boolean{
    if(bindedActivity==null) return false
    if(token!=null) return true
    val backgroundHandle = try {
      arguments.getLong("backgroundHandle")
    } catch (e: Exception) {
      0
    }
    pref?.edit()?.putLong("backgroundHandle", backgroundHandle)?.apply();
    val pushChannel = try {
      arguments.getString("channel")
    } catch (e: Exception) {
      null
    }
    val loggerEnabled = try {
      arguments.getBoolean("logger")
    } catch (e: Exception) {
      false
    }
    val serverLoggerEnabled=try {
      arguments.getBoolean("serverLoggerEnabled")
    } catch (e: Exception) {
      false
    }
    val askpermissions=try {
      arguments.getBoolean("askpermissions")
    } catch (e: Exception) {
      false
    }
    val applicationId=try {
      arguments.getString("applicationId")
    } catch (e: Exception) {
      null
    }
    pushedService= PushedService(bindedActivity!!.activity,BackgroundMessageReceiver::class.java,
      enableLogger = loggerEnabled, channel = pushChannel,
      enableServerLogger = serverLoggerEnabled, applicationId = applicationId, askPermissions = askpermissions)
    //pushedService= PushedService(bindedActivity!!.activity,BackgroundMessageReceiver::class.java)


    pushedService?.setStatusHandler {
      mainHandler!!.post {
        channel.invokeMethod("Status", JSONObject().put("Status",it.value))
      }
    }
    token=pushedService?.start {
      if(PushedService.isApplicationForeground(context)){
        mainHandler!!.post {
          channel.invokeMethod("onReceiveData", it)
        }
        true
      }
      else false
    }
    return token!=null
  }

  fun askPermissions(arguments:JSONObject):Boolean{
    if(pushedService==null) return false
    val askNotification=try {
      arguments.getBoolean("askNotification")
    } catch (e: Exception) {
      false
    }
    val askBackgroundWork=try {
      arguments.getBoolean("askBackgroundWork")
    } catch (e: Exception) {
      false
    }

    pushedService!!.askPermissions(askNotification = askNotification, askBackgroundWork = askBackgroundWork)
    return true

  }
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_pushed_messaging",
      JSONMethodCodec.INSTANCE)
    channel.setMethodCallHandler(this)
    this.context=flutterPluginBinding.applicationContext
    mainHandler = Handler(context.mainLooper)
    pref=context.getSharedPreferences("pushed", Context.MODE_PRIVATE)

  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "init") {
      result.success(initPlugin(call.arguments as JSONObject))
    } else if (call.method == "getToken") {
      result.success(token)
    } else if (call.method == "getStatus") {
      result.success(pushedService!!.status.value)
    } else if (call.method == "log") {
      PushedService.addLogEvent(context,call.argument("event")?:"")
      result.success(true)
    } else if (call.method == "getLog") {
      result.success(PushedService.getLog(context))
    } else if (call.method == "askPermissions") {
      result.success(askPermissions(call.arguments as JSONObject))
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    bindedActivity=binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    pushedService?.unbindService()
    bindedActivity=null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    pushedService?.unbindService()
    bindedActivity=binding
  }

  override fun onDetachedFromActivity() {
    bindedActivity=null
  }
}
