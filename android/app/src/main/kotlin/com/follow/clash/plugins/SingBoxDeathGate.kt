package com.follow.clash.plugins

import android.app.ApplicationExitInfo
import com.kfusion.singbox.SingBoxExitInfo

// The dead pid settles the start poll at once, but the record explaining the death is published only after debuggerd finishes the tombstone; the probe decides which record is the attempt's own, so a stale one never settles the wait.
internal object SingBoxDeathGate {
    fun awaitRecord(
        attempts: Int,
        pause: () -> Unit,
        probe: () -> SingBoxExitInfo.Record?,
    ): SingBoxExitInfo.Record? {
        repeat(attempts) { index ->
            if (index > 0) pause()
            probe()?.let { return it }
        }
        return null
    }

    class Settled(
        val record: SingBoxExitInfo.Record,
        val headline: String?,
        val miss: SingBoxExitInfo.HeadlineMiss?,
    )

    // Only non-native deaths settle on the record alone; a native crash also waits out its tombstone.
    fun awaitSettled(
        attempts: Int,
        pause: () -> Unit,
        record: () -> SingBoxExitInfo.Record?,
        headline: () -> SingBoxExitInfo.HeadlineProbe,
    ): Settled? {
        var found: SingBoxExitInfo.Record? = null
        var lastMiss: SingBoxExitInfo.HeadlineMiss? = null
        repeat(attempts) { index ->
            if (index > 0) pause()
            val current = record() ?: return@repeat
            found = current
            if (current.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) {
                return Settled(current, null, null)
            }
            val probe = headline()
            if (probe.headline != null) return Settled(current, probe.headline, null)
            lastMiss = probe.miss
        }
        return found?.let { Settled(it, null, lastMiss) }
    }
}
