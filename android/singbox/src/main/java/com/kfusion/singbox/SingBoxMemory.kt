package com.kfusion.singbox

import java.util.Locale

// Memory breadcrumb wording for start attempts; the figures come from
// Debug.getPss (this process) and ActivityManager.MemoryInfo (system).
object SingBoxMemory {
    fun pssFragment(pssKb: Long): String = "pss ${megabytes(pssKb)} MB"

    fun snapshotLine(pssKb: Long, availKb: Long, lowMemory: Boolean): String =
        "start: memory snapshot: ${pssFragment(pssKb)}, " +
            "avail ${megabytes(availKb)} MB, lowMemory=$lowMemory"

    private fun megabytes(kb: Long): String =
        String.format(Locale.US, "%.1f", kb / 1024.0)
}
