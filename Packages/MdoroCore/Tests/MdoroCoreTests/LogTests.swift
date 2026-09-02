import Testing
import Foundation
@testable import MdoroCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()

private func at(_ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: hour, minute: minute))!
}

private let logicalDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!

// REQ-ERR-010 / Decision 0034: these tests care that a write failed, not what refused it.
// What the payload now guarantees is asserted in ErrorReportingTests.
private let writeRefused = LogWriteError.writeFailed(
    ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
)

private func entry(
    type: SessionType = .work,
    start: Date = at(9, 0),
    end: Date = at(9, 25),
    elapsed: Int = 25 * 60,
    outcome: LogOutcome = .completed,
    preset: String = "Standard",
    edited: Bool = false,
    task: String? = "仕様書のレビュー",
    extended: Int = 0,
    loopAfter: Int? = 1,
    interval: Int = 4
) -> LogEntry {
    LogEntry(
        sessionType: type, startedAt: start, endedAt: end, elapsedSeconds: elapsed,
        outcome: outcome, presetName: preset, presetEditedDuringSession: edited,
        taskSnapshot: task, extendedSeconds: extended,
        loopCountAfterCompletion: loopAfter, longBreakInterval: interval, logicalDate: logicalDay
    )
}

@Suite("Log line formatting (REQ-LOG-010–017)")
struct LogFormatterTests {

    // Reproduce the example output of 7.2 exactly.
    @Test func matchesTheExamplesInSection72() {
        #expect(LogFormatter.line(for: entry(), calendar: calendar)
                == "- 09:00–09:25 WORK 25m ✅ Loop 1/4 [Standard] — 仕様書のレビュー")

        #expect(LogFormatter.line(for: entry(
            type: .shortBreak, start: at(9, 25), end: at(9, 30), elapsed: 5 * 60,
            task: nil, loopAfter: nil), calendar: calendar)
                == "- 09:25–09:30 SHORT_BREAK 5m ✅ [Standard]")

        #expect(LogFormatter.line(for: entry(
            start: at(9, 32), end: at(10, 4), elapsed: 32 * 60,
            task: "プロトコル設計", extended: 7 * 60, loopAfter: 2), calendar: calendar)
                == "- 09:32–10:04 WORK 32m ✅ Loop 2/4 (+7m extended) [Standard] — プロトコル設計")

        #expect(LogFormatter.line(for: entry(
            type: .shortBreak, start: at(10, 4), end: at(10, 9), elapsed: 5 * 60,
            outcome: .skipped, task: nil, loopAfter: nil), calendar: calendar)
                == "- 10:04–10:09 SHORT_BREAK 5m ⏭ Skipped [Standard]")

        #expect(LogFormatter.line(for: entry(
            start: at(11, 35), end: at(11, 43), elapsed: 8 * 60, outcome: .aborted,
            preset: "ディープワーク", task: "プロトコル設計", loopAfter: nil), calendar: calendar)
                == "- 11:35–11:43 WORK 8m ⏹ Stopped [ディープワーク] — プロトコル設計")
    }

    // REQ-LOG-011: the loop uses the same modulo form as REQ-TIM-025, matching what the UI shows.
    @Test func loopCountUsesTheSameModuloAsTheUI() {
        #expect(LogFormatter.line(for: entry(loopAfter: 4), calendar: calendar).contains("Loop 4/4"))
        #expect(LogFormatter.line(for: entry(loopAfter: 5), calendar: calendar).contains("Loop 1/4"))
        #expect(LogFormatter.line(for: entry(loopAfter: 8), calendar: calendar).contains("Loop 4/4"))
    }

    // The loop belongs to a **normally completed WORK line** only.
    // REQ-LOG-011 states nothing but the **positive MUST**: "include it on a completed WORK line".
    // "It must not appear on any other line" rests on the two below rather than on the article,
    // so both are written down here.
    //   - Aborted and skipped: §4.5, the definition of the actions (neither adds to the loop count)
    //   - Break lines and Stopped lines: §7.2, the example output (no Loop on SHORT_BREAK /
    //     LONG_BREAK / ⏹ Stopped)
    //
    // The word emitted is `Loop n/m`. A completed line carrying the same `loopCountAfterCompletion`
    // is checked first as a control, so that the negatives below show the loop is suppressed even
    // though every condition for emitting it is met.
    @Test func loopCountIsOmittedForBreaksAndAbnormalEndings() {
        #expect(LogFormatter.line(for: entry(), calendar: calendar).contains("Loop 1/4"),
                "control: the same input on a completed WORK line does carry the loop")

        #expect(!LogFormatter.line(for: entry(outcome: .aborted), calendar: calendar).contains("Loop"))
        #expect(!LogFormatter.line(for: entry(outcome: .skipped), calendar: calendar).contains("Loop"))
        // Look at both kinds of break. With longBreak alone, an implementation written as
        // `sessionType != .longBreak` slips through.
        #expect(!LogFormatter.line(for: entry(type: .shortBreak, task: nil), calendar: calendar).contains("Loop"))
        #expect(!LogFormatter.line(for: entry(type: .longBreak, task: nil), calendar: calendar).contains("Loop"))
    }

    // REQ-LOG-016: when group A is edited during a session, mark the preset name with a *.
    @Test func editedPresetIsMarkedWithAnAsterisk() {
        #expect(LogFormatter.line(for: entry(edited: true), calendar: calendar).contains("[Standard*]"))
        #expect(!LogFormatter.line(for: entry(edited: false), calendar: calendar).contains("*"))
    }

    // REQ-LOG-010 / 023: the task name is for WORK only.
    @Test func taskNameOnlyAppearsForWork() {
        #expect(!LogFormatter.line(for: entry(type: .shortBreak, task: "残っていたら異常", loopAfter: nil), calendar: calendar).contains("残っていたら異常"))
    }

    // REQ-LOG-013: plain text that is not a link by default. A setting can make it a link.
    @Test func taskNameIsPlainByDefaultAndLinkableByOption() {
        let plain = LogFormatter.line(for: entry(task: "プロトコル設計"), calendar: calendar)
        #expect(plain.hasSuffix("— プロトコル設計"))
        #expect(!plain.contains("[["))

        let linked = LogFormatter.line(for: entry(task: "プロトコル設計"), options: .init(taskAsLink: true), calendar: calendar)
        #expect(linked.hasSuffix("— [[プロトコル設計]]"))
    }

    // Even when [[...]] is left in the text, the default does not turn it into a link.
    @Test func bracketsInTheTaskNameDoNotBecomeALink() {
        let line = LogFormatter.line(for: entry(task: "[[設計ノート]]"), calendar: calendar)
        #expect(!line.contains("[["))
    }

    // REQ-LOG-017: the logical day comes from sessionStartedAt. A session that crosses the
    // boundary goes under the heading of the day it started.
    @Test func logicalDayComesFromTheSessionStart() {
        let startHour = 4
        // Starting at 03:50 → the logical day is the previous one (short of the 04:00 boundary).
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 3, minute: 50))!
        let crossed = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 4, minute: 15))!
        let day = LogicalDay.date(for: lateNight, dayStartHour: startHour, calendar: calendar)

        let crossing = LogEntry(
            sessionType: .work, startedAt: lateNight, endedAt: crossed, elapsedSeconds: 25 * 60,
            outcome: .completed, presetName: "Standard", presetEditedDuringSession: false,
            taskSnapshot: nil, extendedSeconds: 0, loopCountAfterCompletion: 1,
            longBreakInterval: 4, logicalDate: day
        )
        #expect(LogFormatter.dayHeading(for: crossing.logicalDate, calendar: calendar) == "## 2026-08-24 (Mon)",
                "a session ending the next day belongs under the heading of the day it started")
        #expect(LogFormatter.line(for: crossing, calendar: calendar).hasPrefix("- 03:50–04:15"))
    }

    // REQ-LOG-003: `## YYYY-MM-DD (weekday)`
    @Test func dayHeadingFormat() {
        #expect(LogFormatter.dayHeading(for: logicalDay, calendar: calendar) == "## 2026-08-24 (Mon)")
    }
}

@Suite("Inserting into the log file (REQ-LOG-001 / 003 / 022)")
struct LogFileEditorTests {

    private func insert(into existing: String, _ line: String = "- 新しい行") throws -> String {
        try LogFileEditor.inserting(
            line: line,
            underHeading: LogFormatter.dayHeading(for: logicalDay, calendar: calendar),
            logicalDate: logicalDay, into: existing, calendar: calendar
        ).contents
    }

    // POL-087: the file the app creates for itself ends with a newline. Nothing of the user's is
    // being preserved here, and a Markdown file ending mid-line makes the next write share that line.
    @Test func emptyFileGetsHeadingAndLine() throws {
        let result = try insert(into: "")
        #expect(result == "## 2026-08-24 (Mon)\n\n- 新しい行\n")
    }

    // REQ-LOG-003: when the heading already exists, append to the end of that day's section.
    @Test func appendsToTheEndOfTheMatchingDaySection() throws {
        let existing = """
        ## 2026-08-23 (Sun)

        - 前日の行

        ## 2026-08-24 (Mon)

        - 既存の行1
        - 既存の行2

        ## 2026-08-25 (Tue)

        - 翌日の行

        """
        let result = try insert(into: existing)
        let lines = result.components(separatedBy: "\n")
        let index = lines.firstIndex(of: "- 新しい行")!
        #expect(lines[index - 1] == "- 既存の行2")
        #expect(lines[index + 1] == "")
        #expect(lines[index + 2] == "## 2026-08-25 (Tue)", "the new line must land before the next day's section")
    }

    // **Never change a single existing line.** This is the first principle.
    @Test func neverModifiesOrDropsExistingLines() throws {
        let existing = """
        # 実績ログ

        ユーザーが自分で書いたメモ。

        ## 2026-08-24 (Mon)

        - 既存の行
          - 手で足した子行

        ## 2026-08-25 (Tue)

        - 翌日の行
        """
        let result = try insert(into: existing)
        for line in existing.components(separatedBy: "\n") where !line.isEmpty {
            #expect(result.contains(line), "an existing line was lost: \(line)")
        }
        let before = existing.components(separatedBy: "\n").filter { !$0.isEmpty }
        let after = result.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != "- 新しい行" }
        #expect(before == after, "the order and content of existing lines must be preserved")
    }

    // REQ-LOG-022: when the heading has been deleted or renamed outside the app, recreate it and
    // append at the end of the file. Never try to restore or correct the existing lines.
    // POL-087: the file ends with a newline, so the result does too. A file that ends without one is
    // the subject of `aFileWithoutATrailingNewlineDoesNotGainOne`; this one is about the heading.
    @Test func missingHeadingIsRecreatedAtTheEndOfFile() throws {
        let existing = "## 2026-08-23 (Sun)\n\n- 前日の行\n"
        let result = try insert(into: existing)
        #expect(result.hasSuffix("## 2026-08-24 (Mon)\n\n- 新しい行\n"))
        #expect(result.contains("- 前日の行"))
    }

    // Decision 0014: even when the weekday has been rewritten, a readable date means the same day.
    // **Users edit their own logs.** Never split the record by making a second heading.
    @Test func renamedHeadingIsMatchedByItsDate() throws {
        let existing = "## 2026-08-24 (Monday)\n\n- 既存の行\n"
        let result = try insert(into: existing)
        #expect(result.components(separatedBy: "## ").count == 2, "must not create a second heading for the same day")
        #expect(result.contains("## 2026-08-24 (Monday)"), "must not rewrite the existing heading")
    }

    // REQ-LOG-003 / REQ-LOG-022: a heading the user wrote is not taken as the day's heading, even
    // when it contains the date.
    @Test func userHeadingContainingADateIsNotTreatedAsTheDaySection() throws {
        let existing = "## 週次レビュー 2026-08-24 の分\n\n- ユーザーのメモ\n"
        let result = try insert(into: existing)
        #expect(result.contains("## 2026-08-24 (Mon)"), "must create a new date heading")
        let lines = result.components(separatedBy: "\n")
        let memo = lines.firstIndex(of: "- ユーザーのメモ")!
        let inserted = lines.firstIndex(of: "- 新しい行")!
        #expect(inserted > memo + 1, "must not insert into a section the user wrote")
    }

    // An insertion that would lose even one existing line is stopped before the write. The last
    // line of defence for the first principle.
    @Test func theGuardRejectsAnInsertionThatWouldLoseLines() {
        #expect(!LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新", "c"], insertedAt: 1, count: 1),
                "a rewritten existing line must not pass the guard")
        #expect(!LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新"], insertedAt: 1, count: 1),
                "a mismatched line count must not pass the guard")
        #expect(LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新", "b"], insertedAt: 1, count: 1))
    }

    // Inserting into a CRLF file must not mix line endings.
    @Test func crlfFilesKeepTheirLineEndings() throws {
        let existing = "## 2026-08-24 (Mon)\r\n\r\n- 既存の行\r\n"
        let result = try insert(into: existing)
        #expect(!result.contains("- 既存の行\r\n- 新しい行\n"), "the inserted line must not use LF in a CRLF file")
        #expect(result == "## 2026-08-24 (Mon)\r\n\r\n- 既存の行\r\n- 新しい行\r\n")
    }

    @Test func sectionAtEndOfFileGetsTheLineAppended() throws {
        let existing = "## 2026-08-24 (Mon)\n\n- 既存の行\n"
        let result = try insert(into: existing)
        #expect(result == "## 2026-08-24 (Mon)\n\n- 既存の行\n- 新しい行\n")
    }

    // POL-087 / REQ-LOG-001: **a file that did not end with a newline must not come back with one.**
    // Plenty of editors leave a Markdown file without a final newline, and appending is all this is
    // allowed to do to the user's file — the last line is one of theirs, and a byte was being added
    // to it. Both branches are read: the day's heading found, and the heading recreated.
    @Test func aFileWithoutATrailingNewlineDoesNotGainOne() throws {
        #expect(
            try insert(into: "## 2026-08-24 (Mon)\n\n- 既存の行")
                == "## 2026-08-24 (Mon)\n\n- 既存の行\n- 新しい行"
        )
        #expect(
            try insert(into: "## 2026-08-23 (Sun)\n\n- 前日の行")
                == "## 2026-08-23 (Sun)\n\n- 前日の行\n\n## 2026-08-24 (Mon)\n\n- 新しい行"
        )
        // The same for CRLF, where the byte that would have been added is two.
        #expect(
            try insert(into: "## 2026-08-24 (Mon)\r\n\r\n- 既存の行")
                == "## 2026-08-24 (Mon)\r\n\r\n- 既存の行\r\n- 新しい行"
        )
    }

    // POL-087: **the guard is not what keeps the ending.** `preservesAllLines` compares arrays of
    // lines, and the two files below reduce to the same array — it returns the same verdict for
    // both and never looks at the final byte. It passed all the while one was being added, which
    // is why the test above reads the whole string instead of asking the guard.
    @Test func theGuardCannotSeeATrailingNewline() throws {
        let withoutNewline = "## 2026-08-24 (Mon)\n\n- 既存の行"
        let inserted = try LogFileEditor.inserting(
            line: "- 新しい行",
            underHeading: LogFormatter.dayHeading(for: logicalDay, calendar: calendar),
            logicalDate: logicalDay, into: withoutNewline, calendar: calendar
        )
        let insertedIntoTheSameFileWithOne = try LogFileEditor.inserting(
            line: "- 新しい行",
            underHeading: LogFormatter.dayHeading(for: logicalDay, calendar: calendar),
            logicalDate: logicalDay, into: withoutNewline + "\n", calendar: calendar
        )
        #expect(inserted.insertedLines == insertedIntoTheSameFileWithOne.insertedLines,
                "the two files differ by one byte, and it is not one the insertion knows about")
        #expect(inserted.contents + "\n" == insertedIntoTheSameFileWithOne.contents,
                "the ending is the only difference between the two results")

        // And this is the array the guard is handed for both of them. It accepts the insertion, as
        // it always did — so passing it says nothing about how the file ends.
        let heldLines = ["## 2026-08-24 (Mon)", "", "- 既存の行"]
        #expect(LogFileEditor.preservesAllLines(
            original: heldLines, updated: heldLines + ["- 新しい行"], insertedAt: 3, count: 1))
    }
}

@Suite("Writing the log file (REQ-LOG-002 / 004 / 005 / 021)")
struct LogWriterTests {

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroLogTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func createsTheFileWhenAbsentAndAppendsAcrossCalls() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("PomodoroLog.md")
        let writer = LogWriter(fileURL: url)

        try writer.append(entry(), calendar: calendar)
        try writer.append(entry(type: .shortBreak, start: at(9, 25), end: at(9, 30),
                                elapsed: 5 * 60, task: nil, loopAfter: nil), calendar: calendar)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents == """
        ## 2026-08-24 (Mon)

        - 09:00–09:25 WORK 25m ✅ Loop 1/4 [Standard] — 仕様書のレビュー
        - 09:25–09:30 SHORT_BREAK 5m ✅ [Standard]

        """)
    }

    // REQ-LOG-004: re-read before writing, take in the external changes, then append.
    @Test func externalEditsMadeBetweenWritesAreKept() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("PomodoroLog.md")
        let writer = LogWriter(fileURL: url)

        try writer.append(entry(), calendar: calendar)
        var edited = try String(contentsOf: url, encoding: .utf8)
        edited += "\n- ユーザーが手で書いた行\n"
        try edited.write(to: url, atomically: true, encoding: .utf8)

        try writer.append(entry(start: at(10, 0), end: at(10, 25), loopAfter: 2), calendar: calendar)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("- ユーザーが手で書いた行"), "a line added outside the app must not be lost")
        #expect(contents.contains("Loop 2/4"))
    }

    // REQ-LOG-002: an error when the destination directory does not exist.
    @Test func missingDirectoryIsRejected() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/PomodoroLog.md")
        #expect(throws: LogWriteError.invalidFilePath) {
            try LogWriter(fileURL: url).append(entry(), calendar: calendar)
        }
    }

    // REQ-LOG-021 / the first of the three inviolable rules: the same path as Task.md can never
    // be chosen.
    @Test func theTaskFileCanNeverBeTheLogFile() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = directory.appendingPathComponent("Task.md")
        #expect(throws: LogWriteError.invalidFilePath) {
            try LogWriter.validate(logFileURL: task, taskFileURL: task)
        }
        #expect(throws: Never.self) {
            try LogWriter.validate(logFileURL: directory.appendingPathComponent("PomodoroLog.md"), taskFileURL: task)
        }
    }
}

@Suite("Retrying a failed write (REQ-LOG-005 / REQ-ERR-004)")
struct LogWriteQueueTests {

    // One flush that writes a single entry, or refuses it. An entry has to be queued for a flush to
    // fail at all: with nothing to write, there is nothing to refuse.
    @discardableResult
    private func flushOne(_ queue: LogWriteQueue, failing: Bool) -> LogWriteQueue.FlushResult {
        queue.enqueue(entry(), to: .configured)
        return queue.flush { _ in if failing { throw writeRefused } }
    }

    @Test func failuresKeepEntriesQueuedAndNotifyOnTheThirdAttempt() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(), to: .configured)
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)), to: .configured)

        var result = queue.flush { _ in throw writeRefused }
        #expect(result.written == 0)
        #expect(result.pending == 2, "entries that failed to write stay queued")
        #expect(!result.shouldNotify)

        result = queue.flush { _ in throw writeRefused }
        #expect(result.consecutiveFailures == 2)
        #expect(!result.shouldNotify)

        result = queue.flush { _ in throw writeRefused }
        #expect(result.consecutiveFailures == LogWriteQueue.failureThreshold)
        #expect(result.shouldNotify, "REQ-ERR-004: notify on the third consecutive failure")

        result = queue.flush { _ in throw writeRefused }
        #expect(!result.shouldNotify, "must not keep notifying about the same ongoing failure")
    }

    @Test func successDrainsTheQueueInOrderAndResetsTheCounter() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)), to: .configured)
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)), to: .configured)
        _ = queue.flush { _ in throw writeRefused }

        var written: [Date] = []
        let result = queue.flush { written.append($0.startedAt) }
        #expect(result.written == 2)
        #expect(result.pending == 0)
        #expect(result.consecutiveFailures == 0)
        #expect(written == [at(9, 0), at(10, 0)], "the log is a time series, so write order must be preserved")
    }

    @Test func aFailureMidwayStopsAndKeepsTheRest() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)), to: .configured)
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)), to: .configured)

        var attempts = 0
        let result = queue.flush { _ in
            attempts += 1
            if attempts == 2 { throw writeRefused }
        }
        #expect(result.written == 1)
        #expect(result.pending == 1)
    }

    // REQ-ERR-004 / Decision 0039: the failure that comes and goes is the one worth hearing about.
    // A run of three would never be reached here, and the old rule stayed silent forever.
    @Test func failuresThatComeAndGoStillReachTheThreshold() {
        let queue = LogWriteQueue()

        flushOne(queue, failing: true)
        flushOne(queue, failing: false)
        let second = flushOne(queue, failing: true)
        #expect(!second.shouldNotify, "two failures out of ten are not enough")
        flushOne(queue, failing: false)
        let third = flushOne(queue, failing: true)

        #expect(third.recentFailures == LogWriteQueue.failureThreshold)
        #expect(third.consecutiveFailures == 1, "no run of failures was ever built up")
        #expect(third.shouldNotify, "REQ-ERR-004: three of the last ten flushes failed")
    }

    // Decision 0039: counting is bounded, so a failure from long ago cannot push a later one over
    // the threshold. Counting cumulatively would report the state of months ago as the state now.
    @Test func failuresThatLeftTheWindowNoLongerCount() {
        let queue = LogWriteQueue()

        flushOne(queue, failing: true)
        flushOne(queue, failing: true)
        for _ in 0 ..< LogWriteQueue.recentWindow {
            flushOne(queue, failing: false)
        }

        flushOne(queue, failing: true)
        let result = flushOne(queue, failing: true)
        #expect(result.recentFailures == 2, "the two earlier failures have fallen out of the window")
        #expect(!result.shouldNotify)
    }

    // Decision 0039: the window is ten flushes wide. The counts here are written out rather than
    // read from `recentWindow`, because a test that asks the constant how wide it is can only show
    // that a window exists — not that it is ten.
    @Test func theWindowIsTenFlushesWide() {
        let justOutside = LogWriteQueue()
        flushOne(justOutside, failing: true)
        for _ in 0 ..< 8 { flushOne(justOutside, failing: false) }
        flushOne(justOutside, failing: true)
        let eleventhFlush = flushOne(justOutside, failing: true)
        #expect(eleventhFlush.recentFailures == 2, "the first failure is eleven flushes back and has left the window")
        #expect(!eleventhFlush.shouldNotify)

        let justInside = LogWriteQueue()
        flushOne(justInside, failing: true)
        for _ in 0 ..< 7 { flushOne(justInside, failing: false) }
        flushOne(justInside, failing: true)
        let tenthFlush = flushOne(justInside, failing: true)
        #expect(tenthFlush.recentFailures == 3, "the first failure is ten flushes back and still counts")
        #expect(tenthFlush.consecutiveFailures == 2, "so the notification cannot be coming from a run of three")
        #expect(tenthFlush.shouldNotify, "REQ-ERR-004: three of the last ten flushes failed")
    }

    // Decision 0039: a flush with nothing queued attempted no write and is no evidence either way.
    // Counting it as a success would let idle flushes wash real failures out of the window — and
    // `flush` is public, so the queue cannot lean on its callers to never ask.
    @Test func aFlushThatWroteNothingDoesNotFillTheWindow() {
        let queue = LogWriteQueue()

        flushOne(queue, failing: true)
        flushOne(queue, failing: false)
        flushOne(queue, failing: true)
        flushOne(queue, failing: false)

        // The queue is empty now, so these attempt nothing at all.
        var idle = queue.flush { _ in }
        for _ in 0 ..< 7 { idle = queue.flush { _ in } }
        #expect(idle.written == 0)
        #expect(idle.recentFailures == 2, "eight idle flushes did not push the two failures out")
        #expect(idle.consecutiveFailures == 0, "the run counter still resets, as it did before the window existed")

        let result = flushOne(queue, failing: true)
        #expect(result.recentFailures == 3)
        #expect(result.shouldNotify, "REQ-ERR-004: the third real failure is still the third one")
    }

    // The user is told once while the same trouble stands (existing behaviour), and a single
    // success is not enough to make the same trouble worth reporting twice.
    @Test func successesArmTheNotificationAgainOnceTheWindowIsClear() {
        let queue = LogWriteQueue()

        flushOne(queue, failing: true)
        flushOne(queue, failing: false)
        flushOne(queue, failing: true)
        flushOne(queue, failing: false)
        #expect(flushOne(queue, failing: true).shouldNotify)

        let afterOneSuccess = flushOne(queue, failing: false)
        #expect(afterOneSuccess.recentFailures == LogWriteQueue.failureThreshold)
        #expect(!afterOneSuccess.shouldNotify, "the same trouble is not reported twice")

        for _ in 0 ..< LogWriteQueue.recentWindow {
            flushOne(queue, failing: false)
        }
        flushOne(queue, failing: true)
        flushOne(queue, failing: true)
        let again = flushOne(queue, failing: true)
        #expect(again.shouldNotify, "REQ-ERR-004: trouble that starts again after it cleared is reported again")
    }

    // REQ-ERR-004 / Decision 0039: the attempts that never reached the writing at all. Getting to
    // the file can fail first — on macOS, resolving the bookmark for the log folder — and nothing
    // of that path goes through `flush`. Counted nowhere, a folder that had gone away showed on the
    // screen and never notified, however long it stayed away.
    @Test func attemptsThatNeverReachedTheWritingStillReachTheThreshold() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(), to: .configured)

        #expect(!queue.recordFailedAttempt().shouldNotify)
        #expect(!queue.recordFailedAttempt().shouldNotify)
        let third = queue.recordFailedAttempt()

        #expect(third.consecutiveFailures == LogWriteQueue.failureThreshold)
        #expect(third.recentFailures == LogWriteQueue.failureThreshold)
        #expect(third.shouldNotify, "REQ-ERR-004: three failed attempts in a row")
        #expect(!queue.recordFailedAttempt().shouldNotify, "and the same trouble is told once")
    }

    // REQ-LOG-005: the entries are still owed to the file. Nothing was written, so nothing may be
    // dropped — this path holds sessions whose `committedAt` is already set (REQ-LOG-019).
    @Test func anAttemptThatNeverReachedTheWritingKeepsEveryEntry() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)), to: .configured)
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)), to: .configured)

        let result = queue.recordFailedAttempt()
        #expect(result.written == 0)
        #expect(result.pending == 2)
        #expect(queue.pendingEntries.map(\.startedAt) == [at(9, 0), at(10, 0)])
        #expect(result.lastError == nil, "the failure did not come from LogWriter; the caller holds it")
    }

    // Decision 0039: one window, one run counter. The two entrances are the same event seen at
    // different depths, so a failure counted by one has to be visible to the other — otherwise the
    // threshold could be approached twice over and reached by neither.
    @Test func failuresFromBothEntrancesShareTheWindowAndTheRun() {
        let runOfThree = LogWriteQueue()
        flushOne(runOfThree, failing: true)
        runOfThree.recordFailedAttempt()
        let mixedThird = flushOne(runOfThree, failing: true)
        #expect(mixedThird.consecutiveFailures == LogWriteQueue.failureThreshold)
        #expect(mixedThird.shouldNotify, "REQ-ERR-004: three in a row, whichever entrance they came through")

        let comingAndGoing = LogWriteQueue()
        comingAndGoing.enqueue(entry(), to: .configured)
        comingAndGoing.recordFailedAttempt()
        flushOne(comingAndGoing, failing: false)
        comingAndGoing.enqueue(entry(), to: .configured)
        comingAndGoing.recordFailedAttempt()
        flushOne(comingAndGoing, failing: false)
        comingAndGoing.enqueue(entry(), to: .configured)
        let third = comingAndGoing.recordFailedAttempt()
        #expect(third.consecutiveFailures == 1, "no run was ever built up")
        #expect(third.recentFailures == LogWriteQueue.failureThreshold)
        #expect(third.shouldNotify, "REQ-ERR-004: three of the last ten attempts, counted as one window")
    }

    // Decision 0039, the same reading `flush` gives an idle call: with nothing owed to the file,
    // nothing was attempted. `flush` cannot lean on its callers to never ask, and neither can this.
    @Test func anAttemptWithNothingQueuedIsNoEvidenceEitherWay() {
        let queue = LogWriteQueue()

        flushOne(queue, failing: true)
        flushOne(queue, failing: false)
        flushOne(queue, failing: true)
        flushOne(queue, failing: false)

        // The queue is empty here, so these were owed nothing.
        var idle = queue.recordFailedAttempt()
        for _ in 0 ..< 9 { idle = queue.recordFailedAttempt() }
        #expect(idle.recentFailures == 2, "ten empty attempts did not push the two failures out")
        #expect(idle.consecutiveFailures == 0)
        #expect(!idle.shouldNotify)

        let real = flushOne(queue, failing: true)
        #expect(real.recentFailures == LogWriteQueue.failureThreshold)
        #expect(real.shouldNotify, "REQ-ERR-004: the third real failure is still the third one")
    }
}

// REQ-LOG-002 / Decision 0033. **Every user starts with no folder set**, so this is the state the
// app is in on its first run, not an edge case. The rule is that nothing is written, nothing is
// queued, and none of it is a failure.
@Suite("An unset destination records nothing and fails at nothing (REQ-LOG-002 / Decision 0033)")
struct UnsetLogDestinationTests {

    @Test func anEntryIsRefusedWhileNowhereIsSet() {
        let queue = LogWriteQueue()
        #expect(queue.enqueue(entry(), to: .notSet) == false)
        #expect(queue.pendingCount == 0, "REQ-LOG-002: it may not be queued either")
        #expect(queue.pendingEntries.isEmpty)
    }

    // The other half of the pair. Without it, a guard that refused everything would pass above.
    @Test func anEntryIsTakenOnceSomewhereIsSet() {
        let queue = LogWriteQueue()
        #expect(queue.enqueue(entry(), to: .configured) == true)
        #expect(queue.pendingCount == 1)
    }

    // REQ-ERR-004 / Decision 0033: **the reason the distinction matters.** Read the old way, a new
    // user was notified that writing had failed on their third session — with nothing broken and
    // nothing attempted.
    @Test func sessionsThatWereNeverRecordedNeverReachTheFailureThreshold() {
        let queue = LogWriteQueue()
        var refused = 0

        // More sessions than REQ-ERR-004's threshold, and more flushes than its window.
        for hour in 0 ..< (LogWriteQueue.recentWindow + 2) {
            if !queue.enqueue(entry(start: at(hour, 0), end: at(hour, 25)), to: .notSet) { refused += 1 }
            let result = queue.flush { _ in
                Issue.record("REQ-LOG-002: a write was attempted with nowhere to write to")
            }
            #expect(!result.shouldNotify, "REQ-ERR-004: an unset folder is not a failed write")
            #expect(result.consecutiveFailures == 0)
            #expect(result.recentFailures == 0)
            #expect(result.lastError == nil)
            #expect(result.pending == 0)
        }
        #expect(refused == LogWriteQueue.recentWindow + 2, "the sessions did happen; they were not recorded")
    }

    // Decision 0033: the queue an earlier version left behind. Kept, every one of them would land
    // in the file the moment a folder was chosen — days of sessions the user never asked to write.
    @Test func aQueueLeftOverFromWhenNowhereWasSetIsDropped() {
        let saved = [entry(start: at(9, 0), end: at(9, 25)), entry(start: at(10, 0), end: at(10, 25))]
        let carried = LogDestination.notSet.carryOver(saved)
        #expect(carried.kept.isEmpty)
        #expect(carried.dropped == saved.count, "the count is what the diagnostic log is given")
    }

    // REQ-LOG-005, unchanged: a queue left over from when a folder *was* set holds real write
    // failures, and `committedAt` is already on those sessions. Dropping them loses the record.
    @Test func aQueueLeftOverFromARealFailureIsKept() {
        let saved = [entry(start: at(9, 0), end: at(9, 25)), entry(start: at(10, 0), end: at(10, 25))]
        let carried = LogDestination.configured.carryOver(saved)
        #expect(carried.kept == saved)
        #expect(carried.dropped == 0)
    }

    @Test func theDestinationIsReadFromWhetherAFolderIsSet() {
        #expect(LogDestination(isConfigured: true) == .configured)
        #expect(LogDestination(isConfigured: false) == .notSet)
        #expect(LogDestination.configured.recordsEntries)
        #expect(!LogDestination.notSet.recordsEntries)
    }
}

@Suite("The logged task name is the snapshot from session start (REQ-LOG-023)")
struct LogTaskSnapshotTests {

    private func preset() -> Preset {
        Preset(id: "p", name: "Standard", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
               longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
    }

    // Reselecting during FINISHED / PENDING_DECISION is not reflected in the log line that gets
    // committed. Reflecting it would record a task nobody worked on.
    @Test func changingTheSelectionAfterFinishDoesNotChangeTheLoggedName() throws {
        let p = preset()
        let presets = PresetContext(presets: [p], activePresetId: p.id)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let started = try TimerEngine.reduce(
            action: .startWork(presetId: p.id, taskSnapshot: "開始時に選んでいたタスク"),
            context: .idle(now: start), presets: presets, now: start
        ).get().context
        let endAt = started.sessionEndAt!

        // After reaching FINISHED, select a different task.
        let finished = TimerEngine.tick(context: started, presets: presets, now: endAt).context
        #expect(finished.runState == .finished)
        let reselected = try TimerEngine.reduce(
            action: .selectTask(snapshot: "あとから選んだ別のタスク"),
            context: finished, presets: presets, now: endAt.addingTimeInterval(10)
        ).get().context

        // Let the grace run out so it commits.
        let committed = TimerEngine.tick(context: reselected, presets: presets, now: endAt.addingTimeInterval(120))
        guard case let .commitLog(entry) = committed.effects.first else {
            Issue.record("no commitLog was emitted")
            return
        }
        #expect(entry.taskSnapshot == "開始時に選んでいたタスク")
        #expect(LogFormatter.line(for: entry).hasSuffix("— 開始時に選んでいたタスク"))
    }
}

// POL-120: `LogWriter` reads the file, builds an insertion from what it read, and then replaces
// **the whole file**. Anything saved to it in between was inside what got overwritten — the user's
// save disappeared, silently, and so did everything the app had never read. `preservesAllLines`
// could not see it: it compares two arrays the app is holding, and neither of them is the disk.
//
// Every test here puts a save in exactly that gap. The hook fires after the read and before the
// swap, which is where the window is.
@Suite("A save that lands between the read and the swap (POL-120 / REQ-LOG-004)")
struct LogWriterConcurrentEditTests {

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MdoroLogConflictTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // Someone else's editor saving the file: read what is there, add a line of their own, save.
    // The text differs on every call because writing the same bytes back is not a change.
    private func saveALine(_ nth: Int, into url: URL) {
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (current + "- a line the user typed (\(nth))\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    // **The bug, stated as a test.** Nothing of the user's may be replaced, and the entry may not
    // be written on top of a file it was not built from.
    @Test func aSaveThatLandsInTheWindowIsNeverOverwritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")
        let writer = LogWriter(fileURL: url)
        try writer.append(entry(), calendar: calendar)

        var saves = 0
        #expect(throws: LogWriteError.fileChangedWhileWriting) {
            try writer.append(
                entry(start: at(10, 0), end: at(10, 25), loopAfter: 2),
                calendar: calendar,
                betweenReadAndReplace: {
                    saves += 1
                    saveALine(saves, into: url)
                }
            )
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        for nth in 1...saves {
            #expect(contents.contains("- a line the user typed (\(nth))"), "a save made outside the app was lost")
        }
        #expect(!contents.contains("Loop 2/4"), "the entry was written over a file it was not built from")
        // REQ-LOG-001: the first write is still there too — the whole file is at stake, not one line.
        #expect(contents.contains("Loop 1/4"))
    }

    // POL-120: rereading is the answer, so it has to stop somewhere.
    @Test func rereadingStopsAtTheAttemptLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")
        let writer = LogWriter(fileURL: url)
        try writer.append(entry(), calendar: calendar)

        var attempts = 0
        #expect(throws: LogWriteError.fileChangedWhileWriting) {
            try writer.append(entry(start: at(10, 0), end: at(10, 25), loopAfter: 2), calendar: calendar) {
                attempts += 1
                saveALine(attempts, into: url)
            }
        }
        #expect(attempts == LogWriter.maximumWriteAttempts)
    }

    // REQ-LOG-004 / REQ-LOG-005: a collision that clears is not a failure. The entry is written on
    // the next attempt, into what the other save left behind — which is what "reread before
    // writing, take in the external changes" asks for.
    @Test func aCollisionThatClearsIsWrittenOnTheNextAttempt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")
        let writer = LogWriter(fileURL: url)
        try writer.append(entry(), calendar: calendar)

        var attempts = 0
        try writer.append(entry(start: at(10, 0), end: at(10, 25), loopAfter: 2), calendar: calendar) {
            attempts += 1
            if attempts == 1 { saveALine(1, into: url) }
        }

        #expect(attempts == 2, "the first attempt must have been abandoned and read again")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("- a line the user typed (1)"))
        #expect(contents.contains("Loop 2/4"))
        #expect(contents.contains("Loop 1/4"))
    }

    // REQ-LOG-002: the file is created when it is not there — but "not there" is also a snapshot,
    // and a file that appears in the window is entirely someone else's.
    @Test func aFileThatAppearsInTheWindowIsNotReplaced() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")
        let writer = LogWriter(fileURL: url)

        var attempts = 0
        try writer.append(entry(), calendar: calendar) {
            attempts += 1
            if attempts == 1 {
                try? "- notes the user had already written\n".write(to: url, atomically: true, encoding: .utf8)
            }
        }

        #expect(attempts == 2)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("- notes the user had already written"), "a file created in the window was replaced")
        #expect(contents.contains("Loop 1/4"))
    }

    // **Why the contents are compared and not the metadata.** This save keeps the size (one byte
    // replaced by one byte), keeps the inode (written in place through an open descriptor) and
    // keeps the modification date (pinned to a whole second, set again afterwards). No comparison
    // of size, inode or date, in any combination, can see it. It is an ordinary thing for an
    // editor to do: correcting a character in a line.
    @Test func anEditThatKeepsTheSizeTheInodeAndTheDateIsStillCaught() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")
        let manager = FileManager.default
        let writer = LogWriter(fileURL: url)
        try writer.append(entry(), calendar: calendar)

        // A line of the user's whose last letters can be changed one for one.
        let started = try String(contentsOf: url, encoding: .utf8) + "- aaaa\n"
        try started.write(to: url, atomically: true, encoding: .utf8)
        let pinned = Date(timeIntervalSince1970: 1_756_000_000)
        try manager.setAttributes([.modificationDate: pinned], ofItemAtPath: url.path)
        let before = try manager.attributesOfItem(atPath: url.path)

        var attempts = 0
        var afterTheEdit: [FileAttributeKey: Any] = [:]
        try writer.append(entry(start: at(10, 0), end: at(10, 25), loopAfter: 2), calendar: calendar) {
            attempts += 1
            guard attempts == 1 else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seek(toOffset: UInt64(started.utf8.count - 3))
                try? handle.write(contentsOf: Data("b".utf8))
                try? handle.close()
            }
            try? manager.setAttributes([.modificationDate: pinned], ofItemAtPath: url.path)
            afterTheEdit = (try? manager.attributesOfItem(atPath: url.path)) ?? [:]
        }

        // What the guard could not have gone by.
        #expect(afterTheEdit[.size] as? Int == before[.size] as? Int, "the size changed; the test proves less than it claims")
        #expect(afterTheEdit[.systemFileNumber] as? Int == before[.systemFileNumber] as? Int, "the inode changed")
        #expect(afterTheEdit[.modificationDate] as? Date == before[.modificationDate] as? Date, "the date changed")

        #expect(attempts == 2, "an edit invisible to the metadata went through")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("- aaba"), "the user's correction was lost")
        #expect(!contents.contains("- aaaa"))
        #expect(contents.contains("Loop 2/4"))
    }
}
