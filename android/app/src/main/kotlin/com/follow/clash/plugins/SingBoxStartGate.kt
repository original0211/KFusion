package com.follow.clash.plugins

import com.kfusion.singbox.SingBoxStatus

// What one status-file poll means for the start that began at [epochMs].
internal object SingBoxStartGate {
    enum class Verdict { PENDING, RUNNING, FAILED, SUSPECT }

    // One start's total poll patience, counted from its epoch. A healthy
    // fetch phase alone has kept a start in flight past 49 s on field
    // devices, so the old 40 s budget condemned live starts; a real death
    // is confirmed through exit history in ~5 s, never by this budget.
    // The Dart channel budget (95 s) sits above it: the verdict stays
    // the service's.
    const val POLL_BUDGET_MS = 90_000L

    fun expired(nowMs: Long, epochMs: Long): Boolean =
        nowMs - epochMs >= POLL_BUDGET_MS

    fun verdict(
        snapshot: SingBoxStatus.Snapshot?,
        epochMs: Long,
        pidAlive: (Int) -> Boolean,
    ): Verdict {
        if (snapshot == null) return Verdict.PENDING
        if (snapshot.updatedAt < epochMs) return Verdict.PENDING
        return when (snapshot.state) {
            // The snapshot's pid belongs to the service process, whose /proc
            // entry the app process cannot see: an invisible pid is grounds
            // for suspicion only, never for a death verdict on its own.
            SingBoxStatus.State.STARTING ->
                if (snapshot.pid > 0 && !pidAlive(snapshot.pid)) {
                    Verdict.SUSPECT
                } else {
                    Verdict.PENDING
                }
            SingBoxStatus.State.RUNNING ->
                if (pidAlive(snapshot.pid)) Verdict.RUNNING else Verdict.SUSPECT
            SingBoxStatus.State.FAILED -> Verdict.FAILED
            SingBoxStatus.State.STOPPED -> Verdict.FAILED
        }
    }
}
