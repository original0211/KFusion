package com.follow.clash.plugins

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.PendingCallback
import com.kfusion.singbox.SingBoxLog
import com.kfusion.singbox.SingBoxStatus
import com.kfusion.singbox.SingBoxVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlin.concurrent.thread

class SingBoxPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prepareCallback = PendingCallback<Boolean>()

    private val activityResultListener =
        PluginRegistry.ActivityResultListener(::onActivityResult)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, SINGBOX_CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<String>("configPath"), result)
            "checkConfig" -> checkConfig(call.argument<String>("configPath"), result)
            "stop" -> stop(result)
            "isRunning" -> result.success(SingBoxStatus.isRunning(GlobalState.application))
            else -> result.notImplemented()
        }
    }

    private fun start(configPath: String?, result: MethodChannel.Result) {
        if (configPath.isNullOrEmpty()) {
            result.success("sing-box 配置路径为空")
            return
        }
        prepareVpn { granted ->
            if (!granted) {
                result.success("VPN 权限未授予，sing-box 未启动")
                return@prepareVpn
            }
            val context = GlobalState.application
            // The poll below only settles on snapshots from this epoch on.
            val epoch = System.currentTimeMillis()
            SingBoxStatus.writeAt(context, SingBoxStatus.State.STARTING, "", epoch)
            val intent = Intent(context, SingBoxVpnService::class.java)
                .putExtra(SingBoxVpnService.EXTRA_CONFIG_PATH, configPath)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (error: Exception) {
                result.success("sing-box 服务启动失败：${error.message}")
                return@prepareVpn
            }
            thread(name = "singbox-start-wait") {
                val deadline = System.currentTimeMillis() + START_TIMEOUT_MS
                var message = "sing-box 服务启动超时"
                var settled = false
                while (System.currentTimeMillis() < deadline) {
                    val snapshot = SingBoxStatus.read(context)
                    when (SingBoxStartGate.verdict(snapshot, epoch, SingBoxStatus::isPidAlive)) {
                        SingBoxStartGate.Verdict.RUNNING -> {
                            message = ""
                            settled = true
                            break
                        }
                        SingBoxStartGate.Verdict.FAILED -> {
                            message = if (snapshot?.state == SingBoxStatus.State.STARTING) {
                                "sing-box 进程在启动中退出"
                            } else {
                                snapshot?.message?.ifEmpty { null }
                                    ?: "sing-box 启动失败"
                            }
                            settled = true
                            break
                        }
                        SingBoxStartGate.Verdict.PENDING -> Unit
                    }
                    Thread.sleep(POLL_INTERVAL_MS)
                }
                if (!settled) stopInFlightStart(context)
                if (message.isNotEmpty()) message = withLogTail(context, message)
                mainHandler.post { result.success(message) }
            }
        }
    }

    private fun stopInFlightStart(context: Context) {
        val intent = Intent(context, SingBoxVpnService::class.java)
            .setAction(SingBoxVpnService.ACTION_STOP)
        runCatching { context.startService(intent) }
            .onFailure {
                runCatching {
                    context.stopService(Intent(context, SingBoxVpnService::class.java))
                }
            }
    }

    private fun withLogTail(context: Context, message: String): String {
        val tail = SingBoxLog.tail(context, LOG_TAIL_LINES)
        return if (tail.isEmpty()) message else "$message\n$tail"
    }

    private fun checkConfig(configPath: String?, result: MethodChannel.Result) {
        if (configPath.isNullOrEmpty()) {
            result.success("sing-box 配置路径为空")
            return
        }
        val context = GlobalState.application
        val requestId = System.currentTimeMillis()
        val intent = Intent(context, SingBoxVpnService::class.java)
            .setAction(SingBoxVpnService.ACTION_CHECK_CONFIG)
            .putExtra(SingBoxVpnService.EXTRA_CONFIG_PATH, configPath)
            .putExtra(SingBoxVpnService.EXTRA_REQUEST_ID, requestId)
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (error: Exception) {
            result.success("sing-box 配置校验不可用：${error.message}")
            return
        }
        thread(name = "singbox-check-wait") {
            val deadline = System.currentTimeMillis() + CHECK_TIMEOUT_MS
            var message = "sing-box 配置校验超时"
            while (System.currentTimeMillis() < deadline) {
                val check = SingBoxStatus.readCheckResult(context)
                if (check != null && check.requestId == requestId) {
                    message = if (check.ok) "" else check.message.ifEmpty { "sing-box 配置校验失败" }
                    break
                }
                Thread.sleep(POLL_INTERVAL_MS)
            }
            mainHandler.post { result.success(message) }
        }
    }

    private fun stop(result: MethodChannel.Result) {
        val context = GlobalState.application
        SingBoxVpnService.clearSavedConfigPath(context)
        context.stopService(Intent(context, SingBoxVpnService::class.java))
        thread(name = "singbox-stop-wait") {
            val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                if (!SingBoxStatus.isRunning(context)) break
                Thread.sleep(POLL_INTERVAL_MS)
            }
            mainHandler.post { result.success(!SingBoxStatus.isRunning(context)) }
        }
    }

    private fun prepareVpn(callback: (Boolean) -> Unit) {
        prepareCallback.replace(callback, supersededValue = false)
        val intent = VpnService.prepare(GlobalState.application)
        if (intent == null) {
            prepareCallback.resolve(true)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            prepareCallback.resolve(false)
            return
        }
        @Suppress("DEPRECATION")
        currentActivity.startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
    }

    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) return false
        prepareCallback.resolve(resultCode == Activity.RESULT_OK)
        return true
    }

    private companion object {
        val SINGBOX_CHANNEL = "${Components.PACKAGE_NAME}/singbox"
        const val VPN_PERMISSION_REQUEST_CODE = 1007
        // Under the Dart channel budget (45s): the verdict stays the service's.
        const val START_TIMEOUT_MS = 40_000L
        const val CHECK_TIMEOUT_MS = 30_000L
        const val STOP_TIMEOUT_MS = 5_000L
        const val POLL_INTERVAL_MS = 200L
        const val LOG_TAIL_LINES = 6
    }
}
