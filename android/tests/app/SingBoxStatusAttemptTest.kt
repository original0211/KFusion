package com.follow.clash

import com.kfusion.singbox.SingBoxStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SingBoxStatusAttemptTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun aMissingMirrorReadsAsNoOpenAttempt() {
        assertNull(SingBoxStatus.readAttemptFrom(folder.root))
    }

    @Test
    fun theMirrorRoundTripsTheOpenAttempt() {
        val attempt = SingBoxStatus.Attempt(3, 1, "outbounds and dns", 1_761_000_000_000L)
        SingBoxStatus.writeAttemptTo(folder.root, attempt)
        assertEquals(attempt, SingBoxStatus.readAttemptFrom(folder.root))
    }

    @Test
    fun aNormalAttemptRoundTripsWithABlankLevelName() {
        val attempt = SingBoxStatus.Attempt(1, -1, "", 1_761_000_000_000L)
        SingBoxStatus.writeAttemptTo(folder.root, attempt)
        assertEquals(attempt, SingBoxStatus.readAttemptFrom(folder.root))
    }

    @Test
    fun aLaterMarkReplacesTheMirror() {
        SingBoxStatus.writeAttemptTo(
            folder.root,
            SingBoxStatus.Attempt(1, -1, "", 1_761_000_000_000L),
        )
        val next = SingBoxStatus.Attempt(2, 0, "bare direct", 1_761_000_060_000L)
        SingBoxStatus.writeAttemptTo(folder.root, next)
        assertEquals(next, SingBoxStatus.readAttemptFrom(folder.root))
    }

    @Test
    fun clearingTheMirrorClosesTheAttempt() {
        SingBoxStatus.writeAttemptTo(
            folder.root,
            SingBoxStatus.Attempt(1, -1, "", 1_761_000_000_000L),
        )
        SingBoxStatus.clearAttemptIn(folder.root)
        assertNull(SingBoxStatus.readAttemptFrom(folder.root))
    }

    @Test
    fun aCorruptMirrorReadsAsNoOpenAttempt() {
        SingBoxStatus.attemptFileIn(folder.root).writeText("not a ledger\n")
        assertNull(SingBoxStatus.readAttemptFrom(folder.root))
    }
}
