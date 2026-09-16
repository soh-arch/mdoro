import Testing
import Foundation
@testable import MdoroCore

// A Task.md holds whatever its owner writes, so the fixture is in arbitrary user languages rather
// than in one stand-in for "not English". The scripts are not decoration: multi-byte text,
// precomposed accents, Hangul and RTL each break differently, and REQ-TSK-015 / 022 run over all
// of them. The width variants and the byte-limit fillers stay Japanese on purpose — those two
// check NFKC folding and a multi-byte cut, which is what they are for.
private let sample = """
やることメモ

- [ ] 제목 앞의 할 일

## 今日

- [ ] Revisão da especificação
    - [ ] 第4章
    - [x] 第5章
- [X] 完了したもの
- [-] ملغاة
- [ ] リンクつき [[プロトコル設計]] と [외부](https://example.com) #tag
- [ ] ブロックIDつき ^task-1

## 나중에

* [ ] 星号标记
+ [ ] Marcador de mais
- 這不是任務
本文行
"""

@Suite("Task parsing (REQ-TSK-010–016)")
struct TaskParserTests {

    @Test func onlyCheckboxListItemsBecomeTasks() {
        let result = TaskParser.parse(sample)
        #expect(result.items.count == 10)
        #expect(!result.items.contains { $0.displayText == "這不是任務" })
        #expect(!result.items.contains { $0.displayText == "本文行" })
    }

    @Test func allThreeListMarkersAreAccepted() {
        let result = TaskParser.parse(sample)
        #expect(result.items.contains { $0.displayText == "星号标记" })
        #expect(result.items.contains { $0.displayText == "Marcador de mais" })
    }

    // REQ-TSK-011: a group per heading. Tasks above the first heading go into "(Uncategorized)".
    @Test func headingsBecomeSectionsAndPrecedingTasksAreUncategorized() {
        let result = TaskParser.parse(sample)
        let sections = result.grouped(showCompleted: true).map(\.name)
        #expect(sections == [TaskParser.uncategorizedSection, "今日", "나중에"])
        #expect(result.items.first?.section == TaskParser.uncategorizedSection)
    }

    // REQ-TSK-012: any character but the ASCII space (U+0020) counts as completed.
    @Test func anyNonSpaceMarkMeansCompleted() {
        let result = TaskParser.parse(sample)
        let completed = result.items.filter(\.isCompleted).map(\.displayText)
        #expect(completed.contains("第5章"))
        #expect(completed.contains("完了したもの"))
        #expect(completed.contains("ملغاة"), "[-] counts as completed as well")
        #expect(!completed.contains("Revisão da especificação"))
    }

    @Test func completedTasksAreExcludedByDefault() {
        let result = TaskParser.parse(sample)
        let visible = result.grouped(showCompleted: false).flatMap(\.items)
        #expect(!visible.contains { $0.isCompleted })
        let all = result.grouped(showCompleted: true).flatMap(\.items)
        #expect(all.count == result.items.count)
    }

    // REQ-TSK-013 / 014: the first indent detected is one level, and parentage follows from it.
    @Test func indentDefinesDepthAndParentage() {
        let result = TaskParser.parse(sample)
        let parent = result.items.first { $0.displayText == "Revisão da especificação" }!
        let child = result.items.first { $0.displayText == "第4章" }!
        #expect(parent.depth == 0)
        #expect(child.depth == 1)
        #expect(child.parentId == parent.stableId)
    }

    @Test func partialIndentRoundsDownToTheShallowerDepth() {
        // One level = 4 spaces. 6 spaces falls in between, so it rounds down to depth 1.
        let text = """
        - [ ] 親
            - [ ] 子
              - [ ] 中途半端
                - [ ] 孫
        """
        let items = TaskParser.parse(text).items
        #expect(items.map(\.depth) == [0, 1, 1, 2])
        #expect(items[2].parentId == items[0].stableId, "after rounding down, the parent is the depth-0 task")
    }

    @Test func tabIndentIsAlsoAUnit() {
        let text = "- [ ] 親\n\t- [ ] 子\n\t\t- [ ] 孫"
        #expect(TaskParser.parse(text).items.map(\.depth) == [0, 1, 2])
    }

    // REQ-TSK-015: raw syntax is never shown as it is.
    @Test func markdownIsStrippedForDisplay() {
        let result = TaskParser.parse(sample)
        let item = result.items.first { $0.displayText.contains("リンクつき") }!
        #expect(item.displayText.contains("プロトコル設計"))
        #expect(!item.displayText.contains("[["))
        #expect(!item.displayText.contains("https://example.com"))
        #expect(item.displayText.contains("외부"))
    }

    // REQ-ERR-003 / REQ-TSK-037: cut off at 1,000 items, and say that it was cut off.
    @Test func parsingStopsAtOneThousandTasks() {
        let text = (1...1_200).map { "- [ ] タスク\($0)" }.joined(separator: "\n")
        let result = TaskParser.parse(text)
        #expect(result.loadedCount == TaskParser.maxTaskCount)
        #expect(result.wasTruncated)
    }

    @Test func smallFileIsNotMarkedTruncated() {
        #expect(!TaskParser.parse(sample).wasTruncated)
    }

    @Test func oversizedDataIsTruncatedToFiveMegabytes() throws {
        let filler = String(repeating: "- [ ] 埋め草\n", count: 1)
        var text = "- [ ] 先頭のタスク\n"
        while text.utf8.count < TaskParser.maxBytes + 1_000 { text += filler }
        let result = try TaskParser.parse(data: Data(text.utf8))
        #expect(result.wasTruncated)
        #expect(result.items.first?.displayText == "先頭のタスク")
    }
}

@Suite("Task IDs (REQ-TSK-020–023)")
struct TaskIdTests {

    // REQ-TSK-020 / 023: a block ID takes precedence, and the kind is kept.
    @Test func blockIdWinsAndIsRecorded() {
        let item = TaskParser.parse("- [ ] ブロックIDつき ^task-1").items[0]
        #expect(item.stableId == "task-1")
        #expect(item.idKind == .blockId)
        #expect(!item.displayText.contains("^task-1"), "the block ID is not part of the display text")
    }

    @Test func contentHashIsUsedWhenNoBlockId() {
        let item = TaskParser.parse("- [ ] משימה רגילה").items[0]
        #expect(item.idKind == .contentHash)
        #expect(item.stableId.hasPrefix(TaskTextNormalizer.contentHash("משימה רגילה")))
    }

    // What REQ-TSK-020 is worth: editing the wording keeps the selection.
    @Test func blockIdSurvivesTextEdits() {
        let before = TaskParser.parse("- [ ] 仕様書のレビュー ^abc123").items[0]
        let after = TaskParser.parse("- [ ] 仕様書の再レビュー（追記あり） ^abc123").items[0]
        #expect(before.stableId == after.stableId)
    }

    @Test func contentHashChangesWhenTextChanges() {
        let before = TaskParser.parse("- [ ] 仕様書のレビュー").items[0]
        let after = TaskParser.parse("- [ ] 仕様書の再レビュー").items[0]
        #expect(before.stableId != after.stableId)
    }

    // REQ-TSK-021: told apart by the order they appear in within the same hash.
    @Test func duplicateBodiesGetDistinctIds() {
        let items = TaskParser.parse("- [ ] 同じ本文\n- [ ] 同じ本文\n- [ ] 同じ本文").items
        #expect(Set(items.map(\.stableId)).count == 3)
        #expect(items.allSatisfy { $0.normalizedText == "同じ本文" })
    }

    // REQ-TSK-022: a difference in decoration alone never makes it a different task.
    @Test func normalizationAbsorbsDecorationDifferences() {
        let plain = TaskParser.parse("- [ ] Revisão da especificação").items[0]
        let decorated = TaskParser.parse("- [ ]   **Revisão da especificação**  #trabalho 🔥  ").items[0]
        #expect(plain.normalizedText == decorated.normalizedText)
        #expect(plain.stableId == decorated.stableId)
    }

    @Test func linksAreReplacedByTheirDisplayText() {
        let wiki = TaskParser.parse("- [ ] [[설계 노트|프로토콜 설계]] 쓰기").items[0]
        #expect(wiki.normalizedText == "프로토콜 설계 쓰기")
        let bare = TaskParser.parse("- [ ] [[프로토콜 설계]] 쓰기").items[0]
        #expect(bare.normalizedText == "프로토콜 설계 쓰기")
    }

    @Test func nfkcFoldsWidthVariants() {
        let full = TaskParser.parse("- [ ] ＡＢＣ").items[0]
        let half = TaskParser.parse("- [ ] ABC").items[0]
        #expect(full.normalizedText == half.normalizedText)
    }
}
