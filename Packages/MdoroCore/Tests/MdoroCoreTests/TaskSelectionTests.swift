import Testing
import Foundation
@testable import MdoroCore

private func load(_ text: String) -> TaskParseResult { TaskParser.parse(text) }

private func context(_ text: String, selecting displayText: String? = nil) throws -> TaskContext {
    let parsed = load(text)
    var ctx = TaskContext(items: parsed.items, wasTruncated: parsed.wasTruncated)
    if let displayText, let target = parsed.items.first(where: { $0.displayText == displayText }) {
        try ctx.select(id: target.stableId)
    }
    return ctx
}

@Suite("State of the selected task (REQ-TSK-034 / 036)")
struct SelectedTaskStateTests {

    @Test func judgementOrderIsNoneCompletedPresentMissing() throws {
        var ctx = try context("- [ ] 作業中\n- [x] 済んだもの")
        #expect(ctx.selectedTaskState == .none)

        let present = ctx.items.first { $0.displayText == "作業中" }!
        try ctx.select(id: present.stableId)
        #expect(ctx.selectedTaskState == .present)

        let completed = ctx.items.first { $0.displayText == "済んだもの" }!
        try ctx.select(id: completed.stableId)
        #expect(ctx.selectedTaskState == .completed)

        ctx.selectedTaskId = "存在しないID"
        #expect(ctx.selectedTaskState == .missing)
    }

    // REQ-TSK-034: showCompletedTasks は判定に影響してはならない。
    // 表示から外れているだけのタスクを missing と誤判定しない。
    @Test func showCompletedSettingDoesNotAffectTheJudgement() throws {
        let ctx = try context("- [x] 済んだもの", selecting: "済んだもの")
        #expect(ctx.selectedTaskState == .completed)
        #expect(ctx.grouped(showCompleted: false).flatMap(\.items).isEmpty, "it is filtered out of the visible list")
        #expect(ctx.selectedTaskState == .completed, "but its state must still not be missing")
    }

    // REQ-TSK-036: 一覧に無い stableId は受け付けず、選択も変えない。
    @Test func selectingAnUnknownIdIsRefused() throws {
        var ctx = try context("- [ ] 作業中", selecting: "作業中")
        let before = ctx.selectedTaskId
        #expect(throws: TimerError.taskNotFound) { try ctx.select(id: "知らないID") }
        #expect(ctx.selectedTaskId == before)
    }
}

@Suite("Reload and selection follow-through (REQ-TSK-030–035)")
struct TaskReloadTests {

    // REQ-TSK-030 / 031: 消えても自動的に選択を解除しない。
    @Test func missingSelectionIsKeptNotCleared() throws {
        let before = try context("- [ ] 仕様書のレビュー", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] まったく別のタスク"))
        #expect(outcome.context.selectedTaskId == before.selectedTaskId)
        #expect(outcome.context.selectedTaskState == .missing)
        #expect(!outcome.didFollow)
        // REQ-TSK-031: 実績ログには最後に既知だった本文を記録する。
        #expect(outcome.context.selectedTaskSnapshot == "仕様書のレビュー")
    }

    // REQ-TSK-032: 文言の推敲には追従する。
    @Test func minorEditIsFollowed() throws {
        let before = try context("- [ ] 仕様書のレビューをする", selecting: "仕様書のレビューをする")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 仕様書のレビューをやる"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "仕様書のレビューをやる")
    }

    @Test func rewriteBeyondTheThresholdIsNotFollowed() throws {
        let before = try context("- [ ] 仕様書のレビュー", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 買い物に行く"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // 候補が一意に定まらないときは追従しない。間違った紐付けは、外れているより悪い。
    @Test func ambiguousCandidatesAreNotFollowed() throws {
        let before = try context("- [ ] タスクA1", selecting: "タスクA1")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] タスクA2\n- [ ] タスクA3"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // REQ-TSK-035: contentHash 方式では、同一本文の先行する行が消えると後続の ID が変わる。
    // これも追従の対象。
    @Test func shiftedDuplicateIsFollowed() throws {
        let before = try context("- [ ] 同じ本文\n- [ ] 同じ本文")
        var selected = before
        try selected.select(id: before.items[1].stableId)
        #expect(selected.items[1].stableId.hasSuffix("#1"))

        let outcome = TaskReloader.reload(previous: selected, parsed: load("- [ ] 同じ本文"))
        #expect(outcome.didFollow, "a preceding duplicate disappeared, so the id merely shifted")
        #expect(outcome.context.selectedTaskState == .present)
    }

    // ブロック ID があれば、そもそも追従の出番がない。
    @Test func blockIdNeedsNoFollowing() throws {
        let before = try context("- [ ] 仕様書のレビュー ^abc123", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 全面的に書き直した文言 ^abc123"))
        #expect(!outcome.didFollow, "the id did not change, so follow-through must not run")
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "全面的に書き直した文言")
    }

    // REQ-TSK-033: 完了済みになってもタイマー実行中は選択を維持する。
    @Test func becomingCompletedKeepsTheSelection() throws {
        let before = try context("- [ ] 仕様書のレビュー", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [x] 仕様書のレビュー"))
        #expect(outcome.context.selectedTaskId == before.selectedTaskId)
        #expect(outcome.context.selectedTaskState == .completed)
    }

    @Test func unselectedContextIsUnaffected() throws {
        let before = try context("- [ ] なにか")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] べつのなにか"))
        #expect(outcome.context.selectedTaskState == .none)
        #expect(!outcome.didFollow)
    }
}
