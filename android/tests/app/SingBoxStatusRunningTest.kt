package com.follow.clash

import com.kfusion.singbox.SingBoxExitInfo
import com.kfusion.singbox.SingBoxStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SingBoxStatusRunningTest {
    private val settledAt = 1_000_000L

    private fun snapshot(
        state: SingBoxStatus.State,
        updatedAt: Long = settledAt,
    ) = SingBoxStatus.Snapshot(
        state = state,
        message = "",
        pid = 4242,
        updatedAt = updatedAt,
    )

    private fun death(timestamp: Long) =
        SingBoxExitInfo.Record(2, timestamp, "", 100)

    private fun isRunning(
        snapshot: SingBoxStatus.Snapshot,
        alive: Boolean = false,
        latestExit: SingBoxExitInfo.Record? = null,
    ) = SingBoxStatus.isRunning(snapshot, { alive }, latestExit)

    // The field case: the service settled and reported RUNNING, but its
    // pid is a sibling process's, invisible to the app process.
    @Test
    fun aRunningReportWithAnUnseeablePidStillReadsAsRunning() {
        assertTrue(isRunning(snapshot(SingBoxStatus.State.RUNNING)))
    }

    @Test
    fun aRunningReportWithAVisiblePidReadsAsRunning() {
        assertTrue(
            isRunning(
                snapshot(SingBoxStatus.State.RUNNING),
                alive = true,
                latestExit = death(settledAt + 1_000),
            ),
        )
    }

    @Test
    fun aDeathRecordedAfterTheRunningWriteRefutesTheReport() {
        assertFalse(
            isRunning(
                snapshot(SingBoxStatus.State.RUNNING),
                latestExit = death(settledAt + 1_000),
            ),
        )
    }

    @Test
    fun aDeathRecordedBeforeTheRunningWriteBelongsToAnEarlierIncarnation() {
        assertTrue(
            isRunning(
                snapshot(SingBoxStatus.State.RUNNING),
                latestExit = death(settledAt - 1_000),
            ),
        )
    }

    @Test
    fun terminalAndInFlightReportsNeverReadAsRunning() {
        for (state in listOf(
            SingBoxStatus.State.STARTING,
            SingBoxStatus.State.FAILED,
            SingBoxStatus.State.STOPPED,
        )) {
            assertFalse(isRunning(snapshot(state), alive = true))
        }
    }
}
