package com.follow.clash.plugins

import com.kfusion.singbox.SingBoxStatus

// What one status-file poll means for the start that began at [epochMs].
internal object SingBoxStartGate {
    enum class Verdict { PENDING, RUNNING, FAILED }

    fun verdict(
        snapshot: SingBoxStatus.Snapshot?,
        epochMs: Long,
        pidAlive: (Int) -> Boolean,
    ): Verdict {
        if (snapshot == null) return Verdict.PENDING
        if (snapshot.updatedAt < epochMs) return Verdict.PENDING
        return when (snapshot.state) {
            SingBoxStatus.State.STARTING ->
                if (snapshot.pid > 0 && !pidAlive(snapshot.pid)) {
                    Verdict.FAILED
                } else {
                    Verdict.PENDING
                }
            SingBoxStatus.State.RUNNING ->
                if (pidAlive(snapshot.pid)) Verdict.RUNNING else Verdict.FAILED
            SingBoxStatus.State.FAILED -> Verdict.FAILED
            SingBoxStatus.State.STOPPED -> Verdict.FAILED
        }
    }
}
