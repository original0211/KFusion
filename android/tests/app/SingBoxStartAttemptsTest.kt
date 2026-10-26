package com.follow.clash

import com.kfusion.singbox.SingBoxStartAttempts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SingBoxStartAttemptsTest {
    @Test
    fun aFreshAttemptIsLiveAndOwnsTheGate() {
        val attempts = SingBoxStartAttempts()
        val attempt = attempts.begin()
        assertTrue(attempts.isLive(attempt))
        assertTrue(attempts.ownsGate(attempt))
    }

    @Test
    fun anInvalidatedAttemptIsNotLive() {
        val attempts = SingBoxStartAttempts()
        val attempt = attempts.begin()
        attempts.invalidate()
        assertFalse(attempts.isLive(attempt))
    }

    @Test
    fun aNewerAttemptSupersedesTheOlderOne() {
        val attempts = SingBoxStartAttempts()
        val first = attempts.begin()
        val second = attempts.begin()
        assertFalse(attempts.isLive(first))
        assertFalse(attempts.ownsGate(first))
        assertTrue(attempts.isLive(second))
        assertTrue(attempts.ownsGate(second))
    }

    @Test
    fun attemptIdsIncrease() {
        val attempts = SingBoxStartAttempts()
        val first = attempts.begin()
        val second = attempts.begin()
        assertEquals(first + 1, second)
    }
}
