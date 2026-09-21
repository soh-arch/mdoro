import Testing
import Foundation
@testable import MdoroCore

// MARK: - Test helpers

private func makePreset(
    id: String = "preset-1",
    name: String = "Standard",
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

private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000) // A fixed instant. Only relative seconds are checked.

// MARK: - 4.6 State transition matrix

@Suite("State transition matrix (4.6)")
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
        // pause is not accepted in IDLE.
        let result = TimerEngine.reduce(action: .pause, context: context, presets: presets, now: referenceDate)
        #expect(result == .failure(TimerFailure(error: .invalidStateForAction, effects: [])))
    }
}

// MARK: - Loop count and nextSessionType

@Suite("Loop count and nextSessionType (4.3 / 4.4)")
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
        // REQ-TIM-015: when loopCount is 0, the multiple check must not lead to LONG_BREAK.
        let next = TimerEngine.standardNextSessionType(after: .shortBreak, loopCount: 0, longBreakInterval: 1)
        #expect(next == .work)
    }

    @Test func resetLoopCountImmediatelySuggestsWork() throws {
        let preset = makePreset(interval: 1) // the setting most likely to produce LONG_BREAK
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let finishTime = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: started.presets, now: finishTime).context
        #expect(finished.loopCount == 1)

        let reset = try TimerEngine.reduce(action: .resetLoopCount, context: finished, presets: presets, now: finishTime.addingTimeInterval(10)).get()
        #expect(reset.context.loopCount == 0)
        #expect(reset.context.nextSessionType == .work, "REQ-TIM-015: must not suggest LONG_BREAK right after a reset")
    }
}

// MARK: - Extending, and taking a loop back from FINISHED

@Suite("Extend and undo from FINISHED (4.7)")
struct ExtendAndFinishedTests {
    @Test func extendFromFinishedDecrementsLoopAndReturnsToRunning() throws {
        let preset = makePreset(interval: 4)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context
        #expect(finished.loopCount == 1)

        let extendTime = endAt.addingTimeInterval(30) // within the grace (REQ-TIM-043: one minute)
        let extended = try TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: extendTime).get()

        #expect(extended.context.runState == .running)
        #expect(extended.context.loopCount == 0, "REQ-TIM-042: extending takes the loop count back by one")
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

        let abortTime = endAt.addingTimeInterval(30)
        let aborted = try TimerEngine.reduce(action: .abort, context: finished, presets: presets, now: abortTime).get()

        #expect(aborted.context.loopCount == 0, "REQ-TIM-036: aborting from FINISHED also takes the loop count back by one")
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
        // Past the grace, tick() commits first and moves to IDLE, so the matrix rejects extend.
        // Even when it is rejected, the commitLog tick() produced must not be lost (REQ-LOG-018).
        guard case let .failure(failure) = afterResult else {
            Issue.record("extend past the grace was accepted")
            return
        }
        #expect(failure.error == .invalidStateForAction)
        #expect(failure.effects.count == 1)
    }
}

// MARK: - Committing is idempotent (REQ-LOG-019)

@Suite("Committing is idempotent")
struct CommitIdempotencyTests {
    @Test func breakFinishedCommitsExactlyOnce() throws {
        let preset = makePreset(short: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startBreak(type: .shortBreak, presetId: preset.id), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!

        let firstTick = TimerEngine.tick(context: started.context, presets: presets, now: endAt)
        #expect(firstTick.context.runState == .idle, "REQ-TIM-044: a break commits immediately, with no grace period")
        #expect(firstTick.effects.count == 1)

        let secondTick = TimerEngine.tick(context: firstTick.context, presets: presets, now: endAt.addingTimeInterval(120))
        #expect(secondTick.effects.isEmpty, "an already committed session must not be committed again")
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

        // Repeating the same action on the committed context: the matrix rejects abort in IDLE.
        let secondAbort = TimerEngine.reduce(action: .abort, context: firstAbort.context, presets: presets, now: abortTime.addingTimeInterval(5))
        #expect(secondAbort == .failure(TimerFailure(error: .invalidStateForAction, effects: [])))
    }

    @Test func startWorkResetAbortAllFinalizeOnlyOnceFromFinished() throws {
        // CLAUDE.md: check, as three independent scenarios, that aborting, starting the next
        // session, and resetting while a break sits in FINISHED do not record twice.
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
            #expect(reduction.effects.count == 1, "trigger=\(trigger) must commit exactly once")
        }
    }
}

// MARK: - Net elapsed time (REQ-TIM-005)

@Suite("Net elapsed time across a pause")
struct NetWorkingTimeTests {
    @Test func pauseIsExcludedFromElapsedSeconds() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)

        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let pauseTime = referenceDate.addingTimeInterval(300) // pause after five minutes have passed
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: pauseTime).get()
        #expect(paused.context.remainingSeconds == 1200)

        let resumeTime = pauseTime.addingTimeInterval(600) // paused for ten minutes
        let resumed = try TimerEngine.reduce(action: .resume, context: paused.context, presets: presets, now: resumeTime).get()
        #expect(resumed.context.accumulatedPausedSeconds == 600)

        let endAt = resumed.context.sessionEndAt!
        #expect(endAt == resumeTime.addingTimeInterval(1200))

        // Abort exactly at the end time, within the grace, and check the net elapsed time of
        // the log that gets committed.
        let ticked = TimerEngine.tick(context: resumed.context, presets: presets, now: endAt)
        let aborted = try TimerEngine.reduce(action: .abort, context: ticked.context, presets: presets, now: endAt).get()

        guard case let .commitLog(entry)? = aborted.effects.first else {
            Issue.record("no commitLog effect was produced")
            return
        }
        #expect(entry.elapsedSeconds == 25 * 60, "the 10-minute pause must be excluded, leaving a net 25 minutes")
    }
}

// MARK: - 9.5 When a settings change takes effect (groups A/B/C)

@Suite("When a settings change takes effect (9.5)")
struct SettingsApplicationTests {
    @Test func groupAChangeDoesNotAlterRunningSessionEndAt() throws {
        let preset = makePreset(work: 25 * 60)
        var presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let originalEndAt = started.context.sessionEndAt

        var updated = preset
        updated.workSeconds = 40 * 60 // group A: changing a duration
        let result = try TimerEngine.reduce(action: .updatePreset(updated), context: started.context, presets: started.presets, now: referenceDate.addingTimeInterval(10)).get()
        presets = result.presets

        #expect(result.context.sessionEndAt == originalEndAt, "REQ-CFG-003: must not change sessionEndAt of a running session")
        #expect(result.context.presetEditedDuringSession == true, "REQ-CFG-017")
        #expect(presets.preset(id: preset.id)?.workSeconds == 40 * 60)
    }

    @Test func groupBChangeAppliesImmediatelyToExtend() throws {
        let preset = makePreset(extend: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        var updated = preset
        updated.extendSeconds = 10 * 60 // group B
        let afterUpdate = try TimerEngine.reduce(action: .updatePreset(updated), context: started.context, presets: presets, now: referenceDate.addingTimeInterval(5)).get()

        let beforeExtend = afterUpdate.context.sessionEndAt!
        // REQ-TIM-046: an extension is only accepted with five minutes or less remaining, so
        // move forward into the acceptance window.
        let withinWindow = beforeExtend.addingTimeInterval(-60)
        let extended = try TimerEngine.reduce(action: .extend, context: afterUpdate.context, presets: afterUpdate.presets, now: withinWindow).get()

        #expect(extended.context.sessionEndAt == beforeExtend.addingTimeInterval(10 * 60), "REQ-CFG-015: group B applies to the running session immediately")
    }

    @Test func outOfRangePresetUpdateIsRejected() {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)

        var invalid = preset
        invalid.workSeconds = 999_999 // REQ-CFG-018: out of range
        let result = TimerEngine.reduce(action: .updatePreset(invalid), context: idle, presets: presets, now: referenceDate)
        #expect(result == .failure(TimerFailure(error: .settingOutOfRange, effects: [])))
    }

    @Test func deletingNonexistentPresetReturnsPresetNotFound() {
        let preset = makePreset()
        let presets = makePresetContext(preset) // only one preset exists
        let idle = TimerContext.idle(now: referenceDate)

        let result = TimerEngine.reduce(action: .deletePreset(id: "missing"), context: idle, presets: presets, now: referenceDate)

        guard case let .failure(failure) = result else {
            Issue.record("deleting an id that does not exist was accepted")
            return
        }
        #expect(failure.error == .presetNotFound, "an unknown id must return presetNotFound, not cannotDeleteLastPreset")
    }
}

// MARK: - Reproducing the review findings

@Suite("Review findings (2026-08-25)")
struct ReviewFixTests {
    // uniqueName: duplicating a name of exactly 30 characters must not spin forever.
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
        #expect(!timedOut, "uniqueName must not hang on a name already at the 30-character limit")
        guard !timedOut, let result = box.value else { return }
        #expect(result.count <= 30)
        #expect(result != longName, "a number must be appended, so the result differs from the original name")
    }

    // 2. reduce throws away the Effect from tick() when it rejects.
    @Test func rejectedActionAfterBreakFinishesStillSurfacesCommitLog() throws {
        let preset = makePreset(short: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startBreak(type: .shortBreak, presetId: preset.id), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!

        // pause is not accepted in IDLE, but tick() inside reduce has already committed the break.
        let result = TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: endAt)

        guard case let .failure(failure) = result else {
            Issue.record("the action succeeded instead of being rejected")
            return
        }
        #expect(failure.error == .invalidStateForAction)
        #expect(failure.effects.count == 1, "REQ-LOG-018: a commitLog produced by tick must survive a rejected action")
    }

    // 3. confirmRestoredSession(.discard) lets the idle hours leak into the net elapsed time.
    @Test func discardAfterLongPauseExcludesIdleTimeFromElapsed() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()

        let pauseTime = referenceDate.addingTimeInterval(600) // pause after ten minutes of work
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: pauseTime).get()

        let resumeAttemptTime = pauseTime.addingTimeInterval(13 * 3600) // left for 13 hours (past idleResetHours=12)
        let resumed = try TimerEngine.reduce(action: .resume, context: paused.context, presets: presets, now: resumeAttemptTime).get()
        #expect(resumed.context.runState == .pendingDecision)
        let pending = try #require(resumed.context.pendingDecision)
        #expect(pending.elapsedSeconds == 600)

        let discardTime = resumeAttemptTime.addingTimeInterval(5)
        let discarded = try TimerEngine.reduce(action: .confirmRestoredSession(.discard), context: resumed.context, presets: presets, now: discardTime).get()

        guard case let .commitLog(entry)? = discarded.effects.first else {
            Issue.record("no commitLog effect was produced")
            return
        }
        #expect(entry.elapsedSeconds == 600, "REQ-PER-004: the 13 idle hours must not count toward elapsed time")
    }

    // 4. committedAt stays nil even when a session is committed.
    @Test func finalizeSetsCommittedAtAndIsIdempotentOnReuse() throws {
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        let (firstContext, firstEffects) = TimerEngine.finalize(context: finished, presets: presets, settings: .default, now: endAt.addingTimeInterval(30), outcome: .aborted)
        #expect(firstEffects.count == 1)
        #expect(firstContext.committedAt != nil, "REQ-LOG-019: a successful commit must set committedAt")

        // Calling finalize again by mistake on the same already-committed context must not emit
        // a second commitLog.
        let (secondContext, secondEffects) = TimerEngine.finalize(context: firstContext, presets: presets, settings: .default, now: endAt.addingTimeInterval(60), outcome: .aborted)
        #expect(secondEffects.isEmpty, "a context that already has committedAt must not commit again")
        #expect(secondContext == firstContext)
    }
}

// MARK: - Extend acceptance window (REQ-TIM-046)

@Suite("Extend acceptance window (REQ-TIM-046)")
struct ExtensionWindowTests {
    @Test func runningOutsideWindowIsRejectedAndInsideIsAccepted() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!

        // Earlier than exactly five minutes remaining is not accepted.
        let tooEarly = endAt.addingTimeInterval(-(TimerEngine.extensionWindowSeconds + 1))
        guard case let .failure(failure) = TimerEngine.reduce(action: .extend, context: started.context, presets: presets, now: tooEarly) else {
            Issue.record("REQ-TIM-046: extend earlier than five minutes remaining was accepted")
            return
        }
        #expect(failure.error == .extendWindowClosed)

        // Exactly five minutes remaining is the boundary, and is accepted.
        let boundary = endAt.addingTimeInterval(-TimerEngine.extensionWindowSeconds)
        let accepted = try TimerEngine.reduce(action: .extend, context: started.context, presets: presets, now: boundary).get()
        #expect(accepted.context.sessionEndAt == endAt.addingTimeInterval(TimeInterval(preset.extendSeconds)),
                "REQ-TIM-040: the extension is added to sessionEndAt, not to the current time")
    }

    @Test func extendAnchorIsSessionEndNotPressTime() throws {
        let preset = makePreset(work: 25 * 60, extend: 5 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        // At 10 seconds after the end or at 55, the new end time is the same.
        let early = try TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: endAt.addingTimeInterval(10)).get()
        let late = try TimerEngine.reduce(action: .extend, context: finished, presets: presets, now: endAt.addingTimeInterval(55)).get()
        #expect(early.context.sessionEndAt == endAt.addingTimeInterval(5 * 60))
        #expect(early.context.sessionEndAt == late.context.sessionEndAt, "REQ-TIM-040: the result must not depend on when the button was pressed")
    }

    @Test func pausedOutsideWindowIsRejected() throws {
        let preset = makePreset(work: 25 * 60)
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: referenceDate.addingTimeInterval(60)).get()
        #expect(paused.context.remainingSeconds ?? 0 > Int(TimerEngine.extensionWindowSeconds))

        guard case let .failure(failure) = TimerEngine.reduce(action: .extend, context: paused.context, presets: presets, now: referenceDate.addingTimeInterval(61)) else {
            Issue.record("REQ-TIM-046: extend while PAUSED with more than five minutes remaining was accepted")
            return
        }
        #expect(failure.error == .extendWindowClosed)

        var nearEnd = paused.context
        nearEnd.remainingSeconds = 120
        let accepted = try TimerEngine.reduce(action: .extend, context: nearEnd, presets: presets, now: referenceDate.addingTimeInterval(61)).get()
        #expect(accepted.context.remainingSeconds == 120 + preset.extendSeconds, "REQ-TIM-040: while PAUSED the extension is added to remainingSeconds")
    }

    @Test func finishedWindowIsOneMinute() throws {
        #expect(TimerEngine.extensionGraceSeconds == 60, "REQ-TIM-043: the grace period is one minute")
        let preset = makePreset()
        let presets = makePresetContext(preset)
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(action: .startWork(presetId: preset.id, taskSnapshot: nil), context: idle, presets: presets, now: referenceDate).get()
        let endAt = started.context.sessionEndAt!
        let finished = TimerEngine.tick(context: started.context, presets: presets, now: endAt).context

        #expect(TimerEngine.isWithinExtensionWindow(finished, now: endAt.addingTimeInterval(60)))
        #expect(!TimerEngine.isWithinExtensionWindow(finished, now: endAt.addingTimeInterval(61)))
    }
}

// MARK: - A pause with no remainder (REQ-TIM-002)

// REQ-TIM-002 makes PAUSED hold the remainder of the session in remainingSeconds, so a pause without
// one is a state the spec forbids. These tests pin down what happens if it turns up anyway: nothing is
// invented in its place. Every refusal below is paired with the same call on a sound pause, so that an
// implementation which simply turns everything away cannot pass.
@Suite("A pause with no remainder (REQ-TIM-002)")
struct PauseWithoutRemainderTests {
    private let preset = makePreset(work: 25 * 60, extend: 5 * 60)
    private var presets: PresetContext { makePresetContext(preset) }
    private var pauseTime: Date { referenceDate.addingTimeInterval(60) }

    // A sound pause, one minute into a 25-minute session: 24 minutes remain.
    private func soundPause() throws -> TimerContext {
        let idle = TimerContext.idle(now: referenceDate)
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: preset.id, taskSnapshot: nil),
            context: idle, presets: presets, now: referenceDate
        ).get()
        let paused = try TimerEngine.reduce(action: .pause, context: started.context, presets: presets, now: pauseTime).get()
        #expect(paused.context.runState == .paused)
        #expect(paused.context.remainingSeconds == 24 * 60)
        return paused.context
    }

    // The same pause with the remainder gone — the state REQ-TIM-002 forbids.
    private func pauseWithoutRemainder() throws -> TimerContext {
        var broken = try soundPause()
        broken.remainingSeconds = nil
        return broken
    }

    // The long pause that raises a question, from which continueSession answers (REQ-TIM-033).
    private func pausedTooLongDecision() throws -> TimerContext {
        let sound = try soundPause()
        let asked = try TimerEngine.reduce(
            action: .resume, context: sound, presets: presets,
            now: pauseTime.addingTimeInterval(20 * 3600)
        ).get()
        #expect(asked.context.runState == .pendingDecision)
        #expect(asked.context.pendingDecision?.reason == .pausedTooLong)
        #expect(asked.context.remainingSeconds == 24 * 60, "entering PENDING_DECISION must not drop the remainder")
        return asked.context
    }

    // 1. The window cannot be measured without a remainder, so it counts as closed — the side the
    //    RUNNING and FINISHED branches already fall to.
    @Test func theExtensionWindowIsClosedWithoutARemainder() throws {
        let broken = try pauseWithoutRemainder()
        let now = pauseTime.addingTimeInterval(1)
        #expect(!TimerEngine.isWithinExtensionWindow(broken, now: now))

        // Paired sound case: a pause with two minutes left is inside the window.
        var nearEnd = try soundPause()
        nearEnd.remainingSeconds = 120
        #expect(TimerEngine.isWithinExtensionWindow(nearEnd, now: now))
    }

    // 2. REQ-TIM-046: outside the window, extend answers extendWindowClosed.
    @Test func extendingAPauseWithoutARemainderIsRefused() throws {
        let broken = try pauseWithoutRemainder()
        let now = pauseTime.addingTimeInterval(1)

        switch TimerEngine.reduce(action: .extend, context: broken, presets: presets, now: now) {
        case let .success(reduction):
            Issue.record("REQ-TIM-046: extend on a pause with no remainder was accepted, leaving remainingSeconds=\(String(describing: reduction.context.remainingSeconds))")
        case let .failure(failure):
            #expect(failure.error == .extendWindowClosed)
        }

        // Paired sound case: a pause inside the window still takes the extension on its remainder.
        var nearEnd = try soundPause()
        nearEnd.remainingSeconds = 120
        let extended = try TimerEngine.reduce(action: .extend, context: nearEnd, presets: presets, now: now).get()
        #expect(extended.context.remainingSeconds == 120 + preset.extendSeconds)
        #expect(extended.context.extendedSeconds == preset.extendSeconds)
        #expect(extended.context.runState == .paused)
    }

    // 3. Resuming needs the remainder to recalculate the end time (REQ-TIM-002). Without it the action
    //    is refused, and no end time is written.
    @Test func resumingAPauseWithoutARemainderIsRefused() throws {
        let broken = try pauseWithoutRemainder()
        let resumeAt = pauseTime.addingTimeInterval(120)
        let endAtBefore = broken.sessionEndAt

        switch TimerEngine.reduce(action: .resume, context: broken, presets: presets, now: resumeAt) {
        case let .success(reduction):
            // An end time of "now" is the same shape as a session that has just ended: the next tick()
            // takes it for an end that has arrived.
            let followUp = TimerEngine.tick(context: reduction.context, presets: presets, now: resumeAt)
            Issue.record("resume with no remainder was accepted: sessionEndAt=\(String(describing: reduction.context.sessionEndAt)) at now=\(resumeAt), and the next tick reached \(followUp.context.runState) with loopCount \(followUp.context.loopCount) and \(followUp.effects.count) effects")
        case let .failure(failure):
            #expect(failure.error == .invalidStateForAction)
            #expect(failure.effects.isEmpty, "a refused resume commits nothing")
            #expect(broken.sessionEndAt == endAtBefore, "no end time is written on the way out")
        }

        // Paired sound case: a normal resume still recalculates the end time from now + the remainder.
        // (NetWorkingTimeTests.pauseIsExcludedFromElapsedSeconds covers the elapsed-time side of this.)
        let sound = try soundPause()
        let resumed = try TimerEngine.reduce(action: .resume, context: sound, presets: presets, now: resumeAt).get()
        #expect(resumed.context.runState == .running)
        #expect(resumed.context.sessionEndAt == resumeAt.addingTimeInterval(24 * 60))
        #expect(resumed.context.remainingSeconds == nil)
        #expect(resumed.context.pausedAt == nil)
        #expect(resumed.context.accumulatedPausedSeconds == 120)
    }

    // 4. The same for the answer that continues a session the app asked about (REQ-TIM-033).
    @Test func continuingARestoredSessionWithoutARemainderIsRefused() throws {
        var broken = try pausedTooLongDecision()
        broken.remainingSeconds = nil
        let answerAt = pauseTime.addingTimeInterval(20 * 3600 + 30)
        let endAtBefore = broken.sessionEndAt

        switch TimerEngine.reduce(action: .confirmRestoredSession(.continueSession), context: broken, presets: presets, now: answerAt) {
        case let .success(reduction):
            Issue.record("continueSession with no remainder was accepted: sessionEndAt=\(String(describing: reduction.context.sessionEndAt)) at now=\(answerAt)")
        case let .failure(failure):
            #expect(failure.error == .invalidStateForAction)
            #expect(broken.sessionEndAt == endAtBefore, "no end time is written on the way out")
        }

        // Paired sound case: with the remainder in hand the session picks up where it was left.
        let sound = try pausedTooLongDecision()
        let continued = try TimerEngine.reduce(action: .confirmRestoredSession(.continueSession), context: sound, presets: presets, now: answerAt).get()
        #expect(continued.context.runState == .running)
        #expect(continued.context.sessionEndAt == answerAt.addingTimeInterval(24 * 60))
        #expect(continued.context.remainingSeconds == nil)
        #expect(continued.context.pausedAt == nil)
        #expect(continued.context.pendingDecision == nil)
        #expect(continued.context.committedAt == nil, "continuing writes no log line")
    }

    // The branch that never reads the remainder is left alone: a pause held too long still turns into a
    // question rather than a refusal, so the session can still be completed or discarded.
    @Test func aLongPauseWithoutARemainderStillAsks() throws {
        let broken = try pauseWithoutRemainder()
        let resumed = try TimerEngine.reduce(
            action: .resume, context: broken, presets: presets,
            now: pauseTime.addingTimeInterval(20 * 3600)
        ).get()
        #expect(resumed.context.runState == .pendingDecision)
        #expect(resumed.context.pendingDecision?.reason == .pausedTooLong)
    }
}

// MARK: - Pre-notifications (REQ-NTF-020–023)

@Suite("Pre-notification triggers (REQ-NTF-020–023)")
struct PreNotificationTests {
    private let start = referenceDate
    private var end: Date { referenceDate.addingTimeInterval(25 * 60) }

    @Test func validRangesFollowTheApprovedGrid() {
        // REQ-NTF-020: remaining time is 1–15 minutes in steps of 1; elapsed percent is 50–95%
        // in steps of 5.
        #expect(PreNotification.beforeEnd(seconds: 60).isWithinValidRanges)
        #expect(PreNotification.beforeEnd(seconds: 15 * 60).isWithinValidRanges)
        #expect(!PreNotification.beforeEnd(seconds: 30).isWithinValidRanges)
        #expect(!PreNotification.beforeEnd(seconds: 16 * 60).isWithinValidRanges)
        #expect(!PreNotification.beforeEnd(seconds: 90).isWithinValidRanges, "only whole minutes are valid")

        #expect(PreNotification.atElapsedPercent(50).isWithinValidRanges)
        #expect(PreNotification.atElapsedPercent(95).isWithinValidRanges)
        #expect(!PreNotification.atElapsedPercent(45).isWithinValidRanges)
        #expect(!PreNotification.atElapsedPercent(100).isWithinValidRanges)
        #expect(!PreNotification.atElapsedPercent(82).isWithinValidRanges, "only multiples of 5 percent are valid")
    }

    @Test func presetRejectsMoreThanTwoTriggersOrOutOfRangeValues() {
        var preset = makePreset()
        preset.preNotifications = [.beforeEnd(seconds: 300), .atElapsedPercent(80)]
        #expect(preset.isWithinValidRanges())

        preset.preNotifications = [.beforeEnd(seconds: 300), .atElapsedPercent(80), .atElapsedPercent(90)]
        #expect(!preset.isWithinValidRanges(), "REQ-NTF-020: at most two triggers")

        preset.preNotifications = [.atElapsedPercent(82)]
        #expect(!preset.isWithinValidRanges())
    }

    @Test func triggerBeforeSessionStartIsDropped() {
        // REQ-NTF-021: "30 minutes before the end" does not hold for a 25-minute session.
        let dates = PreNotificationSchedule.fireDates(
            for: [.beforeEnd(seconds: 30 * 60)],
            sessionStartedAt: start, sessionEndAt: end, now: start
        )
        #expect(dates.isEmpty)
    }

    @Test func elapsedPercentFollowsTheExtendedDuration() {
        // REQ-NTF-022: after an extension, recalculate against the new end time.
        let before = PreNotificationSchedule.fireDates(
            for: [.atElapsedPercent(80)], sessionStartedAt: start, sessionEndAt: end, now: start
        )
        #expect(before == [start.addingTimeInterval(20 * 60)])

        let extendedEnd = end.addingTimeInterval(5 * 60)
        let after = PreNotificationSchedule.fireDates(
            for: [.atElapsedPercent(80)], sessionStartedAt: start, sessionEndAt: extendedEnd, now: start
        )
        #expect(after == [start.addingTimeInterval(24 * 60)])
    }

    @Test func alreadyElapsedTriggerIsNotRescheduled() {
        // REQ-NTF-022: a trigger that has already fired is not fired again.
        let dates = PreNotificationSchedule.fireDates(
            for: [.atElapsedPercent(50), .beforeEnd(seconds: 60)],
            sessionStartedAt: start, sessionEndAt: end,
            now: start.addingTimeInterval(20 * 60)
        )
        #expect(dates == [end.addingTimeInterval(-60)])
    }

    @Test func closeTriggersCollapseToTheLaterOne() {
        // REQ-NTF-023: when two come within 60 seconds of each other, only the later one.
        // 80% of 25 minutes = 20 minutes elapsed = 5 minutes left. That coincides with
        // "5 minutes before the end", so only the later one survives.
        let dates = PreNotificationSchedule.fireDates(
            for: [.atElapsedPercent(80), .beforeEnd(seconds: 5 * 60)],
            sessionStartedAt: start, sessionEndAt: end, now: start
        )
        #expect(dates.count == 1)
        #expect(dates == [start.addingTimeInterval(20 * 60)])

        // Far enough apart, and both survive.
        let spread = PreNotificationSchedule.fireDates(
            for: [.atElapsedPercent(50), .beforeEnd(seconds: 60)],
            sessionStartedAt: start, sessionEndAt: end, now: start
        )
        #expect(spread.count == 2)
    }

    @Test func codableRoundTripKeepsTheTriggerShape() throws {
        let triggers: [PreNotification] = [.beforeEnd(seconds: 600), .atElapsedPercent(85)]
        let data = try JSONEncoder().encode(triggers)
        #expect(try JSONDecoder().decode([PreNotification].self, from: data) == triggers)
    }
}

// MARK: - The default the `Standard` preset carries (REQ-PRS-010 / SPEC 9.4)

@Suite("A preset starts with Time Sensitive notifications on (REQ-PRS-010 / SPEC 9.4)")
struct TimeSensitiveDefaultTests {

    // REQ-PRS-010: the value pinned here is the one the table of the `Standard` preset carries
    // (SPEC 9.4). REQ-NTF-005 asks for notifications to be sent as Time Sensitive and for the user
    // to be able to turn that off, and it says nothing about what the user starts from.
    //
    // ⚠ **Reading the default out of that clause has been tried, and the three did not agree.**
    // The table did not carry it, the clause never did, and the implementation started from `false`;
    // none of the three pointed at another, so no one noticed. SPEC 9.4 records it, and `Preset.swift`
    // carries the same note at the initialiser where the value is decided.
    //
    // ⚠ **This is what the preset asks for, not what the OS delivers.** `.timeSensitive` needs the
    // "Time Sensitive Notifications" capability, which this signature does not have and cannot get
    // on a free Apple Account (`docs/platform/0016`). The schedulers carry that note; this suite
    // only pins the value the app starts from.
    @Test func theStandardPresetStartsWithItOn() {
        #expect(Preset.standard().timeSensitiveNotifications)
    }

    // The initialiser's default is the single place this is decided: `standard()`, the settings
    // screen's "new preset" and `restoreDefaultPreset` all reach it by not passing the argument.
    @Test func aPresetMadeWithoutNamingTheSettingStartsWithItOn() {
        #expect(makePreset().timeSensitiveNotifications)
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
