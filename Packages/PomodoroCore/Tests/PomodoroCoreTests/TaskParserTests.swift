import Testing
import Foundation
@testable import PomodoroCore

private let sample = """
やることメモ

- [ ] 見出しより前のタスク

## 今日

- [ ] 仕様書のレビュー
    - [ ] 第4章
    - [x] 第5章
- [X] 完了したもの
- [-] 取り消したもの
- [ ] リンクつき [[プロトコル設計]] と [外部](https://example.com) #tag
- [ ] ブロックIDつき ^task-1

## あとで

* [ ] アスタリスクのマーカー
+ [ ] プラスのマーカー
- これはタスクではない
本文行
"""

@Suite("タスクのパース (REQ-TSK-010〜016)")
struct TaskParserTests {

    @Test func onlyCheckboxListItemsBecomeTasks() {
        let result = TaskParser.parse(sample)
        #expect(result.items.count == 10)
        #expect(!result.items.contains { $0.displayText == "これはタスクではない" })
        #expect(!result.items.contains { $0.displayText == "本文行" })
    }

    @Test func allThreeListMarkersAreAccepted() {
        let result = TaskParser.parse(sample)
        #expect(result.items.contains { $0.displayText == "アスタリスクのマーカー" })
        #expect(result.items.contains { $0.displayText == "プラスのマーカー" })
    }

    // REQ-TSK-011: 見出しごとにグループ化。見出しより前は「（未分類）」。
    @Test func headingsBecomeSectionsAndPrecedingTasksAreUncategorized() {
        let result = TaskParser.parse(sample)
        let sections = result.grouped(showCompleted: true).map(\.name)
        #expect(sections == [TaskParser.uncategorizedSection, "今日", "あとで"])
        #expect(result.items.first?.section == TaskParser.uncategorizedSection)
    }

    // REQ-TSK-012: 半角スペース以外はすべて完了扱い。
    @Test func anyNonSpaceMarkMeansCompleted() {
        let result = TaskParser.parse(sample)
        let completed = result.items.filter(\.isCompleted).map(\.displayText)
        #expect(completed.contains("第5章"))
        #expect(completed.contains("完了したもの"))
        #expect(completed.contains("取り消したもの"), "[-] も完了として扱う")
        #expect(!completed.contains("仕様書のレビュー"))
    }

    @Test func completedTasksAreExcludedByDefault() {
        let result = TaskParser.parse(sample)
        let visible = result.grouped(showCompleted: false).flatMap(\.items)
        #expect(!visible.contains { $0.isCompleted })
        let all = result.grouped(showCompleted: true).flatMap(\.items)
        #expect(all.count == result.items.count)
    }

    // REQ-TSK-013 / 014: 最初に検出したインデントを1段とし、親子関係を持つ。
    @Test func indentDefinesDepthAndParentage() {
        let result = TaskParser.parse(sample)
        let parent = result.items.first { $0.displayText == "仕様書のレビュー" }!
        let child = result.items.first { $0.displayText == "第4章" }!
        #expect(parent.depth == 0)
        #expect(child.depth == 1)
        #expect(child.parentId == parent.stableId)
    }

    @Test func partialIndentRoundsDownToTheShallowerDepth() {
        // 1段 = 4スペース。6スペースは中途半端なので深さ1へ丸める。
        let text = """
        - [ ] 親
            - [ ] 子
              - [ ] 中途半端
                - [ ] 孫
        """
        let items = TaskParser.parse(text).items
        #expect(items.map(\.depth) == [0, 1, 1, 2])
        #expect(items[2].parentId == items[0].stableId, "丸めた結果、親は深さ0のタスク")
    }

    @Test func tabIndentIsAlsoAUnit() {
        let text = "- [ ] 親\n\t- [ ] 子\n\t\t- [ ] 孫"
        #expect(TaskParser.parse(text).items.map(\.depth) == [0, 1, 2])
    }

    // REQ-TSK-015: 生の記法をそのまま表示しない。
    @Test func markdownIsStrippedForDisplay() {
        let result = TaskParser.parse(sample)
        let item = result.items.first { $0.displayText.contains("リンクつき") }!
        #expect(item.displayText.contains("プロトコル設計"))
        #expect(!item.displayText.contains("[["))
        #expect(!item.displayText.contains("https://example.com"))
        #expect(item.displayText.contains("外部"))
    }

    // REQ-ERR-003 / REQ-TSK-037: 1,000 件で打ち切り、打ち切りを伝える。
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

@Suite("タスクID (REQ-TSK-020〜023)")
struct TaskIdTests {

    // REQ-TSK-020 / 023: ブロック ID があれば優先し、種別を保持する。
    @Test func blockIdWinsAndIsRecorded() {
        let item = TaskParser.parse("- [ ] ブロックIDつき ^task-1").items[0]
        #expect(item.stableId == "task-1")
        #expect(item.idKind == .blockId)
        #expect(!item.displayText.contains("^task-1"), "ブロックIDは本文ではない")
    }

    @Test func contentHashIsUsedWhenNoBlockId() {
        let item = TaskParser.parse("- [ ] ふつうのタスク").items[0]
        #expect(item.idKind == .contentHash)
        #expect(item.stableId.hasPrefix(TaskTextNormalizer.contentHash("ふつうのタスク")))
    }

    // REQ-TSK-020 の値打ち: 文言を直しても選択が維持される。
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

    // REQ-TSK-021: 同一ハッシュ内での出現順で区別する。
    @Test func duplicateBodiesGetDistinctIds() {
        let items = TaskParser.parse("- [ ] 同じ本文\n- [ ] 同じ本文\n- [ ] 同じ本文").items
        #expect(Set(items.map(\.stableId)).count == 3)
        #expect(items.allSatisfy { $0.normalizedText == "同じ本文" })
    }

    // REQ-TSK-022: 装飾の差だけで別タスクにしない。
    @Test func normalizationAbsorbsDecorationDifferences() {
        let plain = TaskParser.parse("- [ ] 仕様書のレビュー").items[0]
        let decorated = TaskParser.parse("- [ ]   **仕様書のレビュー**  #仕事 🔥  ").items[0]
        #expect(plain.normalizedText == decorated.normalizedText)
        #expect(plain.stableId == decorated.stableId)
    }

    @Test func linksAreReplacedByTheirDisplayText() {
        let wiki = TaskParser.parse("- [ ] [[設計ノート|プロトコル設計]] を書く").items[0]
        #expect(wiki.normalizedText == "プロトコル設計 を書く")
        let bare = TaskParser.parse("- [ ] [[プロトコル設計]] を書く").items[0]
        #expect(bare.normalizedText == "プロトコル設計 を書く")
    }

    @Test func nfkcFoldsWidthVariants() {
        let full = TaskParser.parse("- [ ] ＡＢＣ").items[0]
        let half = TaskParser.parse("- [ ] ABC").items[0]
        #expect(full.normalizedText == half.normalizedText)
    }
}
