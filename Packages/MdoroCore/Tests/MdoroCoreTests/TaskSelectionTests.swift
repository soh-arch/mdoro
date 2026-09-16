import Testing
import Foundation
@testable import MdoroCore

// The task texts here are in arbitrary user languages. A Markdown task file holds whatever its
// owner writes, so no one language stands for "not English" — and the follow-through threshold
// (REQ-TSK-032) counts Characters, which is why the distances below are checked in more than one
// script.
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
        var ctx = try context("- [ ] 진행 중\n- [x] 끝난 일")
        #expect(ctx.selectedTaskState == .none)

        let present = ctx.items.first { $0.displayText == "진행 중" }!
        try ctx.select(id: present.stableId)
        #expect(ctx.selectedTaskState == .present)

        let completed = ctx.items.first { $0.displayText == "끝난 일" }!
        try ctx.select(id: completed.stableId)
        #expect(ctx.selectedTaskState == .completed)

        ctx.selectedTaskId = "없는 ID"
        #expect(ctx.selectedTaskState == .missing)
    }

    // REQ-TSK-034: showCompletedTasks must not affect the judgement.
    // A task that is merely out of view is never mistaken for missing.
    @Test func showCompletedSettingDoesNotAffectTheJudgement() throws {
        let ctx = try context("- [x] 已完成", selecting: "已完成")
        #expect(ctx.selectedTaskState == .completed)
        #expect(ctx.grouped(showCompleted: false).flatMap(\.items).isEmpty, "it is filtered out of the visible list")
        #expect(ctx.selectedTaskState == .completed, "but its state must still not be missing")
    }

    // REQ-TSK-036: a stableId that is not in the list is refused, and the selection does not move.
    @Test func selectingAnUnknownIdIsRefused() throws {
        var ctx = try context("- [ ] 作業中", selecting: "作業中")
        let before = ctx.selectedTaskId
        #expect(throws: TimerError.taskNotFound) { try ctx.select(id: "知らないID") }
        #expect(ctx.selectedTaskId == before)
    }
}

@Suite("Reload and selection follow-through (REQ-TSK-030–035)")
struct TaskReloadTests {

    // REQ-TSK-030 / 031: a task disappearing never clears the selection on its own.
    @Test func missingSelectionIsKeptNotCleared() throws {
        let before = try context("- [ ] Revisão da especificação", selecting: "Revisão da especificação")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] Compra do supermercado"))
        #expect(outcome.context.selectedTaskId == before.selectedTaskId)
        #expect(outcome.context.selectedTaskState == .missing)
        #expect(!outcome.didFollow)
        // REQ-TSK-031: the session log records the last text that was known.
        #expect(outcome.context.selectedTaskSnapshot == "Revisão da especificação")
    }

    // REQ-TSK-032: polishing the wording is followed.
    @Test func minorEditIsFollowed() throws {
        let before = try context("- [ ] Revisão da especificação", selecting: "Revisão da especificação")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] Revisão das especificações"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "Revisão das especificações")
    }

    @Test func rewriteBeyondTheThresholdIsNotFollowed() throws {
        let before = try context("- [ ] 仕様書のレビュー", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 買い物に行く"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // With no single candidate, nothing is followed. A wrong link is worse than no link at all.
    @Test func ambiguousCandidatesAreNotFollowed() throws {
        let before = try context("- [ ] 작업A1", selecting: "작업A1")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 작업A2\n- [ ] 작업A3"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // REQ-TSK-035: with the contentHash scheme, an earlier line of the same text disappearing
    // changes the ids that follow. That, too, is followed.
    @Test func shiftedDuplicateIsFollowed() throws {
        let before = try context("- [ ] 同じ本文\n- [ ] 同じ本文")
        var selected = before
        try selected.select(id: before.items[1].stableId)
        #expect(selected.items[1].stableId.hasSuffix("#1"))

        let outcome = TaskReloader.reload(previous: selected, parsed: load("- [ ] 同じ本文"))
        #expect(outcome.didFollow, "a preceding duplicate disappeared, so the id merely shifted")
        #expect(outcome.context.selectedTaskState == .present)
    }

    // With a block ID, follow-through never comes into play at all.
    @Test func blockIdNeedsNoFollowing() throws {
        let before = try context("- [ ] משימה קיימת ^abc123", selecting: "משימה קיימת")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] טקסט שנכתב מחדש ^abc123"))
        #expect(!outcome.didFollow, "the id did not change, so follow-through must not run")
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "טקסט שנכתב מחדש")
    }

    // REQ-TSK-033: becoming completed keeps the selection while the timer is running.
    @Test func becomingCompletedKeepsTheSelection() throws {
        let before = try context("- [ ] 仕様書のレビュー", selecting: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [x] 仕様書のレビュー"))
        #expect(outcome.context.selectedTaskId == before.selectedTaskId)
        #expect(outcome.context.selectedTaskState == .completed)
    }

    @Test func unselectedContextIsUnaffected() throws {
        let before = try context("- [ ] 随便什么")
        let outcome = TaskReloader.reload(previous: before, parsed: load("- [ ] 另一件事"))
        #expect(outcome.context.selectedTaskState == .none)
        #expect(!outcome.didFollow)
    }
}
