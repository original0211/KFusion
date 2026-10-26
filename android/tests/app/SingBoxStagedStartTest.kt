package com.follow.clash

import com.kfusion.singbox.SingBoxCacheGuard
import com.kfusion.singbox.SingBoxStagedStart
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SingBoxStagedStartTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val since = 1_761_000_000_000L

    @Test
    fun decideIgnoresDeathsWithoutAnOpenAttempt() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = false,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 5,
            exitAt = since + 100,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun decideArmsStagedAfterANativeDeathInANormalStart() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 5,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.STAGED, decision)
    }

    @Test
    fun decideReportsAfterANativeDeathInsideAStagedLevel() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = 2,
            exitReason = 5,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.REPORT, decision)
    }

    @Test
    fun decideIgnoresDeathsThatAreNeitherNativeNorLowMemory() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 2,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun decideArmsStagedAfterALowMemoryDeathInANormalStart() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 3,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.STAGED, decision)
    }

    @Test
    fun decideReportsAfterALowMemoryDeathInsideAStagedLevel() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = 2,
            exitReason = 3,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.REPORT, decision)
    }

    @Test
    fun decideIgnoresLowMemoryDeathsWithoutAnOpenAttempt() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = false,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 3,
            exitAt = since + 90,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun decideIgnoresLowMemoryDeathsOlderThanTheAttempt() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 3,
            exitAt = since - 120_000,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun attemptDeathAssociationEndsAtTheSlackBoundary() {
        val slack = SingBoxStagedStart.ASSOCIATION_SLACK_MS
        assertTrue(SingBoxStagedStart.isAttemptDeath(true, since - slack, since))
        assertTrue(!SingBoxStagedStart.isAttemptDeath(true, since - slack - 1, since))
        assertTrue(SingBoxStagedStart.isAttemptDeath(true, since + 90, since))
        assertTrue(!SingBoxStagedStart.isAttemptDeath(false, since + 90, since))
    }

    @Test
    fun decideIgnoresExitsOlderThanTheAttempt() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = 5,
            exitAt = since - 120_000,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun decideIgnoresMissingExitRecords() {
        val decision = SingBoxStagedStart.decide(
            attemptOpen = true,
            attemptLevel = SingBoxStagedStart.NORMAL_LEVEL,
            exitReason = null,
            exitAt = 0,
            attemptSince = since,
        )
        assertEquals(SingBoxStagedStart.Decision.NORMAL, decision)
    }

    @Test
    fun planCoversEverySectionOfARenderedConfig() {
        val levels = SingBoxStagedStart.levels(
            SingBoxStagedStart.Facts(
                hasRuleSets = true,
                hasInbounds = true,
                hasExperimental = true,
            ),
        )
        assertEquals(
            listOf("bare direct", "outbounds and dns", "rule sets", "inbounds", "full config"),
            levels.map { it.name },
        )
        assertEquals(listOf(0, 1, 2, 3, 4), levels.map { it.index })
        assertTrue(levels.last().last)
        assertTrue(levels.dropLast(1).none { it.last })
    }

    @Test
    fun planSkipsRuleSetsWhenTheConfigHasNone() {
        val levels = SingBoxStagedStart.levels(
            SingBoxStagedStart.Facts(
                hasRuleSets = false,
                hasInbounds = true,
                hasExperimental = true,
            ),
        )
        assertEquals(
            listOf("bare direct", "outbounds and dns", "inbounds", "full config"),
            levels.map { it.name },
        )
    }

    @Test
    fun planEndsAtInboundsWithoutAnExperimentalSection() {
        val levels = SingBoxStagedStart.levels(
            SingBoxStagedStart.Facts(
                hasRuleSets = true,
                hasInbounds = true,
                hasExperimental = false,
            ),
        )
        assertEquals("inbounds", levels.last().name)
        assertTrue(levels.last().last)
    }

    @Test
    fun verdictNamesTheCrashedLevel() {
        assertEquals(
            "staged start: crashed at L2 (rule sets)",
            SingBoxStagedStart.verdict(5, 2, "rule sets"),
        )
        assertEquals(
            "staged start: crashed at L0",
            SingBoxStagedStart.verdict(5, 0, ""),
        )
    }

    @Test
    fun verdictNamesTheLowMemoryKilledLevel() {
        assertEquals(
            "staged start: low-memory killed at L4 (full config)",
            SingBoxStagedStart.verdict(3, 4, "full config"),
        )
        assertEquals(
            "staged start: low-memory killed at L0",
            SingBoxStagedStart.verdict(3, 0, ""),
        )
    }

    @Test
    fun cacheIsolateRenamesAndKeepsOneRollingCopy() {
        val working = folder.newFolder("singbox")
        assertNull(SingBoxCacheGuard.isolate(working))
        SingBoxCacheGuard.cacheFileIn(working).writeText("first")
        assertEquals(5L, SingBoxCacheGuard.isolate(working))
        assertTrue(!SingBoxCacheGuard.cacheFileIn(working).exists())
        assertEquals("first", SingBoxCacheGuard.staleFileIn(working).readText())
        SingBoxCacheGuard.cacheFileIn(working).writeText("second cache")
        assertEquals(12L, SingBoxCacheGuard.isolate(working))
        assertEquals("second cache", SingBoxCacheGuard.staleFileIn(working).readText())
    }
}
