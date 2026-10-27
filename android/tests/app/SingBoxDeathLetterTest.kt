package com.follow.clash

import com.kfusion.singbox.SingBoxDeathLetter
import com.kfusion.singbox.SingBoxExitInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SingBoxDeathLetterTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun record(
        process: String,
        timestamp: Long,
        reason: Int = 2,
        status: Int = 9,
    ) = SingBoxExitInfo.Record(reason, timestamp, "", 100, status, process)

    @Test
    fun selectTakesTheEarliestSingBoxDeathAtOrAfterTheAttemptStart() {
        val records =
            listOf(
                record("com.follow.clash", 5_000L),
                record("com.follow.clash:singbox", 20_000L),
                record("com.follow.clash:singbox", 12_000L),
            )
        val picked = SingBoxDeathLetter.select(records, attemptSince = 10_000L, consumedThrough = 0L)
        assertEquals(12_000L, picked?.timestamp)
    }

    @Test
    fun selectIgnoresDeathsBeforeTheAssociationWindow() {
        val records = listOf(record("com.follow.clash:singbox", 4_999L))
        assertNull(SingBoxDeathLetter.select(records, attemptSince = 10_000L, consumedThrough = 0L))
    }

    @Test
    fun selectSkipsRecordsAlreadyConsumedByAnEarlierLetter() {
        val records =
            listOf(
                record("com.follow.clash:singbox", 12_000L),
                record("com.follow.clash:singbox", 20_000L),
            )
        val picked =
            SingBoxDeathLetter.select(records, attemptSince = 10_000L, consumedThrough = 12_000L)
        assertEquals(20_000L, picked?.timestamp)
    }

    @Test
    fun selectFindsNothingInMainProcessRecordsAlone() {
        val records = listOf(record("com.follow.clash", 12_000L))
        assertNull(SingBoxDeathLetter.select(records, attemptSince = 10_000L, consumedThrough = 0L))
    }

    @Test
    fun cardLineNamesTheDeathCategory() {
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 7L,
                since = 10_000L,
                scanned = 3,
                record = record("com.follow.clash:singbox", 12_000L),
                newestOther = null,
            )
        val line = SingBoxDeathLetter.cardLine(letter)
        assertTrue(line.startsWith("death letter: attempt #7 died: SIGNALED(2) SIGKILL(9) at "))
    }

    @Test
    fun cardLineReportsAnEmptyHarvest() {
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 7L,
                since = 10_000L,
                scanned = 0,
                record = null,
                newestOther = null,
            )
        assertEquals(
            "death letter: attempt #7 left no exit record (no records published)",
            SingBoxDeathLetter.cardLine(letter),
        )
    }

    @Test
    fun cardLineReportsTheNewestRecordWhenNoDeathMatched() {
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 7L,
                since = 10_000L,
                scanned = 2,
                record = null,
                newestOther = "com.follow.clash EXIT_SELF(3) at 2026-10-27 20:10:50",
            )
        val line = SingBoxDeathLetter.cardLine(letter)
        assertTrue(line.contains("(scanned 2)"))
        assertTrue(line.contains("newest: com.follow.clash EXIT_SELF(3)"))
    }

    @Test
    fun letterRoundTripsThroughItsFile() {
        val working = folder.newFolder("singbox")
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 7L,
                since = 10_000L,
                scanned = 3,
                record = record("com.follow.clash:singbox", 12_000L),
                newestOther = null,
            )
        SingBoxDeathLetter.writeTo(working, letter)
        val read = SingBoxDeathLetter.readFrom(working)
        assertEquals(7L, read?.seq)
        assertEquals(10_000L, read?.since)
        assertEquals(3, read?.scanned)
        assertEquals(2, read?.record?.reason)
        assertEquals(9, read?.record?.status)
        assertEquals(12_000L, read?.record?.timestamp)
        assertEquals("com.follow.clash:singbox", read?.record?.processName)
        assertNull(read?.newestOther)
    }

    @Test
    fun unmatchedLetterRoundTripsThroughItsFile() {
        val working = folder.newFolder("singbox")
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 8L,
                since = 30_000L,
                scanned = 1,
                record = null,
                newestOther = "com.follow.clash EXIT_SELF(3) at 2026-10-27 20:10:50",
            )
        SingBoxDeathLetter.writeTo(working, letter)
        val read = SingBoxDeathLetter.readFrom(working)
        assertEquals(8L, read?.seq)
        assertEquals(1, read?.scanned)
        assertNull(read?.record)
        assertEquals("com.follow.clash EXIT_SELF(3) at 2026-10-27 20:10:50", read?.newestOther)
    }

    @Test
    fun lineForAcceptsTheOwnAndThePreviousAttemptOnly() {
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 7L,
                since = 10_000L,
                scanned = 0,
                record = null,
                newestOther = null,
            )
        assertEquals(SingBoxDeathLetter.cardLine(letter), SingBoxDeathLetter.lineFor(letter, 7L))
        assertEquals(SingBoxDeathLetter.cardLine(letter), SingBoxDeathLetter.lineFor(letter, 8L))
        assertNull(SingBoxDeathLetter.lineFor(letter, 9L))
        assertNull(SingBoxDeathLetter.lineFor(null, 7L))
    }

    @Test
    fun readFromAMissingFileIsNull() {
        assertNull(SingBoxDeathLetter.readFrom(folder.newFolder("empty")))
    }

    @Test
    fun theFieldTimelineDeliversThePreviousDeathToTheNextCard() {
        // v0.2.23, 22:33-22:39 replayed at ledger level: A dies; B is up
        // within a second, before A's record is published, so B's harvest
        // writes an unmatched letter for A; B dies and its record lands;
        // C starts minutes later. C's card must carry B's letter, and A's
        // stale unmatched letter must not speak on C's card.
        val working = folder.newFolder("singbox")
        val aSince = 100_000L
        val bSince = 160_000L
        val atBsHarvest = listOf(record("com.follow.clash", 90_000L))
        val aPicked = SingBoxDeathLetter.select(atBsHarvest, aSince, consumedThrough = 0L)
        assertNull(aPicked)
        val aLetter =
            SingBoxDeathLetter.Letter(
                seq = 1L,
                since = aSince,
                scanned = atBsHarvest.size,
                record = null,
                newestOther = SingBoxDeathLetter.newestOtherOf(atBsHarvest),
            )
        SingBoxDeathLetter.writeTo(working, aLetter)

        val bDeath = record("com.follow.clash:singbox", 190_000L)
        val atCsHarvest = listOf(bDeath, record("com.follow.clash", 90_000L))
        val bPicked = SingBoxDeathLetter.select(atCsHarvest, bSince, consumedThrough = 0L)
        assertEquals(190_000L, bPicked?.timestamp)
        val bLetter =
            SingBoxDeathLetter.Letter(
                seq = 2L,
                since = bSince,
                scanned = atCsHarvest.size,
                record = bPicked,
                newestOther = null,
            )
        SingBoxDeathLetter.writeTo(working, bLetter)

        val onCsCard = SingBoxDeathLetter.lineFor(SingBoxDeathLetter.readFrom(working), 3L)
        assertEquals(SingBoxDeathLetter.cardLine(bLetter), onCsCard)
        assertTrue(onCsCard!!.contains("attempt #2 died:"))
        assertNull(SingBoxDeathLetter.lineFor(aLetter, 3L))
    }

    @Test
    fun aStagedDeathsLetterReachesTheNextCardThroughTheFile() {
        // A staged start walks several levels under one seq (its level is a
        // field, not a seq), so the letter it leaves behind is keyed by the
        // start's single seq and the next attempt quotes it like any other.
        val working = folder.newFolder("singbox")
        val letter =
            SingBoxDeathLetter.Letter(
                seq = 4L,
                since = 300_000L,
                scanned = 2,
                record = record("com.follow.clash:singbox", 330_000L),
                newestOther = null,
            )
        SingBoxDeathLetter.writeTo(working, letter)
        val read = SingBoxDeathLetter.readFrom(working)
        assertEquals(SingBoxDeathLetter.cardLine(letter), SingBoxDeathLetter.lineFor(read, 5L))
        assertEquals(SingBoxDeathLetter.cardLine(letter), SingBoxDeathLetter.lineFor(read, 4L))
        assertNull(SingBoxDeathLetter.lineFor(read, 6L))
    }
}
