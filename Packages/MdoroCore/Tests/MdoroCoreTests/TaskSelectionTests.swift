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

    // The gate on the restore path, seen from this side: **with items in hand, the snapshot is not
    // consulted.** A selection missing from a list that was really read stays missing (REQ-TSK-030),
    // even when the snapshot would have matched something in the new parse.
    @Test func aMissingSelectionDoesNotFollowFromTheSnapshotWhenTheListWasRead() {
        let previous = TaskContext(
            items: load("- [ ] Compra do supermercado").items,
            selectedTaskId: "um ID que desapareceu",
            selectedTaskSnapshot: "Revisão da especificação"
        )
        let outcome = TaskReloader.reload(previous: previous, parsed: load("- [ ] Revisão das especificações"))
        #expect(!outcome.didFollow, "the previous list is evidence, and it did not hold this selection")
        #expect(outcome.context.selectedTaskState == .missing)
    }
}

// What `AppModel.init` hands the first reread after launch (REQ-PER-001 / 002): the persisted
// `stableId` and snapshot, and **no list** — `TaskContext.init` defaults `items` to empty, and the
// file has not been read yet at that point.
private func restoredAtLaunch(selectedTaskId: String, snapshot: String?) -> TaskContext {
    TaskContext(selectedTaskId: selectedTaskId, selectedTaskSnapshot: snapshot)
}

@Suite("Follow-through on the restore path (REQ-TSK-032 / 035 · REQ-PER-002)")
struct RestoredSelectionFollowTests {

    // The ordinary launch: the persisted id is still in the file, so nothing is followed and only
    // the snapshot catches up. **This must stay the quiet case** — no follow notice at every launch.
    @Test func aPersistedIdStillInTheFileIsNotAFollow() {
        let parsed = load("- [ ] 仕様書のレビュー")
        let restored = restoredAtLaunch(selectedTaskId: parsed.items[0].stableId, snapshot: "古い本文")
        let outcome = TaskReloader.reload(previous: restored, parsed: parsed)
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "仕様書のレビュー", "the text catches up")
    }

    // REQ-TSK-032 across a launch. The id is the hash of the normalised text (REQ-TSK-021), so it
    // changes when the wording does — and it changes with no edit at all when normalisation itself
    // changes. Either way the restore has only the snapshot to go on, and it is enough.
    @Test func aRestoredSelectionFollowsTheRewording() {
        let restored = restoredAtLaunch(
            selectedTaskId: "o ID guardado, que já não existe",
            snapshot: "Revisão da especificação"
        )
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] Revisão das especificações"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "Revisão das especificações")
        // REQ-TSK-032: the UI is told, and `AppModel` reads exactly these two fields.
        #expect(outcome.followedFrom == "o ID guardado, que já não existe")
        #expect(outcome.followedTo == outcome.context.selectedTaskId)
    }

    // The other pole. **Nothing about an empty previous list loosens the match.** Every line in the
    // file is a candidate there, so this is the only check left standing, and it refuses a tie.
    @Test func anAmbiguousRestoreFollowsNothing() {
        let restored = restoredAtLaunch(selectedTaskId: "사라진 ID", snapshot: "작업A1")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 작업A2\n- [ ] 작업A3"))
        #expect(!outcome.didFollow, "two candidates at the same distance: a wrong link is worse than none")
        #expect(outcome.context.selectedTaskState == .missing)
        #expect(outcome.context.selectedTaskSnapshot == "작업A1", "REQ-TSK-031: the last known text is kept")
    }

    @Test func aRestoreBeyondTheThresholdFollowsNothing() {
        let restored = restoredAtLaunch(selectedTaskId: "消えたID", snapshot: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 買い物に行く"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // REQ-TSK-030 / 031: a task deleted while the app was closed. There is nothing to follow to, and
    // the selection is still not cleared on its own.
    @Test func aRestoreWithNoCandidateAtAllFollowsNothing() {
        let restored = restoredAtLaunch(selectedTaskId: "已删除的ID", snapshot: "写规格说明")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("# 空的\n"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
        #expect(outcome.context.selectedTaskId == "已删除的ID")
    }

    // An id with no snapshot beside it — an older persisted file, or a write that got half of the
    // pair. There is no text to match on, so nothing is followed and nothing goes wrong.
    @Test func aRestoreWithNoSnapshotFollowsNothing() {
        let restored = restoredAtLaunch(selectedTaskId: "ID בלי טקסט", snapshot: nil)
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] משימה אחרת"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // **The snapshot is `displayText`, not `normalizedText`.** Emoji are in the one and not the
    // other, so the snapshot has to be normalised before the distance to a normalised line means
    // anything.
    //
    // **The pair below is chosen so that the step decides the answer**, which most pairs do not:
    // leaving the emoji in lengthens the source, and a longer source buys a larger allowance, so a
    // short task is where the two emoji characters outweigh what they buy. Here the reworded line is
    // 2 away from the normalised snapshot against an allowance of 2, and 4 away from the raw one
    // against an allowance of 3 — so a regression that stopped normalising would show up as this
    // test's follow no longer happening, not merely as a number moving.
    @Test func theSnapshotIsNormalizedBeforeItIsMatched() {
        #expect(TaskTextNormalizer.normalize(body: "📝 仕様書のレビュー") == "仕様書のレビュー")

        let restored = restoredAtLaunch(selectedTaskId: "前の版のハッシュ", snapshot: "📝 仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 📝 仕様書の最終レビュー"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        // REQ-TSK-015: what the follow records is the new line's display text, emoji and all.
        #expect(outcome.context.selectedTaskSnapshot == "📝 仕様書の最終レビュー")
    }

    // A snapshot that normalises to nothing — a line that was only an emoji. An empty text is
    // within 30% of every text, so it must not be matched at all.
    @Test func aSnapshotThatNormalizesToNothingFollowsNothing() {
        #expect(TaskTextNormalizer.normalize(body: "🔥").isEmpty)

        let restored = restoredAtLaunch(selectedTaskId: "옛날 ID", snapshot: "🔥")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 🔥\n- [ ] 다른 일"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // Two identical lines and a changed hash. The candidates tie at distance 0, and a tie at 0 is
    // not ambiguity: whichever is taken, the text that reaches the log is the same one.
    @Test func identicalCandidatesAreNotAmbiguityOnRestoreEither() {
        let restored = restoredAtLaunch(selectedTaskId: "前の版のハッシュ", snapshot: "同じ本文")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 同じ本文\n- [ ] 同じ本文"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "同じ本文")
    }
}
