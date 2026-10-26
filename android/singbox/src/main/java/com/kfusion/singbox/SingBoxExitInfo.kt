package com.kfusion.singbox

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object SingBoxExitInfo {
    const val PROCESS_SUFFIX = ":singbox"

    class Record(
        val reason: Int,
        val timestamp: Long,
        val description: String,
        val importance: Int,
    )

    fun reasonLabel(reason: Int): String =
        when (reason) {
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
            ApplicationExitInfo.REASON_CRASH -> "CRASH"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            ApplicationExitInfo.REASON_FREEZER -> "FREEZER"
            ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "PACKAGE_STATE_CHANGE"
            ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "PACKAGE_UPDATED"
            else -> "UNRECOGNIZED"
        }

    fun summaryLine(record: Record): String = "process exit: ${exitTail(record)}"

    fun attemptDeathLine(seq: Long, level: Int, levelName: String, record: Record): String {
        val where = if (level >= 0) {
            if (levelName.isBlank()) " at L$level" else " at L$level ($levelName)"
        } else {
            ""
        }
        return "attempt #$seq died$where: ${exitTail(record)}"
    }

    private fun exitTail(record: Record): String {
        val stamp =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(record.timestamp))
        val base = "${reasonLabel(record.reason)}(${record.reason}) at $stamp"
        return if (record.description.isBlank()) base else "$base - ${record.description}"
    }

    fun latest(context: Context): Record? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val exit = latestExitInfo(context) ?: return null
        return Record(
            reason = exit.reason,
            timestamp = exit.timestamp,
            description = exit.description.orEmpty(),
            importance = exit.importance,
        )
    }

    fun traceExcerpt(
        context: Context,
        maxChars: Int = 1200,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val stream = latestExitInfo(context)?.traceInputStream ?: return null
        return runCatching {
            stream.bufferedReader().use { reader -> reader.readText() }.trim().take(maxChars)
        }.getOrNull()?.ifBlank { null }
    }

    private val signalPattern = Regex("""^signal \d+ \(SIG[A-Z0-9]+\).*$""")

    fun signalLine(trace: String?): String? {
        if (trace.isNullOrBlank()) return null
        return trace.lineSequence()
            .map { it.trim() }
            .firstOrNull { signalPattern.matches(it) }
            ?.take(200)
    }

    fun latestSignalLine(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val exit = latestExitInfo(context) ?: return null
        if (exit.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) return null
        val stream = runCatching { exit.traceInputStream }.getOrNull() ?: return null
        val text = runCatching {
            stream.bufferedReader().use { reader -> reader.readText() }
        }.getOrNull() ?: return null
        return signalLine(text)
    }

    private fun latestExitInfo(context: Context): ApplicationExitInfo? {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return null
        val records =
            runCatching {
                manager.getHistoricalProcessExitReasons(context.packageName, 0, 8)
            }.getOrNull() ?: return null
        return records.firstOrNull { it.processName.endsWith(PROCESS_SUFFIX) }
    }
}

object SingBoxCrashReport {
    fun fileIn(workingDir: File): File = File(workingDir, "CrashReport-.log")

    fun unreadLines(
        workingDir: File,
        seenModified: Long,
        maxLines: Int = 40,
    ): Pair<Long, List<String>>? {
        val file = fileIn(workingDir)
        if (!file.isFile) return null
        val modified = file.lastModified()
        if (modified <= seenModified) return null
        val lines = runCatching { file.readLines() }.getOrNull() ?: return null
        return modified to lines.filter { it.isNotBlank() }.takeLast(maxLines)
    }
}
