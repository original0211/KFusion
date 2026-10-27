package com.kfusion.singbox

import java.io.File

// The start verdict races the system's asynchronous exit-record publication
// and keeps losing it; this letter is the deterministic rematch, harvested
// at the next service start and persisted for the card and the log.
object SingBoxDeathLetter {
    data class Letter(
        val seq: Long,
        val since: Long,
        val scanned: Int,
        val record: SingBoxExitInfo.Record?,
        val newestOther: String?,
    )

    fun fileIn(directory: File): File = File(directory, "death-letter.txt")

    // The earliest sing-box record at or after the attempt's start is its death.
    fun select(
        records: List<SingBoxExitInfo.Record>,
        attemptSince: Long,
        consumedThrough: Long,
    ): SingBoxExitInfo.Record? =
        records
            .filter {
                it.processName.endsWith(SingBoxExitInfo.PROCESS_SUFFIX) &&
                    it.timestamp >= attemptSince - SingBoxStagedStart.ASSOCIATION_SLACK_MS &&
                    it.timestamp > consumedThrough
            }
            .minByOrNull { it.timestamp }

    fun newestOtherOf(records: List<SingBoxExitInfo.Record>): String? =
        records.maxByOrNull { it.timestamp }?.let { record ->
            val name = record.processName.ifBlank { "unknown process" }
            "$name ${SingBoxExitInfo.tailOf(record)}"
        }

    fun cardLine(letter: Letter): String {
        val record = letter.record
        if (record != null) {
            return "death letter: attempt #${letter.seq} died: ${SingBoxExitInfo.tailOf(record)}"
        }
        if (letter.scanned == 0) {
            return "death letter: attempt #${letter.seq} left no exit record (no records published)"
        }
        val newest = letter.newestOther?.let { " - newest: $it" } ?: ""
        return "death letter: attempt #${letter.seq} left no exit record " +
            "(scanned ${letter.scanned})$newest"
    }

    // A letter speaks on its own attempt's card or the next attempt's; older is superseded.
    fun lineFor(
        letter: Letter?,
        attemptSeq: Long,
    ): String? {
        if (letter == null) return null
        if (letter.seq != attemptSeq && letter.seq != attemptSeq - 1) return null
        return cardLine(letter)
    }

    fun writeTo(
        directory: File,
        letter: Letter,
    ) {
        val record = letter.record
        val payload =
            buildString {
                append("seq=").append(letter.seq).append('\n')
                append("since=").append(letter.since).append('\n')
                append("scanned=").append(letter.scanned).append('\n')
                if (record != null) {
                    append("reason=").append(record.reason).append('\n')
                    append("status=").append(record.status).append('\n')
                    append("timestamp=").append(record.timestamp).append('\n')
                    append("process=").append(record.processName).append('\n')
                    append("description=").append(record.description.oneLine()).append('\n')
                }
                letter.newestOther?.let { append("newest=").append(it.oneLine()).append('\n') }
            }
        directory.mkdirs()
        val target = fileIn(directory)
        val temp = File(directory, "${target.name}.tmp")
        temp.writeText(payload)
        temp.renameTo(target)
    }

    fun readFrom(directory: File): Letter? {
        val target = fileIn(directory)
        if (!target.isFile) return null
        return runCatching {
            val fields =
                target
                    .readLines()
                    .mapNotNull { line ->
                        val split = line.indexOf('=')
                        if (split <= 0) null else line.substring(0, split) to line.substring(split + 1)
                    }.toMap()
            val record =
                fields["reason"]?.let { reason ->
                    SingBoxExitInfo.Record(
                        reason = reason.toInt(),
                        timestamp = fields.getValue("timestamp").toLong(),
                        description = fields["description"] ?: "",
                        importance = 0,
                        status = fields["status"]?.toIntOrNull() ?: 0,
                        processName = fields["process"] ?: "",
                    )
                }
            Letter(
                seq = fields.getValue("seq").toLong(),
                since = fields["since"]?.toLongOrNull() ?: 0L,
                scanned = fields["scanned"]?.toIntOrNull() ?: 0,
                record = record,
                newestOther = fields["newest"],
            )
        }.getOrNull()
    }

    private fun String.oneLine(): String = replace('\n', ' ').take(300)
}
