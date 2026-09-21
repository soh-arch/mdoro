import Testing
import Foundation
@testable import MdoroCore

// REQ-TIM-040 puts the anchor of an extension at the session's scheduled end time, and REQ-TIM-002 makes
// a pause hold the remainder measured from that same end time. A session in RUNNING or FINISHED with no
// `sessionEndAt` is therefore a state the spec does not describe. These tests pin down what happens if it
// turns up anyway: the action is refused, and no end time and no remainder is invented in its place.
//
// The difference from the remainder cases already covered in `PauseWithoutRemainderTests` is what the
// invented value would do next. Those branches read a missing value; these two **write** one — and
// `finalize()` reads a completed session's end from finishedAt, falling back to sessionEndAt, then hands
// it to `MdoroLog.md`, a file only ever added to (Decision 0002). Once a fabricated end time is on disk
// there is no correcting it.
//
// Every refusal below is paired with the same call on a sound session, so that an implementation which
// simply turns everything away cannot pass.
@Suite("An extension does not invent an end (REQ-TIM-040 / REQ-TIM-002)")
struct AnExtensionDoesNotInventAnEndTests {
    private let preset = Preset(
        id: "preset-anchor",
        name: "Standard",
        workSeconds: 25 * 60,
        shortBreakSeconds: 5 * 60,
        longBreakSeconds: 15 * 60,
        longBreakInterval: 4,
        extendSeconds: 5 * 60
    )
    private var presets: PresetContext { PresetContext(presets: [preset], activePresetId: preset.id) }
    private let start = Date(timeIntervalSince1970: 1_700_000_000) // A fixed instant. Only relative seconds are checked.

    // A sound WORK session, RUNNING, 25 minutes long.
    private func runningSession() throws -> TimerContext {
        let idle = TimerContext.idle(now: start)
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: preset.id, taskSnapshot: nil),
            context: idle, presets: presets, now: start
        ).get()
        let isRunning = started.context.runState == .running
        #expect(isRunning)
        let endsWhenItShould = started.context.sessionEndAt == start.addingTimeInterval(25 * 60)
        #expect(endsWhenItShould)
        return started.context
    }

    // The same session with the end time gone — the state the spec does not describe.
    private func runningWithoutAnEnd() throws -> TimerContext {
        var broken = try runningSession()
        broken.sessionEndAt = nil
        return broken
    }

    // The same session having reached FINISHED at its end time, one loop counted.
    private func finishedSession() throws -> TimerContext {
        let running = try runningSession()
        let finished = TimerEngine.tick(
            context: running, presets: presets,
            now: start.addingTimeInterval(25 * 60)
        ).context
        let isFinished = finished.runState == .finished
        #expect(isFinished)
        let countedTheLoop = finished.loopCount == 1
        #expect(countedTheLoop)
        return finished
    }

    // FINISHED keeps both timestamps; only the end time is taken away. The extension window for FINISHED
    // is measured from `finishedAt` (REQ-TIM-046), so this context passes the window check.
    private func finishedWithoutAnEnd() throws -> TimerContext {
        var broken = try finishedSession()
        broken.sessionEndAt = nil
        let stillKnowsWhenItFinished = broken.finishedAt == start.addingTimeInterval(25 * 60)
        #expect(stillKnowsWhenItFinished)
        return broken
    }

    // 1. REQ-TIM-002: the remainder a pause holds is measured from the end time. With none, the pause is
    //    refused rather than recorded as a remainder of zero — which is what "now − now" comes to.
    @Test func pausingASessionWithNoEndTimeIsRefused() throws {
        let broken = try runningWithoutAnEnd()
        let pauseTime = start.addingTimeInterval(60)

        switch TimerEngine.reduce(action: .pause, context: broken, presets: presets, now: pauseTime) {
        case let .success(reduction):
            Issue.record(
                "REQ-TIM-002: pausing a session with no end time was accepted, leaving remainingSeconds=\(String(describing: reduction.context.remainingSeconds))"
            )
        case let .failure(failure):
            let refused = failure.error == .invalidStateForAction
            #expect(refused, "got \(failure.error)")
        }

        // Paired sound case: one minute into a 25-minute session, 24 minutes are held.
        let sound = try runningSession()
        let paused = try TimerEngine.reduce(action: .pause, context: sound, presets: presets, now: pauseTime).get()
        let isPaused = paused.context.runState == .paused
        #expect(isPaused)
        let heldTheRemainder = paused.context.remainingSeconds == 24 * 60
        #expect(heldTheRemainder, "got \(String(describing: paused.context.remainingSeconds))")
        let noteWhenItPaused = paused.context.pausedAt == pauseTime
        #expect(noteWhenItPaused)
    }

    // 2. The remainder is still rounded up, as the display rounds. Truncating would take a second off the
    //    remainder the instant the timer was paused.
    @Test func theRemainderIsStillRoundedUp() throws {
        let sound = try runningSession()
        let pauseTime = start.addingTimeInterval(60.4) // 1439.6 seconds left
        let paused = try TimerEngine.reduce(action: .pause, context: sound, presets: presets, now: pauseTime).get()
        let roundedUp = paused.context.remainingSeconds == 1440
        #expect(roundedUp, "got \(String(describing: paused.context.remainingSeconds))")
    }

    // 3. REQ-TIM-040: the extension is added to the scheduled end time. A FINISHED session with none is
    //    refused — the window check reads `finishedAt` and lets it through, so this is the first door and
    //    not the second.
    @Test func extendingAFinishedSessionWithNoEndTimeIsRefused() throws {
        let broken = try finishedWithoutAnEnd()
        let extendTime = start.addingTimeInterval(25 * 60 + 30) // within the grace (REQ-TIM-043: one minute)

        // The window is open: nothing here is being turned away for being late.
        let windowIsOpen = TimerEngine.isWithinExtensionWindow(broken, now: extendTime)
        #expect(windowIsOpen, "REQ-TIM-046: the FINISHED window is measured from finishedAt")

        switch TimerEngine.reduce(action: .extend, context: broken, presets: presets, now: extendTime) {
        case let .success(reduction):
            Issue.record(
                "REQ-TIM-040: extending a FINISHED session with no end time was accepted, writing sessionEndAt=\(String(describing: reduction.context.sessionEndAt)) anchored on the press time \(extendTime)"
            )
        case let .failure(failure):
            let refused = failure.error == .invalidStateForAction
            #expect(refused, "got \(failure.error)")
        }

        // Paired sound case: the same extension on the same session, with its end time intact.
        let sound = try finishedSession()
        let extended = try TimerEngine.reduce(action: .extend, context: sound, presets: presets, now: extendTime).get()
        let backToRunning = extended.context.runState == .running
        #expect(backToRunning)
        let tookTheLoopBack = extended.context.loopCount == 0
        #expect(tookTheLoopBack, "REQ-TIM-042: extending takes the loop count back by one")
        let anchoredOnTheScheduledEnd = extended.context.sessionEndAt == start.addingTimeInterval(TimeInterval(25 * 60 + preset.extendSeconds))
        #expect(anchoredOnTheScheduledEnd, "got \(String(describing: extended.context.sessionEndAt))")
        let clearedFinishedAt = extended.context.finishedAt == nil
        #expect(clearedFinishedAt)
        let countedTheExtension = extended.context.extendedSeconds == preset.extendSeconds
        #expect(countedTheExtension)
    }

    // 4. REQ-TIM-040: the RUNNING branch keeps anchoring on the scheduled end time and not on the press
    //    time. The button is pressed with two minutes left — inside the window — and the new end is the
    //    old end plus the preset's extension, which is three minutes later than the press time plus it.
    @Test func extendingARunningSessionStillAnchorsToTheScheduledEnd() throws {
        let nearEnd = try runningSession()
        let scheduledEnd = start.addingTimeInterval(25 * 60)

        let pressTime = scheduledEnd.addingTimeInterval(-120) // two minutes left: inside the window
        let extended = try TimerEngine.reduce(action: .extend, context: nearEnd, presets: presets, now: pressTime).get()

        let stillRunning = extended.context.runState == .running
        #expect(stillRunning)
        let anchoredOnTheScheduledEnd = extended.context.sessionEndAt == scheduledEnd.addingTimeInterval(TimeInterval(preset.extendSeconds))
        #expect(anchoredOnTheScheduledEnd, "got \(String(describing: extended.context.sessionEndAt))")
        let notAnchoredOnThePress = extended.context.sessionEndAt != pressTime.addingTimeInterval(TimeInterval(preset.extendSeconds))
        #expect(notAnchoredOnThePress, "REQ-TIM-040: the press time is not the anchor")
        let countedTheExtension = extended.context.extendedSeconds == preset.extendSeconds
        #expect(countedTheExtension)
    }
}
