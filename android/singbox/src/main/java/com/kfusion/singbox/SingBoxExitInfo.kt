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
        val processName: String = "",
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

    fun recordLine(record: Record?): String =
        if (record == null) {
            "exit record: not published yet"
        } else {
            "exit record: ${exitTail(record)}"
        }

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

    fun tailOf(record: Record): String = exitTail(record)

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
        return recordOf(exit)
    }

    // Every record published for this package, newest first; null = the platform cannot answer.
    fun all(context: Context): List<Record>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val exits = exitInfos(context, ALL_RECORDS_CAP) ?: return null
        return exits.map { recordOf(it) }
    }

    private fun recordOf(exit: ApplicationExitInfo): Record =
        Record(
            reason = exit.reason,
            timestamp = exit.timestamp,
            description = exit.description.orEmpty(),
            importance = exit.importance,
            status = exit.status,
            processName = exit.processName.orEmpty(),
        )

    fun traceExcerpt(
        context: Context,
        maxChars: Int = 1200,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        // The getter itself can throw on records that carry no trace; it runs
        // ahead of the death-letter harvest, so a throw must not skip both.
        val stream = runCatching { latestExitInfo(context)?.traceInputStream }
            .getOrNull() ?: return null
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
        val records = exitInfos(context, 8) ?: return null
        return records.firstOrNull { it.processName.endsWith(PROCESS_SUFFIX) }
    }

    private fun exitInfos(
        context: Context,
        maxNum: Int,
    ): List<ApplicationExitInfo>? {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return null
        return runCatching {
            manager.getHistoricalProcessExitReasons(context.packageName, 0, maxNum)
        }.getOrNull()
    }

    // A concrete cap, not the 0 = "all" form: latest() (cap 8) demonstrably
    // answers on the field device while no death letter was ever harvested
    // through the 0 form there, so all() stops depending on that reading.
    private const val ALL_RECORDS_CAP = 64
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

    // One wording on both card paths: no file, stale file, unusable file.
    fun reasonLineIn(
        workingDir: File,
        notBeforeMs: Long?,
    ): String {
        val file = latestFileIn(workingDir) ?: return "crash reason: no report"
        if (notBeforeMs != null && file.lastModified() < notBeforeMs) {
            return "crash reason: no fresh report"
        }
        val first = headLines(workingDir, 1)?.firstOrNull()
        return "crash reason: " + (first?.take(300) ?: "report unreadable")
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

object SingBoxStageMarkers {
    const val FILE_NAME = "kfusion-stage-markers.log"

    // The first marker every incarnation writes; marks after its last occurrence are the newest attempt's.
    const val ATTEMPT_BEGIN_STAGE = "daemon.new-instance.begin"

    fun fileIn(workingDir: File): File = File(workingDir, FILE_NAME)

    // Null when no marker file exists; a present file that fails to read also
    // yields null, and the caller separates the two via fileIn().isFile.
    fun tailLines(
        workingDir: File,
        maxLines: Int = 30,
    ): List<String>? {
        val file = fileIn(workingDir)
        if (!file.isFile) return null
        val lines = runCatching { file.readLines() }.getOrNull() ?: return null
        return lines.filter { it.isNotBlank() }.takeLast(maxLines)
    }

    fun windowLines(
        lines: List<String>,
        maxLines: Int = 30,
    ): List<String> {
        val begin = lines.indexOfLast { stageOf(it) == ATTEMPT_BEGIN_STAGE }
        val window = if (begin < 0) lines else lines.drop(begin + 1)
        return window.takeLast(maxLines)
    }

    fun tailLinesInWindow(
        workingDir: File,
        notBeforeMs: Long,
        maxLines: Int = 30,
    ): List<String>? {
        val file = fileIn(workingDir)
        if (!file.isFile) return null
        if (file.lastModified() < notBeforeMs) return emptyList()
        val lines = runCatching { file.readLines() }.getOrNull() ?: return null
        return windowLines(lines.filter { it.isNotBlank() }, maxLines)
    }

    fun tailLineInWindow(
        workingDir: File,
        notBeforeMs: Long,
    ): String {
        if (!fileIn(workingDir).isFile) return "stage mark: no marks recorded"
        val tail = tailLinesInWindow(workingDir, notBeforeMs, 1)
            ?: return "stage mark: markers unreadable"
        val last = tail.lastOrNull() ?: return "stage mark: no marks this attempt"
        return "stage mark: " + last.take(300)
    }

    private fun stageOf(line: String): String = line.substringBefore(" +")
}
