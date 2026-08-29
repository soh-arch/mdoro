import Testing
import Foundation
@testable import MdoroCore

@Suite("Robust loading (REQ-ERR-001 / 002 / 003)")
struct TaskLoadRobustnessTests {

    // REQ-ERR-002: a failed parse must never overwrite the list with an empty one.
    // Reading Obsidian part-way through a save is enough to cause it.
    @Test func undecodableDataThrowsInsteadOfReturningAnEmptyList() {
        let broken = Data([0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE])
        #expect(throws: TaskParseError.undecodable) { try TaskParser.parse(data: broken) }
    }

    @Test func failedReloadKeepsThePreviousListAndSelection() throws {
        let parsed = TaskParser.parse("- [ ] 仕様書のレビュー\n- [ ] もうひとつ")
        var previous = TaskContext(items: parsed.items, wasTruncated: false)
        try previous.select(id: parsed.items[0].stableId)

        let outcome = TaskReloader.reload(previous: previous, result: .failure(TaskParseError.undecodable))
        #expect(outcome.context.items.count == 2, "REQ-ERR-002: must not overwrite the list with an empty one")
        #expect(outcome.context.selectedTaskState == .present, "the selection must not drop to missing")
        #expect(outcome.context.loadFailed, "the failure must be recorded so the UI can show it")
    }

    @Test func successfulReloadClearsTheErrorFlag() throws {
        var previous = TaskContext(items: TaskParser.parse("- [ ] 何か").items, loadFailed: true)
        previous.loadFailed = true
        let outcome = TaskReloader.reload(previous: previous, result: .success(TaskParser.parse("- [ ] 何か")))
        #expect(!outcome.context.loadFailed)
    }

    // REQ-ERR-001: Task.md does not exist, or there is no permission for it.
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

@Suite("Parsing boundaries (REQ-TSK-011 / 013 / 015 / 020)")
struct TaskParsingEdgeTests {

    // Parentage is never carried across a heading.
    @Test func parentageDoesNotLeakAcrossHeadings() {
        let items = TaskParser.parse("## A\n- [ ] 親A\n\n## B\n    - [ ] Bの下の字下げ").items
        let leaked = items.first { $0.section == "B" }!
        #expect(leaked.parentId == nil, "a task under another heading must not become the parent")
    }

    // Inside a fenced block is not Markdown.
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

    // Duplicate block IDs are still made unique. Duplicates leave the second one unselectable,
    // and break the UI with it.
    @Test func duplicateBlockIdsStayUnique() {
        let items = TaskParser.parse("- [ ] タスク ^abc\n- [ ] 別のタスク ^abc").items
        #expect(Set(items.map(\.stableId)).count == 2)
        #expect(items[0].stableId == "abc", "the first occurrence keeps the bare id, with no suffix")
        #expect(items[0].idKind == .blockId)
    }

    // The stripping of REQ-TSK-015 must not damage the text.
    // Break this, and a task name that never existed stays in MdoroLog.md for good.
    @Test func displayTextPreservesUnpairedSymbols() {
        #expect(TaskParser.parse("- [ ] snake_case_name を直す").items[0].displayText == "snake_case_name を直す")
        #expect(TaskParser.parse("- [ ] 2*3 の計算").items[0].displayText == "2*3 の計算")
        #expect(TaskParser.parse("- [ ] a_b と c_d").items[0].displayText == "a_b と c_d")
    }

    @Test func displayTextStripsPairedEmphasisAndTags() {
        #expect(TaskParser.parse("- [ ] **強調** と `コード`").items[0].displayText == "強調 と コード")
        #expect(TaskParser.parse("- [ ] 買い物 #家事").items[0].displayText == "買い物",
                "REQ-TSK-015: raw tag syntax must not survive into the display text or the log line")
    }

    // REQ-TSK-022: emoji are dropped whatever their presentation. A wobble in how they drop makes
    // stableId wobble with it.
    @Test func emojiAreRemovedRegardlessOfPresentation() {
        let plain = TaskParser.parse("- [ ] タスク").items[0].normalizedText
        for decorated in ["- [ ] タスク 🔥", "- [ ] タスク ❤️", "- [ ] タスク ☀", "- [ ] タスク 1️⃣"] {
            #expect(TaskParser.parse(decorated).items[0].normalizedText == plain, "\(decorated) was not fully normalized")
        }
    }

    @Test func asciiDigitsAndHashesSurviveNormalization() {
        #expect(TaskParser.parse("- [ ] 第1章と第2章").items[0].normalizedText == "第1章と第2章")
    }
}

@Suite("File watching (REQ-TSK-002 / REQ-PLT-006)")
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

    // REQ-PLT-006: Obsidian replaces the file through a temporary one. A watch put on the
    // descriptor is voided when the inode is swapped, so the parent directory is watched instead.
    @Test func detectsReplacementThroughATemporaryFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Task.md")
        try "- [ ] 最初".write(to: file, atomically: true, encoding: .utf8)

        let counter = Counter()
        let watcher = FileWatcher(fileURL: file, debounce: 0.05) { counter.increment() }
        try watcher.start()
        defer { watcher.stop() }

        // atomically: true replaces the file through a temporary one. The inode changes.
        try "- [ ] 書き換え後".write(to: file, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(3)
        while counter.count == 0, Date() < deadline { usleep(20_000) }
        #expect(counter.count >= 1, "a change must be detected even when the inode is replaced")
    }

    // REQ-TSK-002: a 300ms debounce sits in between. It does not re-read on every save in a burst.
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
        #expect(counter.count == 1, "5 saves must coalesce into 1 reload (observed \(counter.count))")
    }

    @Test func defaultDebounceIsThreeHundredMilliseconds() {
        #expect(FileWatcher.debounceInterval == 0.3)
    }
}
