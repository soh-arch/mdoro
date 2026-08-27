import Testing
import Foundation
@testable import MdoroCore

@Suite("読み込みの頑健性 (REQ-ERR-001 / 002 / 003)")
struct TaskLoadRobustnessTests {

    // REQ-ERR-002: パースに失敗しても空リストで上書きしない。
    // Obsidian の保存途中を読んだだけでも起こりうる。
    @Test func undecodableDataThrowsInsteadOfReturningAnEmptyList() {
        let broken = Data([0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE])
        #expect(throws: TaskParseError.undecodable) { try TaskParser.parse(data: broken) }
    }

    @Test func failedReloadKeepsThePreviousListAndSelection() throws {
        let parsed = TaskParser.parse("- [ ] 仕様書のレビュー\n- [ ] もうひとつ")
        var previous = TaskContext(items: parsed.items, wasTruncated: false)
        try previous.select(id: parsed.items[0].stableId)

        let outcome = TaskReloader.reload(previous: previous, result: .failure(TaskParseError.undecodable))
        #expect(outcome.context.items.count == 2, "REQ-ERR-002: 空リストで上書きしない")
        #expect(outcome.context.selectedTaskState == .present, "選択を missing に落とさない")
        #expect(outcome.context.loadFailed, "エラーを表示できるようにする")
    }

    @Test func successfulReloadClearsTheErrorFlag() throws {
        var previous = TaskContext(items: TaskParser.parse("- [ ] 何か").items, loadFailed: true)
        previous.loadFailed = true
        let outcome = TaskReloader.reload(previous: previous, result: .success(TaskParser.parse("- [ ] 何か")))
        #expect(!outcome.context.loadFailed)
    }

    // REQ-ERR-001: Task.md が存在しない / アクセス権がない。
    @Test func missingFileIsReportedAsUnavailable() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-\(UUID().uuidString).md")
        #expect(throws: TaskFileReader.ReadError.unavailable) { try TaskFileReader(fileURL: url).read() }
    }

    @Test func readerAppliesTheFiveMegabyteLimit() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroTaskTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Task.md")
        var text = "- [ ] 先頭のタスク\n"
        while text.utf8.count < TaskParser.maxBytes + 4_096 { text += "- [ ] 埋め草\n" }
        try text.write(to: url, atomically: true, encoding: .utf8)

        let result = try TaskFileReader(fileURL: url).read()
        #expect(result.wasTruncated)
        #expect(result.items.first?.displayText == "先頭のタスク")
    }
}

@Suite("パースの境界 (REQ-TSK-011 / 013 / 015 / 020)")
struct TaskParsingEdgeTests {

    // 見出しをまたいで親子関係を引き継がない。
    @Test func parentageDoesNotLeakAcrossHeadings() {
        let items = TaskParser.parse("## A\n- [ ] 親A\n\n## B\n    - [ ] Bの下の字下げ").items
        let leaked = items.first { $0.section == "B" }!
        #expect(leaked.parentId == nil, "別の見出しのタスクを親にしてはならない")
    }

    // コードブロックの中は Markdown ではない。
    @Test func fencedBlocksAreIgnored() {
        let text = """
        - [ ] 本物のタスク

        ```
        ## これは見出しではない
        - [ ] これもタスクではない
        ```

        - [ ] もうひとつ本物
        """
        let result = TaskParser.parse(text)
        #expect(result.items.map(\.displayText) == ["本物のタスク", "もうひとつ本物"])
        #expect(result.grouped(showCompleted: true).map(\.name) == [TaskParser.uncategorizedSection])
    }

    // ブロック ID が重複していても一意にする。重複すると2件目が選択できず、UI も破綻する。
    @Test func duplicateBlockIdsStayUnique() {
        let items = TaskParser.parse("- [ ] タスク ^abc\n- [ ] 別のタスク ^abc").items
        #expect(Set(items.map(\.stableId)).count == 2)
        #expect(items[0].stableId == "abc", "先頭は接尾辞を付けず安定させる")
        #expect(items[0].idKind == .blockId)
    }

    // REQ-TSK-015 の除去が本文を壊さないこと。
    // ここが壊れると、実在しないタスク名が PomodoroLog.md に恒久的に残る。
    @Test func displayTextPreservesUnpairedSymbols() {
        #expect(TaskParser.parse("- [ ] snake_case_name を直す").items[0].displayText == "snake_case_name を直す")
        #expect(TaskParser.parse("- [ ] 2*3 の計算").items[0].displayText == "2*3 の計算")
        #expect(TaskParser.parse("- [ ] a_b と c_d").items[0].displayText == "a_b と c_d")
    }

    @Test func displayTextStripsPairedEmphasisAndTags() {
        #expect(TaskParser.parse("- [ ] **強調** と `コード`").items[0].displayText == "強調 と コード")
        #expect(TaskParser.parse("- [ ] 買い物 #家事").items[0].displayText == "買い物",
                "REQ-TSK-015: 生のタグ記法を残さない。ログ行にも入れない")
    }

    // REQ-TSK-022: 絵文字は表示形式によらず落とす。落ち方が揺れると stableId が揺れる。
    @Test func emojiAreRemovedRegardlessOfPresentation() {
        let plain = TaskParser.parse("- [ ] タスク").items[0].normalizedText
        for decorated in ["- [ ] タスク 🔥", "- [ ] タスク ❤️", "- [ ] タスク ☀", "- [ ] タスク 1️⃣"] {
            #expect(TaskParser.parse(decorated).items[0].normalizedText == plain, "\(decorated) が正規化しきれていない")
        }
    }

    @Test func asciiDigitsAndHashesSurviveNormalization() {
        #expect(TaskParser.parse("- [ ] 第1章と第2章").items[0].normalizedText == "第1章と第2章")
    }
}

@Suite("ファイル監視 (REQ-TSK-002 / REQ-PLT-006)")
struct FileWatcherTests {

    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroWatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    // REQ-PLT-006: Obsidian は一時ファイル経由で置き換える。記述子に張った監視は
    // inode 差し替えで無効化されるため、親ディレクトリを監視する。
    @Test func detectsReplacementThroughATemporaryFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Task.md")
        try "- [ ] 最初".write(to: file, atomically: true, encoding: .utf8)

        let counter = Counter()
        let watcher = FileWatcher(fileURL: file, debounce: 0.05) { counter.increment() }
        try watcher.start()
        defer { watcher.stop() }

        // atomically: true は一時ファイル経由の置き換えになる。inode が変わる。
        try "- [ ] 書き換え後".write(to: file, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(3)
        while counter.count == 0, Date() < deadline { usleep(20_000) }
        #expect(counter.count >= 1, "inode が差し替わっても検知できること")
    }

    // REQ-TSK-002: 300ms のデバウンスを挟む。連続保存のたびに読み直さない。
    @Test func burstOfChangesIsCoalescedIntoOneNotification() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Task.md")
        try "- [ ] 最初".write(to: file, atomically: true, encoding: .utf8)

        let counter = Counter()
        let watcher = FileWatcher(fileURL: file, debounce: 0.3) { counter.increment() }
        try watcher.start()
        defer { watcher.stop() }

        for i in 0..<5 {
            try "- [ ] 連続保存\(i)".write(to: file, atomically: true, encoding: .utf8)
            usleep(30_000)
        }

        let deadline = Date().addingTimeInterval(3)
        while counter.count == 0, Date() < deadline { usleep(20_000) }
        usleep(400_000)
        #expect(counter.count == 1, "5回の保存が1回の再読み込みに束ねられること (実測 \(counter.count) 回)")
    }

    @Test func defaultDebounceIsThreeHundredMilliseconds() {
        #expect(FileWatcher.debounceInterval == 0.3)
    }
}
