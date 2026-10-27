package com.follow.clash

import com.kfusion.singbox.SingBoxCrashReport
import com.kfusion.singbox.SingBoxExitInfo
import com.kfusion.singbox.SingBoxLog
import com.kfusion.singbox.SingBoxStageMarkers
import java.io.File
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
    fun attemptDeathLineNamesANormalAttempt() {
        val record = SingBoxExitInfo.Record(3, 1_761_000_000_000L, "", 100)
        val line = SingBoxExitInfo.attemptDeathLine(2, -1, "", record)
        assertTrue(line.startsWith("attempt #2 died: LOW_MEMORY(3) at "))
    }

    @Test
    fun attemptDeathLineNamesAStagedLevel() {
        val record = SingBoxExitInfo.Record(5, 1_761_000_000_000L, "crash", 100)
        val line = SingBoxExitInfo.attemptDeathLine(5, 1, "outbounds and dns", record)
        assertTrue(
            line.startsWith(
                "attempt #5 died at L1 (outbounds and dns): CRASH_NATIVE(5) at ",
            ),
        )
        assertTrue(line.endsWith(" - crash"))
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
    fun attemptDeathLineNamesAProbeLevel() {
        val record = SingBoxExitInfo.Record(5, 1_761_000_000_000L, "crash", 100)
        val line = SingBoxExitInfo.attemptDeathLine(9, 5, "cache redirect", record)
        assertTrue(
            line.startsWith("attempt #9 died at L-1 (cache redirect): CRASH_NATIVE(5) at "),
        )
        val nearEmpty = SingBoxExitInfo.attemptDeathLine(10, 6, "near-empty config", record)
        assertTrue(
            nearEmpty.startsWith("attempt #10 died at L-2 (near-empty config): "),
        )
    }

    @Test
    fun firstBacktraceFrameSkipsRegisterDumps() {
        val tombstone = """
            signal 7 (SIGBUS), code 2 (BUS_ADRERR), fault addr 0x0000007a1b2c3000
            r0 0000000000000000 r1 0000000000000000 r2 0000000000000000
                #00 pc 0000000000abcdef  /data/app/libbox.so (runtime.heapBitsSetType+12)
                #01 pc 0000000000123456  /data/app/libbox.so
        """.trimIndent()
        val frame = SingBoxExitInfo.firstBacktraceFrame(tombstone)
        assertEquals(
            "#00 pc 0000000000abcdef  /data/app/libbox.so (runtime.heapBitsSetType+12)",
            frame,
        )
        assertNull(SingBoxExitInfo.firstBacktraceFrame("r0 0000 r1 0000"))
        assertNull(SingBoxExitInfo.firstBacktraceFrame(null))
    }

    @Test
    fun signalClassNotesClassifyTheThreeSignals() {
        assertTrue(
            SingBoxExitInfo.signalClassNote("signal 7 (SIGBUS), code 2")!!
                .startsWith("SIGBUS"),
        )
        assertTrue(
            SingBoxExitInfo.signalClassNote("signal 11 (SIGSEGV), code 1")!!
                .startsWith("SIGSEGV"),
        )
        assertTrue(
            SingBoxExitInfo.signalClassNote("signal 6 (SIGABRT), code 0")!!
                .startsWith("SIGABRT"),
        )
        assertNull(SingBoxExitInfo.signalClassNote("signal 9 (SIGKILL), code 0"))
        assertNull(SingBoxExitInfo.signalClassNote(null))
    }

    @Test
    fun crashHeadlineLeadsWithSignalNoteAndFirstFrame() {
        val tombstone = """
            pid: 12345, tid: 12399, name: singbox  >>> com.follow.clash:singbox <<<
            signal 7 (SIGBUS), code 2 (BUS_ADRERR), fault addr 0x0000007a1b2c3000
            r7 0000007a1b2c3000 r8 0000000000000001
                #00 pc 0000000000abcdef  /data/app/libbox.so
        """.trimIndent()
        val headline = SingBoxExitInfo.crashHeadline(tombstone)!!
        assertTrue(
            headline.startsWith(
                "signal 7 (SIGBUS), code 2 (BUS_ADRERR), fault addr 0x0000007a1b2c3000（SIGBUS",
            ),
        )
        assertTrue(headline.endsWith(" · #00 pc 0000000000abcdef  /data/app/libbox.so"))
        assertTrue(!headline.contains("r7"))
        assertNull(SingBoxExitInfo.crashHeadline("no signal recorded here"))
        assertNull(SingBoxExitInfo.crashHeadline(null))
    }

    @Test
    fun signalLabelsNameTheDecisiveSignalsAndKeepUnknownNumbers() {
        assertEquals("SIGILL(4)", SingBoxExitInfo.signalLabel(4))
        assertEquals("SIGABRT(6)", SingBoxExitInfo.signalLabel(6))
        assertEquals("SIGBUS(7)", SingBoxExitInfo.signalLabel(7))
        assertEquals("SIGKILL(9)", SingBoxExitInfo.signalLabel(9))
        assertEquals("SIGSEGV(11)", SingBoxExitInfo.signalLabel(11))
        assertEquals("signal(17)", SingBoxExitInfo.signalLabel(17))
    }

    @Test
    fun summaryLineNamesTheSignalBehindASignaledDeath() {
        val record = SingBoxExitInfo.Record(2, 1_761_000_000_000L, "", 100, status = 11)
        val line = SingBoxExitInfo.summaryLine(record)
        assertTrue(line.startsWith("process exit: SIGNALED(2) SIGSEGV(11) at "))
    }

    @Test
    fun attemptDeathLineNamesAnExternalKill() {
        val record = SingBoxExitInfo.Record(2, 1_761_000_000_000L, "", 100, status = 9)
        val line = SingBoxExitInfo.attemptDeathLine(7, -1, "", record)
        assertTrue(line.startsWith("attempt #7 died: SIGNALED(2) SIGKILL(9) at "))
    }

    @Test
    fun aRecordWithoutStatusStaysUnnamed() {
        val record = SingBoxExitInfo.Record(2, 1_761_000_000_000L, "", 100)
        val line = SingBoxExitInfo.summaryLine(record)
        assertTrue(line.startsWith("process exit: SIGNALED(2) at "))
    }

    @Test
    fun statusStaysOutOfNonSignaledLines() {
        val record = SingBoxExitInfo.Record(5, 1_761_000_000_000L, "crash", 100, status = 11)
        val line = SingBoxExitInfo.summaryLine(record)
        assertTrue(line.startsWith("process exit: CRASH_NATIVE(5) at "))
        assertTrue(!line.contains("SIGSEGV"))
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

    @Test
    fun crashReportHeadKeepsTheFirstNonBlankLines() {
        val working = folder.newFolder("singbox")
        val body = "\n" + (1..50).joinToString("\n") { "line $it" }
        SingBoxCrashReport.fileIn(working).writeText(body)
        val head = SingBoxCrashReport.headLines(working, maxLines = 3)
        assertEquals(listOf("line 1", "line 2", "line 3"), head)
    }

    @Test
    fun crashReportHeadStopsAtFortyLinesByDefault() {
        val working = folder.newFolder("singbox")
        val body = (1..50).joinToString("\n") { "line $it" }
        SingBoxCrashReport.fileIn(working).writeText(body)
        val head = SingBoxCrashReport.headLines(working)
        assertNotNull(head)
        assertEquals(40, head!!.size)
        assertEquals("line 1", head.first())
        assertEquals("line 40", head.last())
    }

    @Test
    fun crashReportHeadReadsTheNewestReportFile() {
        val working = folder.newFolder("singbox")
        val older = SingBoxCrashReport.fileIn(working)
        older.writeText("fatal error: older\n")
        val newer = File(working, "CrashReport-Application.log")
        newer.writeText("fatal error: newer\n")
        assertTrue(newer.setLastModified(older.lastModified() + 60_000L))
        assertEquals(newer, SingBoxCrashReport.latestFileIn(working))
        assertEquals(listOf("fatal error: newer"), SingBoxCrashReport.headLines(working))
    }

    @Test
    fun crashReportHeadIsNullWithoutAReport() {
        val working = folder.newFolder("singbox")
        assertNull(SingBoxCrashReport.latestFileIn(working))
        assertNull(SingBoxCrashReport.headLines(working))
    }

    @Test
    fun crashReasonLineTakesTheFirstNonBlankLine() {
        val working = folder.newFolder("singbox")
        val body = "\n\nfatal error: all goroutines are asleep - deadlock!\nstack line\n"
        SingBoxCrashReport.fileIn(working).writeText(body)
        assertEquals(
            "crash reason: fatal error: all goroutines are asleep - deadlock!",
            SingBoxCrashReport.reasonLine(working),
        )
    }

    @Test
    fun crashReasonLineTruncatesAtThreeHundredChars() {
        val working = folder.newFolder("singbox")
        SingBoxCrashReport.fileIn(working).writeText("x".repeat(400) + "\n")
        assertEquals(
            "crash reason: " + "x".repeat(300),
            SingBoxCrashReport.reasonLine(working),
        )
    }

    @Test
    fun crashReasonLineIsUnreadableWithoutAUsableReport() {
        val missing = folder.newFolder("missing")
        assertEquals("crash reason: report unreadable", SingBoxCrashReport.reasonLine(missing))
        val blank = folder.newFolder("blank")
        SingBoxCrashReport.fileIn(blank).writeText("\n\n")
        assertEquals("crash reason: report unreadable", SingBoxCrashReport.reasonLine(blank))
    }

    @Test
    fun stageMarkersTailKeepsTheLastNonBlankLines() {
        val working = folder.newFolder("singbox")
        val body = "\n" + (1..10).joinToString("\n") { "mark $it" } + "\n"
        SingBoxStageMarkers.fileIn(working).writeText(body)
        val tail = SingBoxStageMarkers.tailLines(working, maxLines = 3)
        assertEquals(listOf("mark 8", "mark 9", "mark 10"), tail)
    }

    @Test
    fun stageMarkersTailStopsAtThirtyLinesByDefault() {
        val working = folder.newFolder("singbox")
        val body = (1..45).joinToString("\n") { "mark $it" }
        SingBoxStageMarkers.fileIn(working).writeText(body)
        val tail = SingBoxStageMarkers.tailLines(working)
        assertNotNull(tail)
        assertEquals(30, tail!!.size)
        assertEquals("mark 16", tail.first())
        assertEquals("mark 45", tail.last())
    }

    @Test
    fun stageMarkersTailIsNullWithoutAMarkerFile() {
        val working = folder.newFolder("singbox")
        assertNull(SingBoxStageMarkers.tailLines(working))
    }

    @Test
    fun recordLineNamesANonNativeDeathCategory() {
        val record = SingBoxExitInfo.Record(2, 1_761_000_000_000L, "", 100, status = 9)
        val line = SingBoxExitInfo.recordLine(record)
        assertTrue(line.startsWith("exit record: SIGNALED(2) SIGKILL(9) at "))
    }

    @Test
    fun recordLineIsAnExplicitAbsenceWithoutARecord() {
        assertEquals("exit record: not published yet", SingBoxExitInfo.recordLine(null))
    }

    @Test
    fun stageMarkTailLineTakesTheLastMarkForAnyDeath() {
        val working = folder.newFolder("singbox")
        val body = (1..5).joinToString("\n") { "mark $it" }
        SingBoxStageMarkers.fileIn(working).writeText(body)
        assertEquals("stage mark: mark 5", SingBoxStageMarkers.tailLineInWindow(working, 0L))
    }

    @Test
    fun stageMarkTailLineIsAnExplicitAbsenceWithoutMarks() {
        val working = folder.newFolder("singbox")
        assertEquals("stage mark: no marks recorded", SingBoxStageMarkers.tailLineInWindow(working, 0L))
        SingBoxStageMarkers.fileIn(working).writeText("\n\n")
        assertEquals("stage mark: no marks this attempt", SingBoxStageMarkers.tailLineInWindow(working, 0L))
    }

    @Test
    fun stageMarkWindowStartsAfterTheLastAttemptBegin() {
        val working = folder.newFolder("singbox")
        val body =
            listOf(
                "daemon.new-instance.begin +1ms",
                "old attempt mark +2s",
                "daemon.new-instance.begin +3ms",
                "this attempt mark +4s",
            ).joinToString("\n")
        SingBoxStageMarkers.fileIn(working).writeText(body)
        assertEquals(
            "stage mark: this attempt mark +4s",
            SingBoxStageMarkers.tailLineInWindow(working, 0L),
        )
        assertEquals(
            listOf("this attempt mark +4s"),
            SingBoxStageMarkers.tailLinesInWindow(working, 0L),
        )
    }

    @Test
    fun stageMarkWindowIsEmptyWhenTheAttemptMarkedNothingYet() {
        val working = folder.newFolder("singbox")
        val body =
            listOf(
                "daemon.new-instance.begin +1ms",
                "old attempt mark +2s",
                "daemon.new-instance.begin +3ms",
            ).joinToString("\n")
        SingBoxStageMarkers.fileIn(working).writeText(body)
        assertEquals(
            "stage mark: no marks this attempt",
            SingBoxStageMarkers.tailLineInWindow(working, 0L),
        )
    }

    @Test
    fun stageMarkWindowRejectsAFileOlderThanTheAttempt() {
        val working = folder.newFolder("singbox")
        val file = SingBoxStageMarkers.fileIn(working)
        file.writeText("daemon.new-instance.begin +1ms\nmark +2s")
        assertTrue(file.setLastModified(1_000L))
        assertEquals(
            "stage mark: no marks this attempt",
            SingBoxStageMarkers.tailLineInWindow(working, 2_000L),
        )
    }

    @Test
    fun freshCrashReasonQuotesAReportInsideTheWindow() {
        val working = folder.newFolder("singbox")
        val report = SingBoxCrashReport.fileIn(working)
        report.writeText("panic: fresh boom\n")
        assertTrue(report.setLastModified(2_000L))
        assertEquals(
            "crash reason: panic: fresh boom",
            SingBoxCrashReport.freshReasonLine(working, 1_000L),
        )
    }

    @Test
    fun freshCrashReasonRefusesAStaleReportAndAMissingOne() {
        val working = folder.newFolder("singbox")
        val report = SingBoxCrashReport.fileIn(working)
        report.writeText("panic: older boom\n")
        assertTrue(report.setLastModified(1_000L))
        assertEquals(
            "crash reason: no fresh report",
            SingBoxCrashReport.freshReasonLine(working, 2_000L),
        )
        val empty = folder.newFolder("empty")
        assertEquals(
            "crash reason: no fresh report",
            SingBoxCrashReport.freshReasonLine(empty, 0L),
        )
    }

    @Test
    fun daemonErrorLineTakesTheLastErrorOrFatalLine() {
        val lines = listOf(
            "18:22:10.000 sing-box: [37mDEBUG[0m[0000] dns: lookup domain",
            "18:22:11.000 sing-box: [31mERROR[0m[0001] start router: boom",
            "18:22:12.000 sing-box: [33mWARN[0m[0002] router: slow",
            "18:22:13.000 sing-box: [31mFATAL[0m[0003] later failure",
        )
        assertEquals(
            "daemon error: sing-box: [31mFATAL[0m[0003] later failure",
            SingBoxLog.lastErrorLineIn(lines),
        )
    }

    @Test
    fun daemonErrorLineIsAbsentWithoutAnErrorLine() {
        val lines = listOf(
            "18:22:10.000 start: begin",
            "18:22:11.000 sing-box: [33mWARN[0m[0000] router: slow",
        )
        assertNull(SingBoxLog.lastErrorLineIn(lines))
        assertNull(SingBoxLog.lastErrorLineIn(emptyList()))
    }
}
