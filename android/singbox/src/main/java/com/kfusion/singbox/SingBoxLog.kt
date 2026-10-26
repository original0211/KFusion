package com.kfusion.singbox

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// The service process's log on disk; upstream it only reaches logcat.
object SingBoxLog {
    private const val MAX_FILE_BYTES = 256 * 1024
    private const val MAX_TAIL_CHARS = 900

    private val lock = Any()
    private val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private fun directory(context: Context) = File(context.filesDir, "singbox")

    fun append(context: Context, message: String) {
        appendTo(directory(context), message)
    }

    fun tail(context: Context, maxLines: Int): String =
        tailFrom(directory(context), maxLines)

    fun appendTo(directory: File, message: String) {
        synchronized(lock) {
            runCatching {
                directory.mkdirs()
                val target = File(directory, "service.log")
                if (target.isFile && target.length() > MAX_FILE_BYTES) {
                    val rotated = File(directory, "service.log.old")
                    rotated.delete()
                    target.renameTo(rotated)
                }
                val line = synchronized(stamp) { stamp.format(Date()) }
                target.appendText("$line $message\n")
            }
        }
    }

    fun tailFrom(directory: File, maxLines: Int): String {
        val target = File(directory, "service.log")
        if (!target.isFile) return ""
        val lines = runCatching { target.readLines() }.getOrDefault(emptyList())
            .filter { it.isNotBlank() }
            .takeLast(maxLines)
        var joined = lines.joinToString("\n")
        while (joined.length > MAX_TAIL_CHARS && joined.contains('\n')) {
            joined = joined.substringAfter('\n')
        }
        return joined
    }
}
