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
import io.flutter.plugin.common.PluginRegistry
import android.content.Intent
import org.json.JSONArray


/** FlutterPushedMessagingPlugin */
class FlutterPushedMessagingPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {
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
  private var initialPayload: Map<String, Any?>? = null

  private fun jsonToMap(json: JSONObject): Map<String, Any?> {
    return json.keys().asSequence().associateWith {
      when (val value = json.get(it)) {
        is JSONObject -> jsonToMap(value)
        is JSONArray -> jsonToList(value)
        JSONObject.NULL -> null
        else -> value
      }
    }
  }

  private fun jsonToList(json: JSONArray): List<Any?> {
    return (0 until json.length()).map {
      when (val value = json.get(it)) {
        is JSONObject -> jsonToMap(value)
        is JSONArray -> jsonToList(value)
        JSONObject.NULL -> null
        else -> value
      }
    }
  }

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
        PushedService.addLogEvent(context, "Plugin: Dispatch Status ${it.value}")
        channel.invokeMethod("Status", JSONObject().put("Status",it.value))
      }
    }
    token=pushedService?.start {
      if(PushedService.isApplicationForeground(context)){
        mainHandler!!.post {
          PushedService.addLogEvent(context, "Plugin: Dispatch onReceiveData $it")
          channel.invokeMethod("onReceiveData", it)
        }
        true
      }
      else false
    }
    pushedService?.setOnMessageOpenedAppHandler {
      PushedService.addLogEvent(context, "[PLUGIN_HANDLER] onMessageOpenedApp invoked with: $it")
      mainHandler!!.post {
        PushedService.addLogEvent(context, "[PLUGIN_HANDLER] Posting to Flutter: $it")
        channel.invokeMethod("onMessageOpenedApp", it)
      }
    }
    // If activity already has pending pushedData, process it immediately
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
    PushedService.addLogEvent(context, "Plugin: onAttachedToEngine")

  }

  override fun onNewIntent(intent: Intent): Boolean {
    bindedActivity?.activity?.let { activity ->
      PushedService.addLogEvent(context, "[PLUGIN_HANDLER] onNewIntent received, checking for message")
      activity.intent = intent
      pushedService?.checkOpenedAppMessage(activity)
    }
    return false
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "init") {
      result.success(initPlugin(call.arguments as JSONObject))
    } else if (call.method == "getToken") {
      result.success(token)
    } else if (call.method == "getStatus") {
      result.success(pushedService!!.status.value)
    } else if (call.method == "getInitialMessage") {
      result.success(initialPayload)
      initialPayload = null
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
    binding.addOnNewIntentListener(this)
    val intent = binding.activity.intent
    if (intent.hasExtra("pushedData")) {
      val data = intent.getStringExtra("pushedData")!!
      PushedService.addLogEvent(context, "[PLUGIN] Activity attached with pushedData: $data")
      if (pushedService == null) {
        // Cold start. Store as initial message.
        try {
          initialPayload = jsonToMap(JSONObject(data))
          PushedService.addLogEvent(context, "[PLUGIN] Stored as initial message.")
          intent.removeExtra("pushedData")
        } catch (e: Exception) {
          PushedService.addLogEvent(context, "[PLUGIN] Error parsing initial message: ${e.message}")
        }
      } else {
        // Warm start, but activity was recreated. Process it now.
        PushedService.addLogEvent(context, "[PLUGIN] App running, processing message immediately.")
        pushedService?.checkOpenedAppMessage(binding.activity)
      }
    }
  }

  override fun onDetachedFromActivityForConfigChanges() {
    pushedService?.unbindService()
    bindedActivity?.removeOnNewIntentListener(this)
    bindedActivity=null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    pushedService?.unbindService()
    bindedActivity=binding
    binding.addOnNewIntentListener(this)
    try {
      PushedService.addLogEvent(context, "Plugin: onReattachedToActivityForConfigChanges ${binding.activity.localClassName}")
      pushedService?.checkOpenedAppMessage(binding.activity)
    } catch (e: Exception) {
      PushedService.addLogEvent(context, "Plugin: onReattachedToActivityForConfigChanges error: ${e.message}")
    }
  }

  override fun onDetachedFromActivity() {
    bindedActivity?.removeOnNewIntentListener(this)
    bindedActivity=null
  }
}
