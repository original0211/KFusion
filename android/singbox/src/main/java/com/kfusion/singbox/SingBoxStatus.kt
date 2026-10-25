package com.kfusion.singbox

import android.content.Context
import android.os.Process
import org.json.JSONObject
import java.io.File

// The sing-box service runs in its own process, so its state crosses to the
// app process through this file instead of shared memory.
object SingBoxStatus {
    enum class State { STARTING, RUNNING, FAILED, STOPPED }

    data class Snapshot(
        val state: State,
        val message: String,
        val pid: Int,
        val updatedAt: Long,
    )

    data class CheckResult(
        val requestId: Long,
        val ok: Boolean,
        val message: String,
    )

    private fun directory(context: Context) = File(context.filesDir, "singbox")

    private fun file(context: Context) = File(directory(context), "status.json")

    private fun checkFile(context: Context) = File(directory(context), "check_result.json")

    fun write(context: Context, state: State, message: String) {
        writeAt(context, state, message, System.currentTimeMillis())
    }

    // [updatedAt] is the starting attempt's epoch, not the write time.
    fun writeAt(context: Context, state: State, message: String, updatedAt: Long) {
        val payload = JSONObject()
            .put("state", state.name.lowercase())
            .put("message", message)
            .put("pid", Process.myPid())
            .put("updatedAt", updatedAt)
            .toString()
        writeFile(file(context), payload)
    }

    private fun writeFile(target: File, payload: String) {
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeText(payload)
        temp.renameTo(target)
    }

    fun read(context: Context): Snapshot? {
        val statusFile = file(context)
        if (!statusFile.isFile) return null
        return runCatching {
            val json = JSONObject(statusFile.readText())
            Snapshot(
                state = State.valueOf(json.getString("state").uppercase()),
                message = json.optString("message"),
                pid = json.optInt("pid", -1),
                updatedAt = json.optLong("updatedAt", 0),
            )
        }.getOrNull()
    }

    fun isRunning(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        return snapshot.state == State.RUNNING && isAlive(snapshot)
    }

    // A killed service process leaves a stale "running" file behind.
    fun isAlive(snapshot: Snapshot): Boolean = isPidAlive(snapshot.pid)

    fun isPidAlive(pid: Int): Boolean =
        pid > 0 && File("/proc/$pid").exists()

    fun writeCheckResult(context: Context, requestId: Long, ok: Boolean, message: String) {
        val payload = JSONObject()
            .put("requestId", requestId)
            .put("ok", ok)
            .put("message", message)
            .put("updatedAt", System.currentTimeMillis())
            .toString()
        writeFile(checkFile(context), payload)
    }

    fun readCheckResult(context: Context): CheckResult? {
        val resultFile = checkFile(context)
        if (!resultFile.isFile) return null
        return runCatching {
            val json = JSONObject(resultFile.readText())
            CheckResult(
                requestId = json.getLong("requestId"),
                ok = json.getBoolean("ok"),
                message = json.optString("message"),
            )
        }.getOrNull()
    }
}
