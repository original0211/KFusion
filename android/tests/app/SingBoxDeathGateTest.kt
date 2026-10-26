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
}
