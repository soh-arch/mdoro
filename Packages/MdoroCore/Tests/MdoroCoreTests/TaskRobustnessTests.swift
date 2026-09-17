import Testing
import Foundation
@testable import MdoroCore

// The fixtures are in arbitrary user languages, for the same reason `TaskParserTests` mixes them:
// a Task.md is whatever its owner wrote. Two of them stay Japanese deliberately — the byte-limit
// fillers, which have to be multi-byte to cut where a five-megabyte limit cuts, and the emoji
// base text, where anything but a plain multi-byte word would test the wrong thing.
@Suite("Robust loading (REQ-ERR-001 / 002 / 003)")
struct TaskLoadRobustnessTests {

    // REQ-ERR-002: a failed parse must never overwrite the list with an empty one.
    // Reading Obsidian part-way through a save is enough to cause it.
    @Test func undecodableDataThrowsInsteadOfReturningAnEmptyList() {
        let broken = Data([0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE, 0xFF, 0xFE])
        #expect(throws: TaskParseError.undecodable) { try TaskParser.parse(data: broken) }
    }

    @Test func failedReloadKeepsThePreviousListAndSelection() throws {
        let parsed = TaskParser.parse("- [ ] مراجعة المواصفات\n- [ ] مهمة أخرى")
        var previous = TaskContext(items: parsed.items, wasTruncated: false)
        try previous.select(id: parsed.items[0].stableId)

        let outcome = TaskReloader.reload(previous: previous, result: .failure(TaskParseError.undecodable))
        #expect(outcome.context.items.count == 2, "REQ-ERR-002: must not overwrite the list with an empty one")
        #expect(outcome.context.selectedTaskState == .present, "the selection must not drop to missing")
        #expect(outcome.context.loadFailed, "the failure must be recorded so the UI can show it")
    }

    @Test func successfulReloadClearsTheErrorFlag() throws {
        var previous = TaskContext(items: TaskParser.parse("- [ ] 아무거나").items, loadFailed: true)
        previous.loadFailed = true
        let outcome = TaskReloader.reload(previous: previous, result: .success(TaskParser.parse("- [ ] 아무거나")))
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
        let items = TaskParser.parse("## A\n- [ ] 상위A\n\n## B\n    - [ ] B 아래 들여쓰기").items
        let leaked = items.first { $0.section == "B" }!
        #expect(leaked.parentId == nil, "a task under another heading must not become the parent")
    }

    // Inside a fenced block is not Markdown.
    @Test func fencedBlocksAreIgnored() {
        let text = """
        - [ ] 真正的任务

        ```
        ## 这不是标题
        - [ ] 这也不是任务
        ```

        - [ ] 另一个真正的
        """
        let result = TaskParser.parse(text)
        #expect(result.items.map(\.displayText) == ["真正的任务", "另一个真正的"])
        #expect(result.grouped(showCompleted: true).map(\.name) == [TaskParser.uncategorizedSection])
    }

    // Duplicate block IDs are still made unique. Duplicates leave the second one unselectable,
    // and break the UI with it.
    @Test func duplicateBlockIdsStayUnique() {
        let items = TaskParser.parse("- [ ] Tarefa ^abc\n- [ ] Outra tarefa ^abc").items
        #expect(Set(items.map(\.stableId)).count == 2)
        #expect(items[0].stableId == "abc", "the first occurrence keeps the bare id, with no suffix")
        #expect(items[0].idKind == .blockId)
    }

    // The stripping of REQ-TSK-015 must not damage the text.
    // Break this, and a task name that never existed stays in MdoroLog.md for good.
    @Test func displayTextPreservesUnpairedSymbols() {
        #expect(TaskParser.parse("- [ ] snake_case_name を直す").items[0].displayText == "snake_case_name を直す")
        #expect(TaskParser.parse("- [ ] 2*3 的计算").items[0].displayText == "2*3 的计算")
        #expect(TaskParser.parse("- [ ] a_b و c_d").items[0].displayText == "a_b و c_d")
    }

    @Test func displayTextStripsPairedEmphasisAndTags() {
        #expect(TaskParser.parse("- [ ] **Ênfase** e `código`").items[0].displayText == "Ênfase e código")
        #expect(TaskParser.parse("- [ ] 구매 #집안일").items[0].displayText == "구매",
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

    // REQ-TSK-022: one emoji is often several scalars joined together. All of it goes -- the
    // joiners, the skin tone, the variation selector -- or the leftover changes the hash that
    // REQ-TSK-021 takes of this text.
    @Test func emojiJoinedIntoOneLeaveNothingBehind() {
        let plain = TaskParser.parse("- [ ] Aktualizovat rozvrh").items[0].normalizedText
        for decorated in ["- [ ] Aktualizovat rozvrh \u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F466}",
                          "- [ ] Aktualizovat rozvrh \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}",
                          "- [ ] Aktualizovat rozvrh \u{1F3F3}\u{FE0F}\u{200D}\u{1F308}",
                          "- [ ] Aktualizovat rozvrh \u{1F44B}\u{1F3FF}"] {
            #expect(TaskParser.parse(decorated).items[0].normalizedText == plain,
                    "part of a joined emoji stayed in the text")
        }
    }

    // REQ-TSK-022: the tag letters that spell out a subdivision flag are not emoji themselves.
    // Taken away scalar by scalar, the flag left six invisible characters behind, and two task
    // names that read the same on screen got different stableIds under REQ-TSK-021.
    @Test func aFlagSpelledOutInTagCharactersLeavesNothingInvisibleBehind() {
        // U+1F3F4 followed by the tag letters g b s c t and the cancel tag: one emoji, seven scalars.
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let plain = TaskParser.parse("- [ ] Rendez-vous avec l'équipe").items[0].normalizedText
        let decorated = TaskParser.parse("- [ ] Rendez-vous avec l'équipe \(flag)").items[0].normalizedText
        #expect(decorated == plain, "the flag left something behind")
        let tagCharacters = decorated.unicodeScalars.filter { (0xE0000...0xE007F).contains($0.value) }
        #expect(tagCharacters.isEmpty, "no tag character may survive into the hashed text")
    }

    // REQ-TSK-022: a combining mark that follows an emoji belongs to that emoji. Removed scalar by
    // scalar, the emoji went and the mark stayed, and step (6) folded it onto the letter before:
    // "fase" became "fasé". A name the user never wrote would go into MdoroLog.md under it.
    @Test func aMarkThatFollowedAnEmojiDoesNotLandOnTheLetterBefore() {
        let decorated = "- [ ] Corrigir a fase\u{1F600}\u{0301}"
        #expect(TaskParser.parse(decorated).items[0].normalizedText == "Corrigir a fase")
    }

    // REQ-TSK-022 (4) then (6): a word written in decomposed form keeps every letter and every
    // mark, and the NFKC step puts them back together. Removing an emoji beside it must not reach
    // inside those clusters.
    @Test func aDecomposedWordSurvivesTheEmojiNextToIt() {
        let plain = TaskParser.parse("- [ ] Man\u{0303}ana: revisar el informe").items[0].normalizedText
        #expect(plain == "Ma\u{00F1}ana: revisar el informe", "step (6) composes what step (4) left alone")
        let decorated = TaskParser.parse("- [ ] \u{1F4C5} Man\u{0303}ana: revisar el informe").items[0].normalizedText
        #expect(decorated == plain, "the emoji goes, the decomposed word stays whole")
    }

    // Removing an emoji must not swallow text that merely carries an invisible scalar.
    // A digit under a keycap goes with the sequence (emojiAreRemovedRegardlessOfPresentation), but
    // a letter under the same mark is text and stays. So is a consonant carrying a ZWJ: a joiner
    // attaches to the cluster in front of it, so U+0915 U+200D U+0937 is two clusters and not one
    // conjunct -- a Devanagari conjunct is written with the virama U+094D between the consonants,
    // and a ZWJ after that virama only asks for a half form. Either way the consonants are text
    // and only the joiner comes off.
    @Test func aClusterIsKeptForTheVisibleCharacterItStandsOn() {
        #expect(TaskParser.parse("- [ ] Ticket A\u{20E3} reabrir").items[0].normalizedText == "Ticket A reabrir")
        #expect(TaskParser.parse("- [ ] \u{0915}\u{200D}\u{0937} suchi").items[0].normalizedText == "\u{0915}\u{0937} suchi")
    }

    // REQ-TSK-022 (4) says to remove the emoji, not whatever was standing next to one. A sign that
    // can stand on its own is a character in its own right, and it stays even when the grapheme
    // cluster around it is an emoji's: U+1F600 U+200D U+00A9 is one cluster, and the copyright sign
    // in it is still a copyright sign. Only what cannot stand without the emoji -- a combining
    // mark, a tag letter -- goes with it, which is what the other tests here pin down.
    @Test func aSignThatStandsOnItsOwnIsNotSweptAwayWithTheEmoji() {
        #expect(TaskParser.parse("- [ ] Revisar\u{1F600}\u{200D}\u{00A9}").items[0].normalizedText == "Revisar\u{00A9}")
        #expect(TaskParser.parse("- [ ] Revisar\u{1F600}\u{200D}\u{00AE}").items[0].normalizedText == "Revisar\u{00AE}")
        // U+2605 is not Extended_Pictographic, so a ZWJ does not even draw it into the emoji's
        // cluster -- it is text standing apart, and it stays whichever way the removal goes.
        #expect(TaskParser.parse("- [ ] Revisar\u{1F600}\u{200D}\u{2605}").items[0].normalizedText == "Revisar\u{2605}")
        #expect(TaskParser.parse("- [ ] Revisar \u{1F600}\u{2605}").items[0].normalizedText == "Revisar \u{2605}",
                "a star beside an emoji is a separate character and is not an emoji")
    }

    // The non-joiner is the one invisible scalar that is text. It holds two parts of a word apart
    // in Persian and other scripts -- take it out and the word says something else -- so it stays
    // wherever it lands, including inside the cluster of an emoji that was typed in front of it.
    // `isEmojiScalar` and `standsOnItsOwn` both have to leave it alone, or one of them undoes what
    // the other promises.
    @Test func theNonJoinerIsTextAndSurvivesAnEmojiInFrontOfIt() {
        let plain = TaskParser.parse("- [ ] کتاب\u{200C}ها را برگردان").items[0].normalizedText
        let joiners = plain.unicodeScalars.filter { $0.value == 0x200C }
        #expect(joiners.count == 1, "the non-joiner is part of the word")
        let withEmoji = TaskParser.parse("- [ ] کتاب\u{1F4DA}\u{200C}ها را برگردان").items[0].normalizedText
        #expect(withEmoji == plain, "the emoji goes and the non-joiner stays where it was")
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
        try "- [ ] Início".write(to: file, atomically: true, encoding: .utf8)

        let counter = Counter()
        let watcher = FileWatcher(fileURL: file, debounce: 0.05) { counter.increment() }
        try watcher.start()
        defer { watcher.stop() }

        // atomically: true replaces the file through a temporary one. The inode changes.
        try "- [ ] Depois da reescrita".write(to: file, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(3)
        while counter.count == 0, Date() < deadline { usleep(20_000) }
        #expect(counter.count >= 1, "a change must be detected even when the inode is replaced")
    }

    // REQ-TSK-002: a 300ms debounce sits in between. It does not re-read on every save in a burst.
    @Test func burstOfChangesIsCoalescedIntoOneNotification() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Task.md")
        try "- [ ] Início".write(to: file, atomically: true, encoding: .utf8)

        let counter = Counter()
        let watcher = FileWatcher(fileURL: file, debounce: 0.3) { counter.increment() }
        try watcher.start()
        defer { watcher.stop() }

        for i in 0..<5 {
            try "- [ ] Salvamento \(i)".write(to: file, atomically: true, encoding: .utf8)
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
