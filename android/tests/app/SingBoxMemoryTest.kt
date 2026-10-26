package com.follow.clash

import com.kfusion.singbox.SingBoxMemory
import org.junit.Assert.assertEquals
import org.junit.Test

class SingBoxMemoryTest {
    @Test
    fun pssFragmentFormatsKilobytesAsMegabytes() {
        assertEquals("pss 200.0 MB", SingBoxMemory.pssFragment(204_800))
        assertEquals("pss 1.5 MB", SingBoxMemory.pssFragment(1_500))
        assertEquals("pss 0.0 MB", SingBoxMemory.pssFragment(0))
    }

    @Test
    fun snapshotLineCarriesPssAvailAndTheLowMemoryFlag() {
        assertEquals(
            "start: memory snapshot: pss 200.0 MB, avail 1024.0 MB, lowMemory=false",
            SingBoxMemory.snapshotLine(204_800, 1_048_576, false),
        )
        assertEquals(
            "start: memory snapshot: pss 200.0 MB, avail 1024.0 MB, lowMemory=true",
            SingBoxMemory.snapshotLine(204_800, 1_048_576, true),
        )
    }
}
