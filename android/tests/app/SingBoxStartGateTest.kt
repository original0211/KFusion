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
    fun thisAttemptsStartingWithADeadPidFails() {
        val starting = snapshot(SingBoxStatus.State.STARTING, updatedAt = epoch)
        assertEquals(
            SingBoxStartGate.Verdict.FAILED,
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
    fun thisAttemptsRunningWithADeadPidFails() {
        val running = snapshot(SingBoxStatus.State.RUNNING, updatedAt = epoch + 5)
        assertEquals(
            SingBoxStartGate.Verdict.FAILED,
            verdict(running, alive = { false }),
        )
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
