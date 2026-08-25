import Testing
import Foundation
@testable import PomodoroCore

// MARK: - Test helpers

private func makePreset(
    id: String = "preset-1",
    name: String = "標準",
    work: Int = 25 * 60,
    short: Int = 5 * 60,
    long: Int = 15 * 60,
    interval: Int = 4,
    extend: Int = 5 * 60
) -> Preset {
    Preset(
        id: id,
        name: name,
        workSeconds: work,
        shortBreakSeconds: short,
        longBreakSeconds: long,
        longBreakInterval: interval,
        extendSeconds: extend
    )
}

private func makePresetContext(_ preset: Preset) -> PresetContext {
    PresetContext(presets: [preset], activePresetId: preset.id)
}

private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000) // 固定時刻。相対秒だけで検証する。

// MARK: - 4.6 状態遷移マトリクス

@Suite("状態遷移マトリクス (4.6)")
struct StateTransitionMatrixTests {
    private let allStates: [RunState] = [.idle, .running, .paused, .finished, .pendingDecision]

    private func check(_ action: TimerAction, acceptedIn accepted: Set<RunState>, sourceLocation: SourceLocation = #_sourceLocation) {
        for state in allStates {
            let expected = accepted.contains(state)
            #expect(
                StateTransitionMatrix.canAccept(action, in: state) == expected,
                "action=\(action) state=\(state) expected=\(expected)",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test func startSession() {
        check(.startWork(presetId: "p", taskSnapshot: nil), acceptedIn: [.idle, .finished])
        check(.startBreak(type: .shortBreak, presetId: "p"), acceptedIn: [.idle, .finished])
    }

    @Test func pause() {
        check(.pause, acceptedIn: [.running])
    }

    @Test func resume() {
        check(.resume, acceptedIn: [.paused])
    }

    @Test func skip() {
        check(.skip, acceptedIn: [.running, .paused])
    }

    @Test func abort() {
        check(.abort, acceptedIn: [.running, .paused, .finished])
    }

    @Test func extend() {
        check(.extend, acceptedIn: [.running, .paused, .finished])
    }

    @Test func resetLoopCount() {
        check(.resetLoopCount, acceptedIn: [.idle, .running, .paused, .finished])
    }

    @Test func confirmRestoredSession() {
        check(.confirmRestoredSession(.complete), acceptedIn: [.pendingDecision])
    }

    @Test func taskSelectionAlwaysAccepted() {
        check(.selectTask(snapshot: "x"), acceptedIn: Set(allStates))
        check(.clearTaskSelection, acceptedIn: Set(allStates))
    }

    @Test func reloadTasksAlwaysAccepted() {
        check(.reloadTasks, acceptedIn: Set(allStates))
    }

    @Test func updateSettingsAlwaysAccepted() {
        check(.updateSettings(.default), acceptedIn: Set(allStates))
    }

    @Test func presetEditAlwaysAccepted() {
        check(.selectPreset(id: "p"), acceptedIn: Set(allStates))
        check(.updatePreset(makePreset()), acceptedIn: Set(allStates))
    }

    @Test func presetManagementAlwaysAccepted() {
        check(.createPreset(makePreset(id: "new")), acceptedIn: Set(allStates))
        check(.duplicatePreset(id: "p"), acceptedIn: Set(allStates))
        check(.deletePreset(id: "p"), acceptedIn: Set(allStates))
        check(.reorderPresets(order: ["p"]), acceptedIn: Set(allStates))
        check(.restoreDefaultPreset, acceptedIn: Set(allStates))
    }

    @Test func rejectedActionReturnsInvalidStateForAction() {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let context = TimerContext.idle(now: referenceDate)
        // pause は IDLE では受理されない。
        let result = TimerEngine.reduce(action: .pause, context: context, presets: presets, now: referenceDate)
        #expect(result == .failure(TimerFailure(error: .invalidStateForAction, effects: [])))
    }
}

// MARK: - 周回数と nextSessionType

@Suite("周回数と nextSessionType (4.3 / 4.4)")
struct LoopCountTests {
    @Test func workCompletionAccumulatesLoopAndSuggestsLongBreakOnFourthLoop() throws {
        let preset = makePreset(interval: 4)
        var presets = makePresetContext(preset)
        var context = TimerContext.idle(now: referenceDate)
        var now = referenceDate

        for i in 1...4 {
            let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: context, presets: presets, now: now).get()
            context = started.context
            presets = started.presets
            now = context.sessionEndAt!

            let ticked = TimerEngine.tick(context: context, presets: presets, now: now)
            context = ticked.context

            #expect(context.loopCount == i)
            #expect(context.runState == .finished)
            if i < 4 {
                #expect(context.nextSessionType == .shortBreak, "loop \(i)")
            } else {
                #expect(context.nextSessionType == .longBreak, "loop \(i) should suggest LONG_BREAK")
            }
        }
    }

    @Test func skippedWorkDoesNotIncrementLoopAndSuggestsShortBreak() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let skipTime = referenceDate.addingTimeInterval(60)
        let skipped = try TimerEngine.reduce(action: .skip, context: started.context, presets: started.presets, now: skipTime).get()

        #expect(skipped.context.loopCount == 0)
        #expect(skipped.context.nextSessionType == .shortBreak)
        #expect(skipped.context.runState == .idle)
    }

    @Test func abortedWorkDoesNotIncrementLoopAndSuggestsShortBreak() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let abortTime = referenceDate.addingTimeInterval(60)
        let aborted = try TimerEngine.reduce(action: .abort, context: started.context, presets: started.presets, now: abortTime).get()

        #expect(aborted.context.loopCount == 0)
        #expect(aborted.context.nextSessionType == .shortBreak)
    }

    @Test func loopCountZeroNeverSuggestsLongBreakEvenWithInterval1() {
        // REQ-TIM-015: loopCount が 0 のときに倍数判定で LONG_BREAK を導いてはならない。
        let next = TimerEngine.standardNextSessionType(after: .shortBreak, loopCount: 0, longBreakInterval: 1)
        #expect(next == .work)
    }

    @Test func resetLoopCountImmediatelySuggestsWork() throws {
        let preset = makePreset(interval: 1) // 最も LONG_BREAK が出やすい設定
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let finishTime = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: started.presets, now: finishTime).context
        #expect(finished.loopCount == 1)

        let reset = try TimerEngine.reduce(action: .resetLoopCount, context: finished, presets: presets, now: finishTime.addingTimeInterval(10)).get()
        #expect(reset.context.loopCount == 0)
        #expect(reset.context.nextSessionType == .work, "REQ-TIM-015: リセット直後に LONG_BREAK を提案してはならない")
    }
}

// MARK: - 延長・FINISHED からの周回取り消し

@Suite("延長と FINISHED からの取り消し (4.7)")
struct ExtendAndFinishedTests {
    @Test func extendFromFinishedDecrementsLoopAndReturnsToRunning() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context
        #expect(finished.loopCount == 1)

        let extendTime = endAt.addingTimeInterval(60) // 猶予内
        let extended = try TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: extendTime).get()

        #expect(extended.context.runState == .running)
        #expect(extended.context.loopCount == 0, "REQ-TIM-042: 延長で周回数を1減らす")
        #expect(extended.context.sessionEndAt == endAt.addingTimeInterval(TimeInterval(preset.extendSeconds)))
        #expect(extended.context.extendedSeconds == preset.extendSeconds)
    }

    @Test func abortFromFinishedAlsoDecrementsLoop() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context
        #expect(finished.loopCount == 1)

        let abortTime = endAt.addingTimeInterval(60)
        let aborted = try TimerEngine.reduce(action: .abort, context: finished, presets: presets, now: abortTime).get()

        #expect(aborted.context.loopCount == 0, "REQ-TIM-036: FINISHED からの abort も1減らす")
        #expect(aborted.context.runState == .idle)
    }

    @Test func extendAllowedWithinGraceRejectedAfterGrace() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        let withinGrace = endAt.addingTimeInterval(TimerEngine.extensionGraceSeconds - 1)
        let withinResult = TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: withinGrace)
        #expect(withinResult.isSuccess)

        let afterGrace = endAt.addingTimeInterval(TimerEngine.extensionGraceSeconds + 1)
        let afterResult = TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: afterGrace)
        // 猶予超過後は tick() が先に確定させ IDLE へ遷移するため、extend はマトリクス上拒否される。
        // ただし拒否時も、tick() が確定させた commitLog は失われてはならない (REQ-LOG-018)。
        guard case let .failure(failure) = afterResult else {
            Issue.record("猶予超過後の extend は拒否されるべき")
            return
        }
        #expect(failure.error == .invalidStateForAction)
        #expect(failure.effects.count == 1)
    }
}

// MARK: - 確定処理の冪等性 (REQ-LOG-019)

@Suite("確定処理の冪等性")
struct CommitIdempotencyTests {
    @Test func breakFinishedCommitsExactlyOnce() throws {
        let preset = makePreset(short: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startBreak(type: .shortBreak, presetId: preset.id), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!

        let firstTick = TimerEngine.tick(context: started.context, presets: presets, now: endAt)
        #expect(firstTick.context.runState == .idle, "REQ-TIM-044: 休憩は猶予なく即座に確定する")
        #expect(firstTick.effects.count == 1)

        let secondTick = TimerEngine.tick(context: firstTick.context, presets: presets, now: endAt.addingTimeInterval(120))
        #expect(secondTick.effects.isEmpty, "既に確定済みのセッションを再確定してはならない")
    }

    @Test func repeatedAbortOnAlreadyFinalizedSessionIsRejected() throws {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        let abortTime = endAt.addingTimeInterval(30)
        let firstAbort = try TimerEngine.reduce(action: .abort, context: finished, presets: presets, now: abortTime).get()
        #expect(firstAbort.effects.count == 1)
        #expect(firstAbort.context.runState == .idle)

        // 同じ操作を確定後のコンテキストに対して再度行うと、マトリクス上 IDLE では abort が拒否される。
        let secondAbort = TimerEngine.reduce(action: .abort, context: firstAbort.context, presets: presets, now: abortTime.addingTimeInterval(5))
        #expect(secondAbort == .failure(TimerFailure(error: .invalidStateForAction, effects: [])))
    }

    @Test func startWorkResetAbortAllFinalizeOnlyOnceFromFinished() throws {
        // CLAUDE.md: 休憩が FINISHED に留まる間の中断・次セッション開始・リセットで二重記録されないことを、
        // それぞれ独立したシナリオとして確認する。
        let preset = makePreset()
        let presets = makePresetContext(preset)

        for trigger in ["abort", "startWork", "resetLoopCount"] {
            let idle = TimerContext.idle(now: referenceDate)
            let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
            let endAt = started.context.sessionEndAt!
            let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context
            let actionTime = endAt.addingTimeInterval(30)

            let action: TimerAction
            switch trigger {
            case "abort": action = .abort
            case "startWork": action = .startWork(presetId: preset.id, taskSnapshot: nil)
            default: action = .resetLoopCount
            }

            let reduction = try TimerEngine.reduce(action: action, context: finished, presets: presets, now: actionTime).get()
            #expect(reduction.effects.count == 1, "trigger=\(trigger) は1回だけ確定するべき")
        }
    }
}

// MARK: - 実経過時間 (REQ-TIM-005)

@Suite("一時停止を挟んだ実経過時間")
struct NetWorkingTimeTests {
    @Test func pauseIsExcludedFromElapsedSeconds() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)

        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let pauseTime = referenceDate.addingTimeInterval(300) // 5分経過後に一時停止
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: pauseTime).get()
        #expect(paused.context.remainingSeconds == 1200)

        let resumeTime = pauseTime.addingTimeInterval(600) // 10分間一時停止
        let resumed = try TimerEngine.reduce(action: .resume, context: paused.context, presets: presets, now: resumeTime).get()
        #expect(resumed.context.accumulatedPausedSeconds == 600)

        let endAt = resumed.context.sessionEndAt!
        #expect(endAt == resumeTime.addingTimeInterval(1200))

        // 猶予内、終了時刻ちょうどで中断して、確定されるログの実経過時間を検証する。
        let ticked = TimerEngine.tick(context: resumed.context, presets: presets, now: endAt)
        let aborted = try TimerEngine.reduce(action: .abort, context: ticked.context, presets: presets, now: endAt).get()

        guard case let .commitLog(entry)? = aborted.effects.first else {
            Issue.record("commitLog effect が見つからない")
            return
        }
        #expect(entry.elapsedSeconds == 25 * 60, "一時停止10分を除いた正味25分になるべき")
    }
}

// MARK: - 9.5 設定変更の適用タイミング (A/B/C 群)

@Suite("設定変更の適用タイミング (9.5)")
struct SettingsApplicationTests {
    @Test func groupAChangeDoesNotAlterRunningSessionEndAt() throws {
        let preset = makePreset(work: 25 * 60)
        var presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let originalEndAt = started.context.sessionEndAt

        var updated = preset
        updated.workSeconds = 40 * 60 // A群: 時間項目の変更
        let result = try TimerEngine.reduce(action: .updatePreset(updated), context: started.context, presets: started.presets, now: referenceDate.addingTimeInterval(10)).get()
        presets = result.presets

        #expect(result.context.sessionEndAt == originalEndAt, "REQ-CFG-003: 実行中の sessionEndAt を変更してはならない")
        #expect(result.context.presetEditedDuringSession == true, "REQ-CFG-017")
        #expect(presets.preset(id: preset.id)?.workSeconds == 40 * 60)
    }

    @Test func groupBChangeAppliesImmediatelyToExtend() throws {
        let preset = makePreset(extend: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        var updated = preset
        updated.extendSeconds = 10 * 60 // B群
        let afterUpdate = try TimerEngine.reduce(action: .updatePreset(updated), context: started.context, presets: presets, now: referenceDate.addingTimeInterval(5)).get()

        let beforeExtend = afterUpdate.context.sessionEndAt!
        let extended = try TimerEngine.reduce(action: .extend, context: afterUpdate.context, presets: afterUpdate.presets, now: referenceDate.addingTimeInterval(10)).get()

        #expect(extended.context.sessionEndAt == beforeExtend.addingTimeInterval(10 * 60), "REQ-CFG-015: B群は実行中セッションにも即座に適用される")
    }

    @Test func outOfRangePresetUpdateIsRejected() {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)

        var invalid = preset
        invalid.workSeconds = 999_999 // REQ-CFG-018: 範囲外
        let result = TimerEngine.reduce(action: .updatePreset(invalid), context: idle, presets: presets, now: referenceDate)
        #expect(result == .failure(TimerFailure(error: .settingOutOfRange, effects: [])))
    }

    @Test func deletingNonexistentPresetReturnsPresetNotFound() {
        let preset = makePreset()
        let presets = makePresetContext(preset) // プリセットは1件のみ
        let idle = TimerContext.idle(now: referenceDate)

        let result = TimerEngine.reduce(action: .deletePreset(id: "missing"), context: idle, presets: presets, now: referenceDate)

        guard case let .failure(failure) = result else {
            Issue.record("存在しない ID の削除は拒否されるべき")
            return
        }
        #expect(failure.error == .presetNotFound, "存在しない ID には cannotDeleteLastPreset ではなく presetNotFound を返すべき")
    }
}

// MARK: - レビュー指摘の再現テスト

@Suite("レビュー指摘 (2026-08-25)")
struct ReviewFixTests {
    // 1. uniqueName の無限ループ: 30文字ちょうどの名前を複製するとハングしていた。
    @Test func duplicatePresetOfMaxLengthNameDoesNotHangAndStaysWithinLimit() {
        let longName = String(repeating: "あ", count: 30)
        let preset = makePreset(id: "long", name: longName)
        let presets = makePresetContext(preset)

        let semaphore = DispatchSemaphore(value: 0)
        let box = NameResultBox()
        DispatchQueue.global().async {
            let name = TimerEngine.uniqueName(base: longName, in: presets)
            box.value = name
            semaphore.signal()
        }
        let timedOut = semaphore.wait(timeout: .now() + 2) == .timedOut
        #expect(!timedOut, "uniqueName は30文字ちょうどの名前でハングしてはならない")
        guard !timedOut, let result = box.value else { return }
        #expect(result.count <= 30)
        #expect(result != longName, "連番が付与され、元の名前と異なるべき")
    }

    // 2. reduce が拒否時に tick() の Effect を捨てる。
    @Test func rejectedActionAfterBreakFinishesStillSurfacesCommitLog() throws {
        let preset = makePreset(short: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startBreak(type: .shortBreak, presetId: preset.id), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!

        // pause は IDLE では受理されないが、reduce 内部の tick() が休憩を先に確定させている。
        let result = TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: endAt)

        guard case let .failure(failure) = result else {
            Issue.record("拒否されるはずが成功した")
            return
        }
        #expect(failure.error == .invalidStateForAction)
        #expect(failure.effects.count == 1, "REQ-LOG-018: tick が確定させた commitLog を拒否時にも返さなければならない")
    }

    // 3. confirmRestoredSession(.discard) が放置時間を実経過時間に混入させる。
    @Test func discardAfterLongPauseExcludesIdleTimeFromElapsed() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let pauseTime = referenceDate.addingTimeInterval(600) // 10分作業してから一時停止
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: pauseTime).get()

        let resumeAttemptTime = pauseTime.addingTimeInterval(13 * 3600) // 13時間放置 (idleResetHours=12 を超過)
        let resumed = try TimerEngine.reduce(action: .resume, context: paused.context, presets: presets, now: resumeAttemptTime).get()
        #expect(resumed.context.runState == .pendingDecision)
        let pending = try #require(resumed.context.pendingDecision)
        #expect(pending.elapsedSeconds == 600)

        let discardTime = resumeAttemptTime.addingTimeInterval(5)
        let discarded = try TimerEngine.reduce(action: .confirmRestoredSession(.discard), context: resumed.context, presets: presets, now: discardTime).get()

        guard case let .commitLog(entry)? = discarded.effects.first else {
            Issue.record("commitLog effect が見つからない")
            return
        }
        #expect(entry.elapsedSeconds == 600, "REQ-PER-004: 放置していた13時間を実経過時間に含めてはならない")
    }

    // 4. committedAt が確定処理でも常に nil のまま。
    @Test func finalizeSetsCommittedAtAndIsIdempotentOnReuse() throws {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        let (firstContext, firstEffects) = TimerEngine.finalize(context: finished, presets: presets, settings: .default, now: endAt.addingTimeInterval(30), outcome: .aborted)
        #expect(firstEffects.count == 1)
        #expect(firstContext.committedAt != nil, "REQ-LOG-019: 確定に成功したら committedAt を設定する")

        // 同じ「確定済み」コンテキストを誤って再度 finalize しても、二重に commitLog を出してはならない。
        let (secondContext, secondEffects) = TimerEngine.finalize(context: firstContext, presets: presets, settings: .default, now: endAt.addingTimeInterval(60), outcome: .aborted)
        #expect(secondEffects.isEmpty, "committedAt が設定済みのコンテキストを再確定してはならない")
        #expect(secondContext == firstContext)
    }
}

private final class NameResultBox: @unchecked Sendable {
    var value: String?
}

// MARK: - Result helper

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
