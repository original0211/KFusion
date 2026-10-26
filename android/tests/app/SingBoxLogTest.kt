package com.follow.clash

import com.kfusion.singbox.SingBoxLog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SingBoxLogTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun tailOfAMissingLogIsEmpty() {
        assertEquals("", SingBoxLog.tailFrom(folder.root, 5))
    }

    @Test
    fun tailReturnsTheLastLinesInOrder() {
        repeat(5) { SingBoxLog.appendTo(folder.root, "line $it") }
        val tail = SingBoxLog.tailFrom(folder.root, 2)
        val lines = tail.lines()
        assertEquals(2, lines.size)
        assertTrue(lines[0].endsWith("line 3"))
        assertTrue(lines[1].endsWith("line 4"))
    }

    @Test
    fun cardTailSkipsTraceDumpLinesThatThePlainTailKeeps() {
        SingBoxLog.appendTo(folder.root, "process exit: CRASH_NATIVE(5)")
        SingBoxLog.appendTo(folder.root, "exit trace excerpt:")
        SingBoxLog.appendTo(folder.root, "exit trace: r7 0000007a r8 00000001")
        SingBoxLog.appendTo(folder.root, "exit trace: #00 pc 00000000 libbox.so")
        SingBoxLog.appendTo(folder.root, "staged: crashed at L0 (bare direct)")
        val plain = SingBoxLog.tailFrom(folder.root, 10)
        assertTrue(plain.contains("r7 0000007a"))
        val card = SingBoxLog.cardTailFrom(folder.root, 10)
        assertTrue(!card.contains("r7 0000007a"))
        assertTrue(!card.contains("exit trace"))
        assertTrue(card.contains("process exit: CRASH_NATIVE(5)"))
        assertTrue(card.contains("staged: crashed at L0 (bare direct)"))
    }

    @Test
    fun appendingBeyondTheCapRotatesThePreviousLog() {
        val line = "x".repeat(64 * 1024)
        repeat(5) { SingBoxLog.appendTo(folder.root, line) }
        assertTrue(File(folder.root, "service.log.old").isFile)
        assertTrue(File(folder.root, "service.log").length() <= 256 * 1024 + line.length)
    }
}
