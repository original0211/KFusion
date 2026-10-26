package com.follow.clash

import com.follow.clash.plugins.SingBoxDeathGate
import com.kfusion.singbox.SingBoxExitInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class SingBoxDeathGateTest {
    private val record = SingBoxExitInfo.Record(5, 1_000L, "crash", 100)

    @Test
    fun aRecordOnTheFirstProbeSettlesWithoutPausing() {
        var probes = 0
        var pauses = 0
        val found = SingBoxDeathGate.awaitRecord(13, { pauses++ }) {
            probes++
            record
        }
        assertSame(record, found)
        assertEquals(1, probes)
        assertEquals(0, pauses)
    }

    @Test
    fun missedProbesAreRetriedUntilTheRecordLands() {
        var probes = 0
        var pauses = 0
        val found = SingBoxDeathGate.awaitRecord(13, { pauses++ }) {
            probes++
            if (probes < 3) null else record
        }
        assertSame(record, found)
        assertEquals(3, probes)
        assertEquals(2, pauses)
    }

    @Test
    fun silenceGivesUpAfterTheBoundedAttempts() {
        var probes = 0
        var pauses = 0
        val found = SingBoxDeathGate.awaitRecord(4, { pauses++ }) {
            probes++
            null
        }
        assertNull(found)
        assertEquals(4, probes)
        assertEquals(3, pauses)
    }

    private val nativeRecord = SingBoxExitInfo.Record(5, 1_000L, "crash", 100)
    private val signaledRecord = SingBoxExitInfo.Record(2, 1_000L, "", 100, status = 11)

    private fun miss(
        kind: SingBoxExitInfo.HeadlineMiss,
    ) = SingBoxExitInfo.HeadlineProbe(null, kind)

    @Test
    fun aNativeCrashWaitsUntilItsHeadlineLands() {
        var headlineProbes = 0
        val settled = SingBoxDeathGate.awaitSettled(13, {}, { nativeRecord }) {
            headlineProbes++
            if (headlineProbes < 3) {
                miss(SingBoxExitInfo.HeadlineMiss.NO_SIGNAL_LINE)
            } else {
                SingBoxExitInfo.HeadlineProbe("signal 11 (SIGSEGV), code 1", null)
            }
        }
        assertSame(nativeRecord, settled!!.record)
        assertEquals("signal 11 (SIGSEGV), code 1", settled.headline)
        assertNull(settled.miss)
        assertEquals(3, headlineProbes)
    }

    @Test
    fun aNativeCrashDegradesToTheRecordWhenTheHeadlineNeverLands() {
        var headlineProbes = 0
        val settled = SingBoxDeathGate.awaitSettled(4, {}, { nativeRecord }) {
            headlineProbes++
            miss(SingBoxExitInfo.HeadlineMiss.STREAM_UNAVAILABLE)
        }
        assertSame(nativeRecord, settled!!.record)
        assertNull(settled.headline)
        assertEquals(SingBoxExitInfo.HeadlineMiss.STREAM_UNAVAILABLE, settled.miss)
        assertEquals(4, headlineProbes)
    }

    @Test
    fun otherReasonsNeverWaitForAHeadline() {
        var headlineProbes = 0
        var pauses = 0
        val settled = SingBoxDeathGate.awaitSettled(13, { pauses++ }, { signaledRecord }) {
            headlineProbes++
            SingBoxExitInfo.HeadlineProbe("unreachable", null)
        }
        assertSame(signaledRecord, settled!!.record)
        assertNull(settled.headline)
        assertEquals(0, headlineProbes)
        assertEquals(0, pauses)
    }

    @Test
    fun aLateRecordWithAReadyHeadlineSettlesAtOnce() {
        var recordProbes = 0
        val settled = SingBoxDeathGate.awaitSettled(
            13,
            {},
            {
                recordProbes++
                if (recordProbes < 3) null else nativeRecord
            },
        ) {
            SingBoxExitInfo.HeadlineProbe("signal 7 (SIGBUS), code 2", null)
        }
        assertSame(nativeRecord, settled!!.record)
        assertEquals("signal 7 (SIGBUS), code 2", settled.headline)
        assertEquals(3, recordProbes)
    }

    @Test
    fun settledSilenceStillGivesUpEmpty() {
        val settled = SingBoxDeathGate.awaitSettled(3, {}, { null }) {
            SingBoxExitInfo.HeadlineProbe(null, null)
        }
        assertNull(settled)
    }
}
