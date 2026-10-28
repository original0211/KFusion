package com.follow.clash

import com.follow.clash.plugins.SingBoxStartGate
import com.kfusion.singbox.SingBoxStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class SingBoxStartGateTest {
    private val epoch = 1_000_000L

    private fun snapshot(
        state: SingBoxStatus.State,
        updatedAt: Long,
        pid: Int = 4242,
    ) = SingBoxStatus.Snapshot(
        state = state,
        message = "",
        pid = pid,
        updatedAt = updatedAt,
    )

    private fun verdict(
        snapshot: SingBoxStatus.Snapshot?,
        alive: (Int) -> Boolean = { true },
    ) = SingBoxStartGate.verdict(snapshot, epoch, alive)

    @Test
    fun noSnapshotYetIsPending() {
        assertEquals(SingBoxStartGate.Verdict.PENDING, verdict(null))
    }

    @Test
    fun aPreviousAttemptsFailureDoesNotFailThisAttempt() {
        val stale = snapshot(SingBoxStatus.State.FAILED, updatedAt = epoch - 1)
        assertEquals(SingBoxStartGate.Verdict.PENDING, verdict(stale))
    }

    @Test
    fun aPreviousAttemptsRunningDoesNotPassThisAttempt() {
        val stale = snapshot(SingBoxStatus.State.RUNNING, updatedAt = epoch - 1)
        assertEquals(SingBoxStartGate.Verdict.PENDING, verdict(stale))
    }

    @Test
    fun thisAttemptsStartingIsPending() {
        val starting = snapshot(SingBoxStatus.State.STARTING, updatedAt = epoch)
        assertEquals(SingBoxStartGate.Verdict.PENDING, verdict(starting))
    }

    @Test
    fun thisAttemptsStartingWithAnUnseeablePidIsOnlySuspect() {
        val starting = snapshot(SingBoxStatus.State.STARTING, updatedAt = epoch)
        assertEquals(
            SingBoxStartGate.Verdict.SUSPECT,
            verdict(starting, alive = { false }),
        )
    }

    @Test
    fun thisAttemptsStartingWithAnUnknownPidIsPending() {
        val starting = snapshot(
            SingBoxStatus.State.STARTING,
            updatedAt = epoch,
            pid = -1,
        )
        assertEquals(
            SingBoxStartGate.Verdict.PENDING,
            verdict(starting, alive = { false }),
        )
    }

    @Test
    fun thisAttemptsRunningWithALivePidPasses() {
        val running = snapshot(SingBoxStatus.State.RUNNING, updatedAt = epoch + 5)
        assertEquals(SingBoxStartGate.Verdict.RUNNING, verdict(running))
    }

    @Test
    fun thisAttemptsRunningWithAnUnseeablePidIsOnlySuspect() {
        val running = snapshot(SingBoxStatus.State.RUNNING, updatedAt = epoch + 5)
        assertEquals(
            SingBoxStartGate.Verdict.SUSPECT,
            verdict(running, alive = { false }),
        )
    }

    // Field replay (2026-10-28 13:09, attempt #160): polls meet the service's
    // dispatch write (its pid, refreshed 4-6 ms after each epoch), never a death.
    @Test
    fun theAttempt160TimelineNeverFailsTheStart() {
        val appPid = 1000
        val servicePid = 24907
        val seeable: (Int) -> Boolean = { it == appPid }
        val secondEpoch = 1_793_164_177_187L
        val thirdEpoch = 1_793_164_184_405L
        val polls = listOf(
            secondEpoch to snapshot(
                SingBoxStatus.State.STARTING,
                updatedAt = secondEpoch,
                pid = appPid,
            ),
            secondEpoch to snapshot(
                SingBoxStatus.State.STARTING,
                updatedAt = secondEpoch + 4,
                pid = servicePid,
            ),
            thirdEpoch to snapshot(
                SingBoxStatus.State.STARTING,
                updatedAt = thirdEpoch,
                pid = appPid,
            ),
            thirdEpoch to snapshot(
                SingBoxStatus.State.STARTING,
                updatedAt = thirdEpoch + 6,
                pid = servicePid,
            ),
        )
        polls.forEach { (epochMs, snap) ->
            assertEquals(
                if (snap.pid == servicePid) {
                    SingBoxStartGate.Verdict.SUSPECT
                } else {
                    SingBoxStartGate.Verdict.PENDING
                },
                SingBoxStartGate.verdict(snap, epochMs, seeable),
            )
        }
    }

    @Test
    fun thisAttemptsFailureFails() {
        val failed = snapshot(SingBoxStatus.State.FAILED, updatedAt = epoch + 5)
        assertEquals(SingBoxStartGate.Verdict.FAILED, verdict(failed))
    }

    @Test
    fun aStopDuringThisAttemptFails() {
        val stopped = snapshot(SingBoxStatus.State.STOPPED, updatedAt = epoch + 5)
        assertEquals(SingBoxStartGate.Verdict.FAILED, verdict(stopped))
    }
}
