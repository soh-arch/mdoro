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


// The shapes a restored selection must refuse. **Anything that is not the same normalised text**,
// including edits the 30% rule would have taken had the previous list been there to justify it.
private struct NotTheSameText: Sendable {
    let what: String
    let snapshot: String
    let file: String
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

    // The positive pole, and the one symptom this path was opened for: **the normalisation rules
    // changed, so the hash changed** (REQ-TSK-021) **while the line in the file did not.** The user
    // typed nothing, so the text matches exactly — which is all that is asked for here.
    @Test func aRestoredSelectionFollowsAnIdThatMovedUnderTheSameText() {
        let parsed = load("- [ ] 仕様書のレビュー")
        // Stands in for the id an earlier version's normalisation gave this same line.
        let restored = restoredAtLaunch(selectedTaskId: "0000000000000000#0", snapshot: "仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: restored, parsed: parsed)
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskId == parsed.items[0].stableId)
        // REQ-TSK-032: the UI is told, and `AppModel` reads exactly these two fields.
        #expect(outcome.followedFrom == "0000000000000000#0")
        #expect(outcome.followedTo == parsed.items[0].stableId)
    }

    // The negative pole. **One edit, answered two ways** — and the same edit both times, so what
    // differs is only whether there was a list. With one, REQ-TSK-032's 30% takes it, untouched.
    // Without one, nothing does: the number was priced against the evidence the list provides, and
    // the evidence does not travel.
    @Test func theSameEditIsFollowedWithTheListAndNotWithoutIt() throws {
        let edited = load("- [ ] Revisão das especificações")

        let withList = try context("- [ ] Revisão da especificação", selecting: "Revisão da especificação")
        let onReload = TaskReloader.reload(previous: withList, parsed: edited)
        #expect(onReload.didFollow, "REQ-TSK-032 on the reload path is untouched")
        #expect(onReload.context.selectedTaskState == .present)

        let withoutList = restoredAtLaunch(selectedTaskId: "o ID guardado", snapshot: "Revisão da especificação")
        let onRestore = TaskReloader.reload(previous: withoutList, parsed: edited)
        #expect(!onRestore.didFollow, "the very same edit, with no list: the allowance does not carry over")
        #expect(onRestore.context.selectedTaskState == .missing)
        // REQ-TSK-030 / 031: still not cleared on its own, and the last known text is still what a
        // session would log.
        #expect(onRestore.context.selectedTaskId == "o ID guardado")
        #expect(onRestore.context.selectedTaskSnapshot == "Revisão da especificação")
    }

    // The same pole, across the range of ways a line can differ. **A task renamed or deleted while
    // the app was closed is a selection that comes off**, which is what someone expects of a tool
    // that reads the file and does not track tasks by line number.
    @Test(arguments: [
        NotTheSameText(what: "one character different", snapshot: "작업A1", file: "- [ ] 작업A2"),
        NotTheSameText(what: "a word appended", snapshot: "仕様書のレビュー", file: "- [ ] 仕様書の最終レビュー"),
        NotTheSameText(what: "a rewrite", snapshot: "仕様書のレビュー", file: "- [ ] 買い物に行く"),
        NotTheSameText(what: "a near-duplicate pair, neither of them it",
                       snapshot: "작업A1", file: "- [ ] 작업A2\n- [ ] 작업A3"),
    ])
    func anythingButTheSameTextIsNotFollowedOnRestore(_ shape: NotTheSameText) {
        let restored = restoredAtLaunch(selectedTaskId: "an id from before", snapshot: shape.snapshot)
        let outcome = TaskReloader.reload(previous: restored, parsed: load(shape.file))
        #expect(!outcome.didFollow, "\(shape.what): the restore path allows no distance at all")
        #expect(outcome.context.selectedTaskState == .missing)
        #expect(outcome.context.selectedTaskSnapshot == shape.snapshot, "REQ-TSK-031: the last known text is kept")
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
    // other, so the snapshot has to be normalised before it can be set against a normalised line at
    // all. Under an exact match that step is no longer worth a couple of points of distance — it is
    // the whole difference between following and not, which is what this pins.
    @Test func theSnapshotIsNormalizedBeforeItIsMatched() {
        #expect(TaskTextNormalizer.normalize(body: "📝 仕様書のレビュー") == "仕様書のレビュー")

        let restored = restoredAtLaunch(selectedTaskId: "0000000000000000#0", snapshot: "📝 仕様書のレビュー")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 📝 仕様書のレビュー"))
        #expect(outcome.didFollow, "the line is unchanged; only the persisted id is from before")
        #expect(outcome.context.selectedTaskState == .present)
        // REQ-TSK-015: what the follow records is the line's display text, emoji and all.
        #expect(outcome.context.selectedTaskSnapshot == "📝 仕様書のレビュー")
    }

    // The other half of the same gap: `displayText` has not been through NFKC either. A line written
    // in fullwidth letters normalises to halfwidth, and the snapshot kept the fullwidth ones.
    @Test func theSnapshotGoesThroughNFKCBeforeItIsMatched() {
        #expect(TaskTextNormalizer.normalize(body: "ＡＰＩ の確認") == "API の確認")

        let restored = restoredAtLaunch(selectedTaskId: "0000000000000000#0", snapshot: "ＡＰＩ の確認")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] ＡＰＩ の確認"))
        #expect(outcome.didFollow, "the line is unchanged; only the persisted id is from before")
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "ＡＰＩ の確認", "REQ-TSK-015: fullwidth is how it is written")
    }

    // A snapshot that normalises to nothing — a line that was only an emoji. **With no distance
    // allowed, empty is an exact match for every line that also normalises to nothing**, so the
    // emptiness has to be refused before the comparison rather than left to the distance.
    @Test func aSnapshotThatNormalizesToNothingFollowsNothing() {
        #expect(TaskTextNormalizer.normalize(body: "🔥").isEmpty)

        let restored = restoredAtLaunch(selectedTaskId: "옛날 ID", snapshot: "🔥")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 🔥\n- [ ] 다른 일"))
        #expect(!outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .missing)
    }

    // Two identical lines and a changed hash. The candidates tie at distance 0, and a tie at 0 is
    // not ambiguity: whichever is taken, the text that reaches the log is the same one. **An exact
    // match does not change this** — it is the one place where a tie is still allowed to resolve.
    @Test func identicalCandidatesAreNotAmbiguityOnRestoreEither() {
        let restored = restoredAtLaunch(selectedTaskId: "前の版のハッシュ", snapshot: "同じ本文")
        let outcome = TaskReloader.reload(previous: restored, parsed: load("- [ ] 同じ本文\n- [ ] 同じ本文"))
        #expect(outcome.didFollow)
        #expect(outcome.context.selectedTaskState == .present)
        #expect(outcome.context.selectedTaskSnapshot == "同じ本文")
    }
}
