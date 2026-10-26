package com.follow.clash

import com.follow.clash.plugins.SingBoxCheckGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SingBoxCheckGateTest {
    @Test
    fun anAnswerOnTheFirstAttemptIsNotRetried() {
        var attempts = 0
        val message = SingBoxCheckGate.awaitResult(2) {
            attempts++
            ""
        }
        assertEquals("", message)
        assertEquals(1, attempts)
    }

    @Test
    fun anErrorAnswerIsNotRetriedEither() {
        var attempts = 0
        val message = SingBoxCheckGate.awaitResult(2) {
            attempts++
            "invalid config"
        }
        assertEquals("invalid config", message)
        assertEquals(1, attempts)
    }

    @Test
    fun aSilentAttemptEarnsExactlyOneRetry() {
        var attempts = 0
        val message = SingBoxCheckGate.awaitResult(2) {
            attempts++
            if (attempts == 1) null else ""
        }
        assertEquals("", message)
        assertEquals(2, attempts)
    }

    @Test
    fun twoSilentAttemptsGiveUpToTheTimeoutSentinel() {
        var attempts = 0
        val message = SingBoxCheckGate.awaitResult(2) {
            attempts++
            null
        }
        assertNull(message)
        assertEquals(2, attempts)
        assertEquals("sing-box-check-timeout", SingBoxCheckGate.TIMEOUT_SENTINEL)
    }
}
