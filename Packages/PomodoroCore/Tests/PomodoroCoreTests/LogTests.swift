import Testing
import Foundation
@testable import PomodoroCore

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

private func entry(
    type: SessionType = .work,
    start: Date = at(9, 0),
    end: Date = at(9, 25),
    elapsed: Int = 25 * 60,
    outcome: LogOutcome = .completed,
    preset: String = "標準",
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

@Suite("ログ1行の整形 (REQ-LOG-010〜017)")
struct LogFormatterTests {

    // 7.2 の出力例をそのまま再現できること。
    @Test func matchesTheExamplesInSection72() {
        #expect(LogFormatter.line(for: entry(), calendar: calendar)
                == "- 09:00–09:25 WORK 25m ✅ 周回 1/4 [標準] — 仕様書のレビュー")

        #expect(LogFormatter.line(for: entry(
            type: .shortBreak, start: at(9, 25), end: at(9, 30), elapsed: 5 * 60,
            task: nil, loopAfter: nil), calendar: calendar)
                == "- 09:25–09:30 SHORT_BREAK 5m ✅ [標準]")

        #expect(LogFormatter.line(for: entry(
            start: at(9, 32), end: at(10, 4), elapsed: 32 * 60,
            task: "プロトコル設計", extended: 7 * 60, loopAfter: 2), calendar: calendar)
                == "- 09:32–10:04 WORK 32m ✅ 周回 2/4 (延長 +7m) [標準] — プロトコル設計")

        #expect(LogFormatter.line(for: entry(
            type: .shortBreak, start: at(10, 4), end: at(10, 9), elapsed: 5 * 60,
            outcome: .skipped, task: nil, loopAfter: nil), calendar: calendar)
                == "- 10:04–10:09 SHORT_BREAK 5m ⏭ スキップ [標準]")

        #expect(LogFormatter.line(for: entry(
            start: at(11, 35), end: at(11, 43), elapsed: 8 * 60, outcome: .aborted,
            preset: "ディープワーク", task: "プロトコル設計", loopAfter: nil), calendar: calendar)
                == "- 11:35–11:43 WORK 8m ⏹ 中断 [ディープワーク] — プロトコル設計")
    }

    // REQ-LOG-011: 周回は REQ-TIM-025 と同じ剰余表現で、UI の表示と一致させる。
    @Test func loopCountUsesTheSameModuloAsTheUI() {
        #expect(LogFormatter.line(for: entry(loopAfter: 4), calendar: calendar).contains("周回 4/4"))
        #expect(LogFormatter.line(for: entry(loopAfter: 5), calendar: calendar).contains("周回 1/4"))
        #expect(LogFormatter.line(for: entry(loopAfter: 8), calendar: calendar).contains("周回 4/4"))
    }

    // 周回は WORK の**正常完了行**のみ。
    @Test func loopCountIsOmittedForBreaksAndAbnormalEndings() {
        #expect(!LogFormatter.line(for: entry(outcome: .aborted), calendar: calendar).contains("周回"))
        #expect(!LogFormatter.line(for: entry(outcome: .skipped), calendar: calendar).contains("周回"))
        #expect(!LogFormatter.line(for: entry(type: .longBreak, task: nil), calendar: calendar).contains("周回"))
    }

    // REQ-LOG-016: A 群がセッション中に編集されたらプリセット名に * を付す。
    @Test func editedPresetIsMarkedWithAnAsterisk() {
        #expect(LogFormatter.line(for: entry(edited: true), calendar: calendar).contains("[標準*]"))
        #expect(!LogFormatter.line(for: entry(edited: false), calendar: calendar).contains("*"))
    }

    // REQ-LOG-010 / 023: タスク名は WORK のみ。
    @Test func taskNameOnlyAppearsForWork() {
        #expect(!LogFormatter.line(for: entry(type: .shortBreak, task: "残っていたら異常", loopAfter: nil), calendar: calendar).contains("残っていたら異常"))
    }

    // REQ-LOG-013: 既定はリンクにならないプレーンテキスト。設定でリンク化を選べる。
    @Test func taskNameIsPlainByDefaultAndLinkableByOption() {
        let plain = LogFormatter.line(for: entry(task: "プロトコル設計"), calendar: calendar)
        #expect(plain.hasSuffix("— プロトコル設計"))
        #expect(!plain.contains("[["))

        let linked = LogFormatter.line(for: entry(task: "プロトコル設計"), options: .init(taskAsLink: true), calendar: calendar)
        #expect(linked.hasSuffix("— [[プロトコル設計]]"))
    }

    // 本文に [[...]] が残っていても、既定ではリンクにしない。
    @Test func bracketsInTheTaskNameDoNotBecomeALink() {
        let line = LogFormatter.line(for: entry(task: "[[設計ノート]]"), calendar: calendar)
        #expect(!line.contains("[["))
    }

    // REQ-LOG-017: 論理日は sessionStartedAt 基準。境界をまたいだセッションは開始側の見出しへ。
    @Test func logicalDayComesFromTheSessionStart() {
        let startHour = 4
        // 03:50 開始 → 論理日は前日 (境界 04:00 の手前)。
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 3, minute: 50))!
        let crossed = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 4, minute: 15))!
        let day = LogicalDay.date(for: lateNight, dayStartHour: startHour, calendar: calendar)

        let crossing = LogEntry(
            sessionType: .work, startedAt: lateNight, endedAt: crossed, elapsedSeconds: 25 * 60,
            outcome: .completed, presetName: "標準", presetEditedDuringSession: false,
            taskSnapshot: nil, extendedSeconds: 0, loopCountAfterCompletion: 1,
            longBreakInterval: 4, logicalDate: day
        )
        #expect(LogFormatter.dayHeading(for: crossing.logicalDate, calendar: calendar) == "## 2026-08-24 (月)",
                "終了が翌日でも、開始側の日付見出しへ記録する")
        #expect(LogFormatter.line(for: crossing, calendar: calendar).hasPrefix("- 03:50–04:15"))
    }

    // REQ-LOG-003: `## YYYY-MM-DD (曜日)`
    @Test func dayHeadingFormat() {
        #expect(LogFormatter.dayHeading(for: logicalDay, calendar: calendar) == "## 2026-08-24 (月)")
    }
}

@Suite("ログファイルへの挿入 (REQ-LOG-001 / 003 / 022)")
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
        #expect(result == "## 2026-08-24 (月)\n\n- 新しい行\n")
    }

    // REQ-LOG-003: 当該見出しが既にあれば、その日付セクションの末尾へ追記する。
    @Test func appendsToTheEndOfTheMatchingDaySection() throws {
        let existing = """
        ## 2026-08-23 (日)

        - 前日の行

        ## 2026-08-24 (月)

        - 既存の行1
        - 既存の行2

        ## 2026-08-25 (火)

        - 翌日の行

        """
        let result = try insert(into: existing)
        let lines = result.components(separatedBy: "\n")
        let index = lines.firstIndex(of: "- 新しい行")!
        #expect(lines[index - 1] == "- 既存の行2")
        #expect(lines[index + 1] == "")
        #expect(lines[index + 2] == "## 2026-08-25 (火)", "翌日のセクションの前に入る")
    }

    // **既存行は1行たりとも変えない。** これが第一原則。
    @Test func neverModifiesOrDropsExistingLines() throws {
        let existing = """
        # 実績ログ

        ユーザーが自分で書いたメモ。

        ## 2026-08-24 (月)

        - 既存の行
          - 手で足した子行

        ## 2026-08-25 (火)

        - 翌日の行
        """
        let result = try insert(into: existing)
        for line in existing.components(separatedBy: "\n") where !line.isEmpty {
            #expect(result.contains(line), "既存行が失われた: \(line)")
        }
        let before = existing.components(separatedBy: "\n").filter { !$0.isEmpty }
        let after = result.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != "- 新しい行" }
        #expect(before == after, "既存行の順序と内容が保たれていない")
    }

    // REQ-LOG-022: 見出しが外部で削除・改名されていたら、再作成してファイル末尾へ追記する。
    // 既存の行を復元・修正しようとしてはならない。
    @Test func missingHeadingIsRecreatedAtTheEndOfFile() throws {
        let existing = """
        ## 2026-08-23 (日)

        - 前日の行
        """
        let result = try insert(into: existing)
        #expect(result.hasSuffix("## 2026-08-24 (月)\n\n- 新しい行\n"))
        #expect(result.contains("- 前日の行"))
    }

    // Decision 0014: 曜日部分を書き換えられていても、日付が読めれば同じ日として扱う。
    // 見出しを2つ作って記録を分断しない。REQ-LOG-022 の「改名」には当たらない。
    @Test func renamedHeadingIsMatchedByItsDate() throws {
        let existing = "## 2026-08-24 (Mon)\n\n- 既存の行\n"
        let result = try insert(into: existing)
        #expect(result.components(separatedBy: "## ").count == 2, "見出しを二重に作らない")
        #expect(result.contains("## 2026-08-24 (Mon)"), "既存の見出しは書き換えない")
    }

    // REQ-LOG-003: ユーザーが自分で書いた見出しに日付が含まれていても、当該見出しとみなさない。
    @Test func userHeadingContainingADateIsNotTreatedAsTheDaySection() throws {
        let existing = "## 週次レビュー 2026-08-24 の分\n\n- ユーザーのメモ\n"
        let result = try insert(into: existing)
        #expect(result.contains("## 2026-08-24 (月)"), "日付見出しを新設する")
        let lines = result.components(separatedBy: "\n")
        let memo = lines.firstIndex(of: "- ユーザーのメモ")!
        let inserted = lines.firstIndex(of: "- 新しい行")!
        #expect(inserted > memo + 1, "ユーザーの節の中へ混入させない")
    }

    // 既存行を1行でも失う挿入は、書き込む前に止める。第1原則を守る最後の砦。
    @Test func theGuardRejectsAnInsertionThatWouldLoseLines() {
        #expect(!LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新", "c"], insertedAt: 1, count: 1),
                "既存行が書き換わった場合は通してはならない")
        #expect(!LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新"], insertedAt: 1, count: 1),
                "行数が合わない場合は通してはならない")
        #expect(LogFileEditor.preservesAllLines(
            original: ["a", "b"], updated: ["a", "新", "b"], insertedAt: 1, count: 1))
    }

    // CRLF のファイルへ挿入しても改行コードを混ぜない。
    @Test func crlfFilesKeepTheirLineEndings() throws {
        let existing = "## 2026-08-24 (月)\r\n\r\n- 既存の行\r\n"
        let result = try insert(into: existing)
        #expect(!result.contains("- 既存の行\r\n- 新しい行\n"), "挿入行だけ LF にしない")
        #expect(result == "## 2026-08-24 (月)\r\n\r\n- 既存の行\r\n- 新しい行\r\n")
    }

    @Test func sectionAtEndOfFileGetsTheLineAppended() throws {
        let existing = "## 2026-08-24 (月)\n\n- 既存の行\n"
        let result = try insert(into: existing)
        #expect(result == "## 2026-08-24 (月)\n\n- 既存の行\n- 新しい行\n")
    }
}

@Suite("ログの書き込み (REQ-LOG-002 / 004 / 005 / 021)")
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
        ## 2026-08-24 (月)

        - 09:00–09:25 WORK 25m ✅ 周回 1/4 [標準] — 仕様書のレビュー
        - 09:25–09:30 SHORT_BREAK 5m ✅ [標準]

        """)
    }

    // REQ-LOG-004: 書き込み前に再読み込みし、外部変更を取り込んでから追記する。
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
        #expect(contents.contains("- ユーザーが手で書いた行"), "外部で加えられた行を失ってはならない")
        #expect(contents.contains("周回 2/4"))
    }

    // REQ-LOG-002: 作成先ディレクトリが存在しない場合はエラー。
    @Test func missingDirectoryIsRejected() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/PomodoroLog.md")
        #expect(throws: LogWriteError.invalidFilePath) {
            try LogWriter(fileURL: url).append(entry(), calendar: calendar)
        }
    }

    // REQ-LOG-021 / 3原則: Task.md と同一パスは指定できない。
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

@Suite("書き込み失敗時の再試行 (REQ-LOG-005 / REQ-ERR-004)")
struct LogWriteQueueTests {

    @Test func failuresKeepEntriesQueuedAndNotifyOnTheThirdAttempt() {
        let queue = LogWriteQueue()
        queue.enqueue(entry())
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))

        var result = queue.flush { _ in throw LogWriteError.writeFailed("disk") }
        #expect(result.written == 0)
        #expect(result.pending == 2, "失敗した分はキューに残す")
        #expect(!result.shouldNotify)

        result = queue.flush { _ in throw LogWriteError.writeFailed("disk") }
        #expect(result.consecutiveFailures == 2)
        #expect(!result.shouldNotify)

        result = queue.flush { _ in throw LogWriteError.writeFailed("disk") }
        #expect(result.consecutiveFailures == LogWriteQueue.failureThreshold)
        #expect(result.shouldNotify, "REQ-ERR-004: 3回失敗した時点で通知する")

        result = queue.flush { _ in throw LogWriteError.writeFailed("disk") }
        #expect(!result.shouldNotify, "同じ障害で鳴らし続けない")
    }

    @Test func successDrainsTheQueueInOrderAndResetsTheCounter() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)))
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))
        _ = queue.flush { _ in throw LogWriteError.writeFailed("disk") }

        var written: [Date] = []
        let result = queue.flush { written.append($0.startedAt) }
        #expect(result.written == 2)
        #expect(result.pending == 0)
        #expect(result.consecutiveFailures == 0)
        #expect(written == [at(9, 0), at(10, 0)], "時系列の記録なので順序を守る")
    }

    @Test func aFailureMidwayStopsAndKeepsTheRest() {
        let queue = LogWriteQueue()
        queue.enqueue(entry(start: at(9, 0), end: at(9, 25)))
        queue.enqueue(entry(start: at(10, 0), end: at(10, 25)))

        var attempts = 0
        let result = queue.flush { _ in
            attempts += 1
            if attempts == 2 { throw LogWriteError.writeFailed("disk") }
        }
        #expect(result.written == 1)
        #expect(result.pending == 1)
    }
}

@Suite("ログのタスク名は開始時点のスナップショット (REQ-LOG-023)")
struct LogTaskSnapshotTests {

    private func preset() -> Preset {
        Preset(id: "p", name: "標準", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
               longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
    }

    // FINISHED / PENDING_DECISION の間に選び直しても、確定するログ行には反映しない。
    // 反映すると、作業していないタスクが実績として記録される。
    @Test func changingTheSelectionAfterFinishDoesNotChangeTheLoggedName() throws {
        let p = preset()
        let presets = PresetContext(presets: [p], activePresetId: p.id)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let started = try TimerEngine.reduce(
            action: .startWork(presetId: p.id, taskSnapshot: "開始時に選んでいたタスク"),
            context: .idle(now: start), presets: presets, now: start
        ).get().context
        let endAt = started.sessionEndAt!

        // FINISHED に到達させたあと、別のタスクを選び直す。
        let finished = TimerEngine.tick(context: started, presets: presets, now: endAt).context
        #expect(finished.runState == .finished)
        let reselected = try TimerEngine.reduce(
            action: .selectTask(snapshot: "あとから選んだ別のタスク"),
            context: finished, presets: presets, now: endAt.addingTimeInterval(10)
        ).get().context

        // 猶予満了で確定させる。
        let committed = TimerEngine.tick(context: reselected, presets: presets, now: endAt.addingTimeInterval(120))
        guard case let .commitLog(entry) = committed.effects.first else {
            Issue.record("commitLog が出ていない")
            return
        }
        #expect(entry.taskSnapshot == "開始時に選んでいたタスク")
        #expect(LogFormatter.line(for: entry).hasSuffix("— 開始時に選んでいたタスク"))
    }
}
