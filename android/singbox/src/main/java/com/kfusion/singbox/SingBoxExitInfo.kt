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
        // For a SIGNALED death the platform status is the signal number; 0 = not captured.
        val status: Int = 0,
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
        val label = SingBoxStagedStart.labelForIndex(level)
        val where = if (level >= 0) {
            if (levelName.isBlank()) " at $label" else " at $label ($levelName)"
        } else {
            ""
        }
        return "attempt #$seq died$where: ${exitTail(record)}"
    }

    fun signalLabel(status: Int): String =
        when (status) {
            4 -> "SIGILL(4)"
            6 -> "SIGABRT(6)"
            7 -> "SIGBUS(7)"
            9 -> "SIGKILL(9)"
            11 -> "SIGSEGV(11)"
            else -> "signal($status)"
        }

    private fun exitTail(record: Record): String {
        val stamp =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(record.timestamp))
        val signal =
            if (record.reason == ApplicationExitInfo.REASON_SIGNALED && record.status > 0) {
                " ${signalLabel(record.status)}"
            } else {
                ""
            }
        val base = "${reasonLabel(record.reason)}(${record.reason})$signal at $stamp"
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
            status = exit.status,
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

    private val framePattern = Regex("""^#\d+ pc [0-9a-fA-F]+ .*$""")

    fun firstBacktraceFrame(trace: String?): String? {
        if (trace.isNullOrBlank()) return null
        return trace.lineSequence()
            .map { it.trim() }
            .firstOrNull { framePattern.matches(it) }
            ?.take(200)
    }

    fun signalClassNote(signalLine: String?): String? =
        when {
            signalLine == null -> null
            signalLine.contains("(SIGBUS)") -> "SIGBUS 多指向内存映射文件（如缓存文件）损坏"
            signalLine.contains("(SIGSEGV)") -> "SIGSEGV 为原生代码非法内存访问"
            signalLine.contains("(SIGABRT)") -> "SIGABRT 为程序主动中止，多见于 Go 运行时致命错误"
            else -> null
        }

    // The card leads with the signal evidence; register dumps stay in the service log.
    fun crashHeadline(trace: String?): String? {
        val signal = signalLine(trace) ?: return null
        val noted = signalClassNote(signal)?.let { "$signal（$it）" } ?: signal
        val frame = firstBacktraceFrame(trace)
        return if (frame == null) noted else "$noted · $frame"
    }

    // Why a native crash produced no headline, named so a caller can log the branch.
    enum class HeadlineMiss { STREAM_UNAVAILABLE, TRACE_UNREADABLE, NO_SIGNAL_LINE }

    class HeadlineProbe(val headline: String?, val miss: HeadlineMiss?)

    fun headlineMissLine(miss: HeadlineMiss): String =
        when (miss) {
            HeadlineMiss.STREAM_UNAVAILABLE -> "exit headline: trace stream unavailable"
            HeadlineMiss.TRACE_UNREADABLE -> "exit headline: trace unreadable"
            HeadlineMiss.NO_SIGNAL_LINE -> "exit headline: no signal line in trace"
        }

    fun probeCrashHeadline(context: Context): HeadlineProbe {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return HeadlineProbe(null, null)
        val exit = latestExitInfo(context) ?: return HeadlineProbe(null, null)
        if (exit.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) {
            return HeadlineProbe(null, null)
        }
        val stream = runCatching { exit.traceInputStream }.getOrNull()
            ?: return HeadlineProbe(null, HeadlineMiss.STREAM_UNAVAILABLE)
        val text = runCatching {
            stream.bufferedReader().use { reader -> reader.readText() }
        }.getOrNull() ?: return HeadlineProbe(null, HeadlineMiss.TRACE_UNREADABLE)
        val headline = crashHeadline(text)
            ?: return HeadlineProbe(null, HeadlineMiss.NO_SIGNAL_LINE)
        return HeadlineProbe(headline, null)
    }

    fun latestCrashHeadline(context: Context): String? = probeCrashHeadline(context).headline

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

    // Rotated reports move into a subdirectory, so the newest match in the
    // working directory itself is the live report.
    fun latestFileIn(workingDir: File): File? =
        workingDir.listFiles { file ->
            file.isFile && file.name.startsWith("CrashReport-") && file.name.endsWith(".log")
        }?.maxWithOrNull(compareBy({ it.lastModified() }, { it.name }))

    fun headLines(
        workingDir: File,
        maxLines: Int = 40,
    ): List<String>? {
        val file = latestFileIn(workingDir) ?: return null
        val lines = runCatching { file.readLines() }.getOrNull() ?: return null
        return lines.filter { it.isNotBlank() }.take(maxLines)
    }

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
