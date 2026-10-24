package com.kfusion.singbox

import android.content.Context
import android.os.Process
import org.json.JSONObject
import java.io.File

// The sing-box service runs in its own process, so its state crosses to the
// app process through this file instead of shared memory.
object SingBoxStatus {
    enum class State { RUNNING, FAILED, STOPPED }

    data class Snapshot(val state: State, val message: String, val pid: Int)

    private fun directory(context: Context) = File(context.filesDir, "singbox")

    private fun file(context: Context) = File(directory(context), "status.json")

    fun write(context: Context, state: State, message: String) {
        val dir = directory(context)
        dir.mkdirs()
        val payload = JSONObject()
            .put("state", state.name.lowercase())
            .put("message", message)
            .put("pid", Process.myPid())
            .put("updatedAt", System.currentTimeMillis())
            .toString()
        val temp = File(dir, "status.json.tmp")
        temp.writeText(payload)
        temp.renameTo(file(context))
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
            )
        }.getOrNull()
    }

    fun isRunning(context: Context): Boolean {
        val snapshot = read(context) ?: return false
        if (snapshot.state != State.RUNNING) return false
        // A killed service process leaves a stale "running" file behind.
        return snapshot.pid > 0 && File("/proc/${snapshot.pid}").exists()
    }
}
