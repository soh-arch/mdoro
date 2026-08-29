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
    @Test func missingHeadingIsRecreatedAtTheEndOfFile() throws {
        let existing = """
        ## 2026-08-23 (Sun)

        - 前日の行
        """
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

    // REQ-LOG-021 / the first principle: the same path as Task.md can never be chosen.
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

    @Test func failuresKeepEntriesQueuedAndNotifyOnTheThirdAttempt() {
        let queue = LogWriteQueue()
        queue.enqueue(entry())
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))

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
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)))
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))
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
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)))
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))

        var attempts = 0
        let result = queue.flush { _ in
            attempts += 1
            if attempts == 2 { throw writeRefused }
        }
        #expect(result.written == 1)
        #expect(result.pending == 1)
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
