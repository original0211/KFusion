package com.follow.clash.plugins

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
}
