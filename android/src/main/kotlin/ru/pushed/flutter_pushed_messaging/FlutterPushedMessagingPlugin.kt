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
import ru.pushed.messaginglibrary.PushedEnvironment
import ru.pushed.messaginglibrary.PushActionReceiver
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
  private val envTokens = mutableMapOf<String, String>()

  private fun saveTokenForEnv(env: PushedEnvironment, t: String?) {
    val key = "token_${env.name.lowercase()}"
    if (t.isNullOrEmpty()) {
      envTokens.remove(env.name.lowercase())
      pref?.edit()?.remove(key)?.apply()
    } else {
      envTokens[env.name.lowercase()] = t
      pref?.edit()?.putString(key, t)?.apply()
    }
  }

  private fun loadTokenForEnv(env: PushedEnvironment): String? {
    val envKey = env.name.lowercase()
    envTokens[envKey]?.let { return it }
    val saved = pref?.getString("token_$envKey", null)
    if (!saved.isNullOrEmpty()) {
      envTokens[envKey] = saved
    }
    return saved
  }

  private fun clearStoredPushedToken(clearDeviceFields: Boolean = false) {
    try {
      val secret = PushedService.getSecure(context)
      secret.edit().remove("token").apply()
    } catch (e: Exception) {
      PushedService.addLogEvent(context, "Plugin: clearStoredPushedToken secret error: ${e.message}")
    }

    try {
      context.getSharedPreferences("Pushed", Context.MODE_PRIVATE)
        .edit()
        .remove("token")
        .apply()
      val pushedPrefs = context.getSharedPreferences("pushed", Context.MODE_PRIVATE)
      pushedPrefs.edit().remove("token").apply()
      if (clearDeviceFields) {
        pushedPrefs.edit()
          .remove("operatingSystem")
          .remove("sdkVersion")
          .remove("deviceName")
          .apply()
        // SDK reads from "Pushed" (capital P), clear there too
        context.getSharedPreferences("Pushed", Context.MODE_PRIVATE)
          .edit()
          .remove("operatingSystem")
          .remove("sdkVersion")
          .remove("deviceName")
          .apply()
      }
    } catch (e: Exception) {
      PushedService.addLogEvent(context, "Plugin: clearStoredPushedToken prefs error: ${e.message}")
    }
  }

  private fun writeStoredPushedToken(t: String) {
    try {
      val secret = PushedService.getSecure(context)
      secret.edit().putString("token", t).apply()
    } catch (e: Exception) {
      PushedService.addLogEvent(context, "Plugin: writeStoredPushedToken secret error: ${e.message}")
    }
    try {
      context.getSharedPreferences("Pushed", Context.MODE_PRIVATE)
        .edit()
        .putString("token", t)
        .apply()
    } catch (e: Exception) {
      PushedService.addLogEvent(context, "Plugin: writeStoredPushedToken prefs error: ${e.message}")
    }
  }

  private fun getApplicationIdForEnv(env: PushedEnvironment): String? {
    return when (env) {
      PushedEnvironment.PROD -> ""
      PushedEnvironment.DEV -> "690b72be907c4d493670ed68"
      PushedEnvironment.LOAD -> "66eac3a88164a8e82897405e"
    }
  }

  private fun resolveTargetEnvironment(environmentArg: String?, applicationId: String?): PushedEnvironment {
    val trimmedArg = environmentArg?.trim()?.lowercase()
    if (!trimmedArg.isNullOrEmpty()) {
      return try {
        PushedEnvironment.valueOf(trimmedArg.uppercase())
      } catch (_: Exception) {
        try {
          PushedService.getEnvironment(context)
        } catch (_: Exception) {
          PushedEnvironment.PROD
        }
      }
    }
    return when (applicationId?.trim()) {
      "690b72be907c4d493670ed68" -> PushedEnvironment.DEV
      "" -> PushedEnvironment.PROD
      else ->
        try {
          PushedService.getEnvironment(context)
        } catch (_: Exception) {
          PushedEnvironment.PROD
        }
    }
  }

  private fun reinitServiceForCurrentEnv() {
    if (bindedActivity == null) return
    val currentEnv = try { PushedService.getEnvironment(context) } catch (_: Exception) { PushedEnvironment.PROD }
    val appIdForEnv = getApplicationIdForEnv(currentEnv)
    val loggerEnabled = pref?.getBoolean("loggerEnabled", false) ?: false
    val pushChannel = pref?.getString("pushChannel", "messages")
    val serverLoggerEnabled = pref?.getBoolean("serverLoggerEnabled", false) ?: false
    val askPermissions = pref?.getBoolean("askPermissions", false) ?: false

    PushedService.addLogEvent(context, "Plugin: reinitServiceForCurrentEnv env=$currentEnv appId=${appIdForEnv ?: "null"}")

    pushedService = PushedService(
      context,
      ru.pushed.flutter_pushed_messaging.BackgroundMessageReceiver::class.java,
      pushChannel,
      loggerEnabled,
      askPermissions,
      serverLoggerEnabled,
      appIdForEnv,
      "Flutter 1.7.0"
    )
    pushedService?.setStatusHandler {
      mainHandler!!.post {
        channel.invokeMethod("Status", JSONObject().put("Status", it.value))
      }
    }
  }

  private fun resetTokenInCurrentEnvironment(): String? {
    val currentEnv = try { PushedService.getEnvironment(context) } catch (_: Exception) { PushedEnvironment.PROD }
    val appIdForEnv = getApplicationIdForEnv(currentEnv)
    PushedService.addLogEvent(context, "Plugin: resetTokenInCurrentEnvironment ($currentEnv): clearing token, appId=${appIdForEnv ?: "null"}")
    clearStoredPushedToken(clearDeviceFields = true)
    token = null
    pushedService?.pushedToken = null
    saveTokenForEnv(currentEnv, null)

    reinitServiceForCurrentEnv()
    val newToken = pushedService?.start {
      if(PushedService.isApplicationForeground(context)){
        mainHandler!!.post {
          PushedService.addLogEvent(context, "Plugin: Dispatch onReceiveData $it")
          channel.invokeMethod("onReceiveData", it)
        }
        true
      }
      else false
    }
    if (!newToken.isNullOrEmpty()) {
      token = newToken
      saveTokenForEnv(currentEnv, newToken)
      mainHandler?.post {
        channel.invokeMethod("Token", JSONObject().put("Token", newToken))
      }
      PushedService.addLogEvent(context, "Plugin: resetTokenInCurrentEnvironment: new token from start(): ${newToken.take(8)}…")
      return newToken
    }
    PushedService.addLogEvent(context, "Plugin: resetTokenInCurrentEnvironment: new token is null")
    return null
  }

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

    if(token != null) {
      return true
    }

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
    val environmentArg: String? = try {
      if (arguments.has("environment") && !arguments.isNull("environment")) {
        arguments.getString("environment")
      } else {
        null
      }
    } catch (_: Exception) {
      null
    }

    val targetEnv = resolveTargetEnvironment(environmentArg, applicationId)

    var currentEnv = try {
      PushedService.getEnvironment(context)
    } catch (e: Exception) {
      PushedEnvironment.PROD
    }
    if (targetEnv != currentEnv) {
      if (!token.isNullOrEmpty()) {
        saveTokenForEnv(currentEnv, token)
      }
      PushedService.setEnvironment(context, targetEnv)
      currentEnv = targetEnv
      PushedService.addLogEvent(
        context,
        "Plugin: init synced SDK env to ${targetEnv.name.lowercase()} (Dart / applicationId)"
      )
    }
    // Save settings for later reinit on env switch
    pref?.edit()
      ?.putString("pushChannel", pushChannel)
      ?.putBoolean("loggerEnabled", loggerEnabled)
      ?.putBoolean("serverLoggerEnabled", serverLoggerEnabled)
      ?.putBoolean("askPermissions", askpermissions)
      ?.apply()

    val applicationIdForInit = getApplicationIdForEnv(currentEnv)
    PushedService.addLogEvent(
      context,
      "Plugin: init env=${currentEnv.name.lowercase()} applicationIdForInit=${applicationIdForInit ?: "null"}"
    )
    // Use positional args for compatibility with different library metadata/signatures.
    pushedService = PushedService(
      context,
      ru.pushed.flutter_pushed_messaging.BackgroundMessageReceiver::class.java,
      pushChannel,
      loggerEnabled,
      askpermissions,
      serverLoggerEnabled,
      applicationIdForInit,
      "Flutter 1.7.0"
    )
    //pushedService= PushedService(bindedActivity!!.activity,BackgroundMessageReceiver::class.java)


    pushedService?.setStatusHandler {
      mainHandler!!.post {
        PushedService.addLogEvent(context, "Plugin: Dispatch Status ${it.value}")
        channel.invokeMethod("Status", JSONObject().put("Status",it.value))
      }
    }
    // Check if we have a saved token for the current env — write to secure storage
    // so PushedService.start() uses it instead of requesting a new one
    val savedEnvToken = loadTokenForEnv(currentEnv)
    if (!savedEnvToken.isNullOrEmpty()) {
      writeStoredPushedToken(savedEnvToken)
      pushedService?.pushedToken = savedEnvToken
      PushedService.addLogEvent(context, "Plugin: init restored saved token for ${currentEnv.name.lowercase()}: ${savedEnvToken.take(8)}…")
    }

    PushedService.addLogEvent(context, "Plugin: init calling start() for env=${currentEnv.name.lowercase()} savedToken=${savedEnvToken?.take(8) ?: "null"}")
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
    PushedService.addLogEvent(context, "Plugin: init start() returned token=${token?.take(8) ?: "null"} (savedWas=${savedEnvToken?.take(8) ?: "null"})")
    if (!token.isNullOrEmpty()) {
      // Only save if different from what we had (avoid overwriting with a new token on restart)
      if (savedEnvToken.isNullOrEmpty() || savedEnvToken != token) {
        saveTokenForEnv(currentEnv, token)
        PushedService.addLogEvent(context, "Plugin: init saved token for ${currentEnv.name.lowercase()}: ${token?.take(8)}…")
      }
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
    } else if (call.method == "setEnvironment") {
      try {
        val args = call.arguments as JSONObject
        val envName = args.getString("environment")
        val env = PushedEnvironment.valueOf(envName.uppercase())

        val oldEnv = try { PushedService.getEnvironment(context) } catch (_: Exception) { PushedEnvironment.PROD }
        if (!token.isNullOrEmpty()) {
          saveTokenForEnv(oldEnv, token)
        }

        PushedService.setEnvironment(context, env)
        val appIdForEnv = getApplicationIdForEnv(env)
        PushedService.addLogEvent(context, "Plugin: setEnvironment $oldEnv -> $env, appId=${appIdForEnv ?: "null"}")

        val savedToken = loadTokenForEnv(env)
        if (!savedToken.isNullOrEmpty()) {
          // Write saved token to SDK secure storage BEFORE reinit,
          // so PushedService constructor finds it and doesn't generate a new one
          writeStoredPushedToken(savedToken)
          PushedService.addLogEvent(context, "Plugin: wrote saved token to secure storage for $env: ${savedToken.take(8)}…")
          reinitServiceForCurrentEnv()
          token = savedToken
          pushedService?.pushedToken = savedToken
          mainHandler?.post {
            channel.invokeMethod("Token", JSONObject().put("Token", savedToken))
          }
          PushedService.addLogEvent(context, "Plugin: restored saved token for $env: ${savedToken.take(8)}…")
        } else {
          // No saved token — clear everything including cached device fields so they get re-sent
          clearStoredPushedToken(clearDeviceFields = true)
          token = null
          reinitServiceForCurrentEnv()

          val newToken = pushedService?.start {
            if(PushedService.isApplicationForeground(context)){
              mainHandler!!.post {
                PushedService.addLogEvent(context, "Plugin: Dispatch onReceiveData $it")
                channel.invokeMethod("onReceiveData", it)
              }
              true
            }
            else false
          }
          if (!newToken.isNullOrEmpty()) {
            token = newToken
            saveTokenForEnv(env, newToken)
            mainHandler?.post {
              channel.invokeMethod("Token", JSONObject().put("Token", newToken))
            }
            PushedService.addLogEvent(context, "Plugin: new token from start() for $env: ${newToken.take(8)}…")
          } else {
            PushedService.addLogEvent(context, "Plugin: new token for $env is null")
          }
        }

        result.success(true)
      } catch (e: Exception) {
        PushedService.addLogEvent(context, "Plugin: setEnvironment error: ${e.message}")
        result.success(false)
      }
    } else if (call.method == "getEnvironment") {
      try {
        val env = PushedService.getEnvironment(context)
        PushedService.addLogEvent(context, "Plugin: getEnvironment -> $env")
        result.success(env.name.lowercase())
      } catch (e: Exception) {
        PushedService.addLogEvent(context, "Plugin: getEnvironment error: ${e.message}")
        result.success("prod")
      }
    } else if (call.method == "resetToken") {
      try {
        result.success(resetTokenInCurrentEnvironment())
      } catch (e: Exception) {
        PushedService.addLogEvent(context, "Plugin: resetToken error: ${e.message}")
        result.success(null)
      }
    } else if (call.method == "getEndpoints") {
      try {
        val env = PushedService.getEnvironment(context)
        val payload = JSONObject()
          .put("environment", env.name.lowercase())
          .put("tokensUrl", PushedService.getTokensUrl(context))
          .put("webSocketUrl", PushedService.getWebSocketUrl(context))
          .put("serverLogUrl", PushedService.getServerLogUrl(context))
          .put("confirmDeliveredUrlFcm", PushedService.getConfirmDeliveredUrl(context, "Fcm"))

        PushedService.addLogEvent(context, "Plugin: getEndpoints -> $payload")
        result.success(payload)
      } catch (e: Exception) {
        PushedService.addLogEvent(context, "Plugin: getEndpoints error: ${e.message}")
        result.success(JSONObject().put("environment", "unknown"))
      }
    } else if (call.method == "sendInteraction") {
      try {
        val args = call.arguments as JSONObject
        val messageId = args.getString("messageId")
        var interaction = args.getString("interaction")
        if (interaction == "Close") {
            interaction = "Closed"
        }
        PushedService.addLogEvent(context, "Plugin: sendInteraction messageId=$messageId interaction=$interaction")
        PushActionReceiver.send(context, messageId, interaction)
        result.success(true)
      } catch (e: Exception) {
        PushedService.addLogEvent(context, "Plugin: sendInteraction error: ${e.message}")
        result.success(false)
      }
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
