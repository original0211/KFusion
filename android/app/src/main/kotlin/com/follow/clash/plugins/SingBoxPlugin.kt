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
import com.kfusion.singbox.SingBoxCrashReport
import com.kfusion.singbox.SingBoxDeathLetter
import com.kfusion.singbox.SingBoxExitInfo
import com.kfusion.singbox.SingBoxLog
import com.kfusion.singbox.SingBoxStageMarkers
import com.kfusion.singbox.SingBoxStagedStart
import com.kfusion.singbox.SingBoxStatus
import com.kfusion.singbox.SingBoxVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
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
                var message = "sing-box 服务启动超时"
                var settled = false
                while (!SingBoxStartGate.expired(System.currentTimeMillis(), epoch)) {
                    val snapshot = SingBoxStatus.read(context)
                    when (SingBoxStartGate.verdict(snapshot, epoch, SingBoxStatus::isPidAlive)) {
                        SingBoxStartGate.Verdict.RUNNING -> {
                            message = ""
                            settled = true
                            break
                        }
                        SingBoxStartGate.Verdict.FAILED -> {
                            message = if (snapshot?.state == SingBoxStatus.State.STARTING) {
                                deathMessage(context, epoch, snapshot)
                            } else {
                                snapshot?.message?.ifEmpty { null }
                                    ?: "sing-box 启动失败"
                            }
                            settled = true
                            break
                        }
                        SingBoxStartGate.Verdict.SUSPECT -> {
                            if (deathConfirmed(context)) {
                                message = if (
                                    snapshot?.state == SingBoxStatus.State.STARTING
                                ) {
                                    deathMessage(context, epoch, snapshot)
                                } else {
                                    snapshot?.message?.ifEmpty { null }
                                        ?: "sing-box 启动失败"
                                }
                                settled = true
                                break
                            }
                            if (snapshot?.state == SingBoxStatus.State.RUNNING) {
                                message = ""
                                settled = true
                                break
                            }
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

    // SUSPECT's second channel: only an exit record tied to this attempt confirms a death.
    private fun deathConfirmed(context: Context): Boolean {
        val attempt = SingBoxStatus.readAttempt(context) ?: return false
        return SingBoxDeathGate.awaitRecord(
            DEATH_RECORD_ATTEMPTS,
            { Thread.sleep(DEATH_RECORD_POLL_MS) },
        ) {
            SingBoxExitInfo.latest(context)?.takeIf {
                SingBoxStagedStart.isAttemptDeath(true, it.timestamp, attempt.since)
            }
        } != null
    }

    // An exit record is quoted only when the mirrored ledger ties it to this poll's attempt.
    private fun deathMessage(
        context: Context,
        epoch: Long,
        snapshot: SingBoxStatus.Snapshot?,
    ): String {
        val generic = "sing-box 进程在启动中退出"
        val parts = mutableListOf(generic)
        var settled: SingBoxDeathGate.Settled? = null
        val attempt = SingBoxStatus.readAttempt(context)
        SingBoxLog.append(
            context,
            "death verdict inputs: state=${snapshot?.state} pid=${snapshot?.pid} " +
                "updatedAt=${snapshot?.updatedAt} epoch=$epoch " +
                "attempt=${attempt?.seq}/${attempt?.since}",
        )
        if (attempt != null &&
            attempt.since >= epoch - SingBoxStagedStart.ASSOCIATION_SLACK_MS
        ) {
            settled = SingBoxDeathGate.awaitSettled(
                DEATH_RECORD_ATTEMPTS,
                { Thread.sleep(DEATH_RECORD_POLL_MS) },
                {
                    SingBoxExitInfo.latest(context)?.takeIf {
                        SingBoxStagedStart.isAttemptDeath(true, it.timestamp, attempt.since)
                    }
                },
            ) { SingBoxExitInfo.probeCrashHeadline(context) }
            val found = settled
            if (found != null) {
                if (found.headline == null) {
                    found.miss?.let { miss ->
                        SingBoxLog.append(context, SingBoxExitInfo.headlineMissLine(miss))
                    }
                }
                found.headline?.let { parts += it }
                parts += SingBoxExitInfo.attemptDeathLine(
                    attempt.seq,
                    attempt.level,
                    attempt.levelName,
                    found.record,
                )
            }
        }
        parts += diagnosticsLines(context, epoch, settled?.record, attempt)
        return parts.joinToString("；")
    }

    // Epoch-gated throughout, except the death letter: seq-gated to this or
    // the previous attempt, it is the channel for a death already settled.
    private fun diagnosticsLines(
        context: Context,
        epoch: Long,
        settledRecord: SingBoxExitInfo.Record?,
        attempt: SingBoxStatus.Attempt?,
    ): List<String> {
        val lines = mutableListOf<String>()
        if (settledRecord == null) {
            val windowStart = epoch - SingBoxStagedStart.ASSOCIATION_SLACK_MS
            val fresh = SingBoxExitInfo.latest(context)
                ?.takeIf { it.timestamp >= windowStart }
            lines += SingBoxExitInfo.recordLine(fresh)
        }
        val workingDir = File(context.filesDir, "singbox")
        lines += SingBoxStageMarkers.tailLineInWindow(workingDir, attempt?.since ?: epoch)
        // Freshness is a property of the attempt, not of this poll: anchored
        // to the poll's epoch, two polls of one attempt reached opposite
        // verdicts over a single empty report file (field cards, v0.2.23).
        lines += SingBoxCrashReport.reasonLineIn(
            workingDir,
            (attempt?.since ?: epoch) - SingBoxStagedStart.ASSOCIATION_SLACK_MS,
        )
        SingBoxLog.lastErrorLine(context)?.let { lines += it }
        if (attempt != null) {
            SingBoxDeathLetter.lineFor(SingBoxDeathLetter.readFrom(workingDir), attempt.seq)
                ?.let { lines += it }
        }
        return lines
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
        val tail = SingBoxLog.cardTail(context, LOG_TAIL_LINES)
        return if (tail.isEmpty()) message else "$message\n$tail"
    }

    private fun checkConfig(configPath: String?, result: MethodChannel.Result) {
        if (configPath.isNullOrEmpty()) {
            result.success("sing-box 配置路径为空")
            return
        }
        val context = GlobalState.application
        thread(name = "singbox-check-wait") {
            val message = SingBoxCheckGate.awaitResult(CHECK_ATTEMPTS) {
                runCheckAttempt(context, configPath)
            } ?: SingBoxCheckGate.TIMEOUT_SENTINEL
            mainHandler.post { result.success(message) }
        }
    }

    // One check round-trip; null means the round timed out unanswered. Reissuing
    // the intent also restarts the service process when it died mid-check.
    private fun runCheckAttempt(context: Context, configPath: String): String? {
        val requestId = System.nanoTime()
        val intent = Intent(context, SingBoxVpnService::class.java)
            .setAction(SingBoxVpnService.ACTION_CHECK_CONFIG)
            .putExtra(SingBoxVpnService.EXTRA_CONFIG_PATH, configPath)
            .putExtra(SingBoxVpnService.EXTRA_REQUEST_ID, requestId)
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (error: Exception) {
            return "sing-box 配置校验不可用：${error.message}"
        }
        val deadline = System.currentTimeMillis() + CHECK_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            val check = SingBoxStatus.readCheckResult(context)
            if (check != null && check.requestId == requestId) {
                return if (check.ok) "" else check.message.ifEmpty { "sing-box 配置校验失败" }
            }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        return null
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
        const val CHECK_TIMEOUT_MS = 30_000L
        const val CHECK_ATTEMPTS = 2
        const val STOP_TIMEOUT_MS = 5_000L
        const val POLL_INTERVAL_MS = 200L
        const val LOG_TAIL_LINES = 6
        // The exit record lags the pid's death; the old ~3s window missed it.
        const val DEATH_RECORD_ATTEMPTS = 21
        const val DEATH_RECORD_POLL_MS = 250L
    }
}
