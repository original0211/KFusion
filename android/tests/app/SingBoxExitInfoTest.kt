package com.follow.clash

import com.kfusion.singbox.SingBoxCrashReport
import com.kfusion.singbox.SingBoxExitInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SingBoxExitInfoTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun reasonLabelsCoverTheDecisiveCodes() {
        assertEquals("EXIT_SELF", SingBoxExitInfo.reasonLabel(1))
        assertEquals("SIGNALED", SingBoxExitInfo.reasonLabel(2))
        assertEquals("LOW_MEMORY", SingBoxExitInfo.reasonLabel(3))
        assertEquals("CRASH", SingBoxExitInfo.reasonLabel(4))
        assertEquals("CRASH_NATIVE", SingBoxExitInfo.reasonLabel(5))
        assertEquals("ANR", SingBoxExitInfo.reasonLabel(6))
        assertEquals("UNRECOGNIZED", SingBoxExitInfo.reasonLabel(9999))
    }

    @Test
    fun summaryLineCarriesLabelCodeAndDescription() {
        val record = SingBoxExitInfo.Record(5, 1_761_000_000_000L, "native crash", 100)
        val line = SingBoxExitInfo.summaryLine(record)
        assertTrue(line.startsWith("process exit: CRASH_NATIVE(5) at "))
        assertTrue(line.endsWith(" - native crash"))
    }

    @Test
    fun summaryLineOmitsABlankDescription() {
        val record = SingBoxExitInfo.Record(3, 1_761_000_000_000L, "", 100)
        val line = SingBoxExitInfo.summaryLine(record)
        assertTrue(line.startsWith("process exit: LOW_MEMORY(3) at "))
        assertTrue(!line.contains(" - "))
    }

    @Test
    fun crashReportIsUnreadUntilItChanges() {
        val working = folder.newFolder("singbox")
        assertNull(SingBoxCrashReport.unreadLines(working, 0L))
        SingBoxCrashReport.fileIn(working).writeText("panic: boom\n")
        val first = SingBoxCrashReport.unreadLines(working, 0L)
        assertNotNull(first)
        assertEquals(listOf("panic: boom"), first!!.second)
        assertNull(SingBoxCrashReport.unreadLines(working, first.first))
    }

    @Test
    fun signalLineExtractsTheTombstoneSignal() {
        val tombstone = """
            Build fingerprint: 'google/pixel/pixel:14/UP1A/1:user/release-keys'
            pid: 12345, tid: 12399, name: singbox  >>> com.follow.clash:singbox <<<
            signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0000000000000000
                #00 pc 0000000000123456  /data/app/libbox.so
        """.trimIndent()
        assertEquals(
            "signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0000000000000000",
            SingBoxExitInfo.signalLine(tombstone),
        )
    }

    @Test
    fun signalLineCoversBusErrorsAndMissingTraces() {
        assertEquals(
            "signal 7 (SIGBUS), code 2 (BUS_ADRERR), fault addr 0x0000007a1b2c3000",
            SingBoxExitInfo.signalLine(
                "signal 7 (SIGBUS), code 2 (BUS_ADRERR), fault addr 0x0000007a1b2c3000",
            ),
        )
        assertNull(SingBoxExitInfo.signalLine("no signal recorded here"))
        assertNull(SingBoxExitInfo.signalLine(null))
        assertNull(SingBoxExitInfo.signalLine(""))
    }

    @Test
    fun crashReportTailKeepsOnlyTheLastNonBlankLines() {
        val working = folder.newFolder("singbox")
        val body = (1..50).joinToString("\n") { "line $it" } + "\n\n"
        SingBoxCrashReport.fileIn(working).writeText(body)
        val read = SingBoxCrashReport.unreadLines(working, 0L, maxLines = 3)
        assertNotNull(read)
        assertEquals(listOf("line 48", "line 49", "line 50"), read!!.second)
    }
}
