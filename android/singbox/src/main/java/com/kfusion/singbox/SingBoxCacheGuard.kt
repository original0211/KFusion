package com.kfusion.singbox

import android.app.ApplicationExitInfo
import java.io.File

object SingBoxCacheGuard {
    private const val PROBE_PREFIX = "cache-probe-"

    fun cacheFileIn(workingDir: File): File = File(workingDir, "cache.db")

    fun staleFileIn(workingDir: File): File = File(workingDir, "cache.db.stale")

    fun probeCacheName(nonce: Long): String = "$PROBE_PREFIX$nonce.db"

    fun sweepProbeCaches(workingDir: File): Int {
        val files = workingDir.listFiles { file -> file.name.startsWith(PROBE_PREFIX) }
            ?: return 0
        var removed = 0
        for (file in files) {
            if (file.delete()) removed++
        }
        return removed
    }

    fun isolationDue(reason: Int): Boolean =
        reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            reason == ApplicationExitInfo.REASON_SIGNALED

    fun isolate(workingDir: File): Long? {
        val cache = cacheFileIn(workingDir)
        if (!cache.isFile) return null
        val size = cache.length()
        val stale = staleFileIn(workingDir)
        stale.delete()
        return if (cache.renameTo(stale)) size else null
    }
}
