package com.kfusion.singbox

import java.io.File

object SingBoxCacheGuard {
    fun cacheFileIn(workingDir: File): File = File(workingDir, "cache.db")

    fun staleFileIn(workingDir: File): File = File(workingDir, "cache.db.stale")

    fun isolate(workingDir: File): Long? {
        val cache = cacheFileIn(workingDir)
        if (!cache.isFile) return null
        val size = cache.length()
        val stale = staleFileIn(workingDir)
        stale.delete()
        return if (cache.renameTo(stale)) size else null
    }
}
