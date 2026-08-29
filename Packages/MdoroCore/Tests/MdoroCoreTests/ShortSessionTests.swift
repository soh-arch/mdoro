import Testing
import Foundation
@testable import MdoroCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func standardPresets() -> PresetContext {
    let p = Preset(id: "p", name: "Standard", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
                   longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
    return PresetContext(presets: [p], activePresetId: p.id)
}

private func hasCommitLog(_ effects: [Effect]) -> Bool {
    effects.contains { if case .commitLog = $0 { return true } else { return false } }
}

// REQ-TIM-032 / REQ-TIM-005: a session with less than 60 seconds of net working time is never
// recorded in the log. Both sides of the boundary are pinned.
@Suite("Too-short sessions are not recorded (REQ-TIM-032)")
struct ShortSessionTests {

    private func abort(after seconds: TimeInterval) throws -> [Effect] {
        let presets = standardPresets()
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: "p", taskSnapshot: "タスク"),
            context: .idle(now: t0), presets: presets, now: t0
        ).get()
        return try TimerEngine.reduce(
            action: .abort, context: started.context, presets: presets,
            now: t0.addingTimeInterval(seconds)
        ).get().effects
    }

    @Test func abortUnderSixtySecondsIsNotLogged() throws {
        #expect(!hasCommitLog(try abort(after: 6)))
        #expect(!hasCommitLog(try abort(after: 59)))
    }

    @Test func abortAtSixtySecondsIsLogged() throws {
        #expect(hasCommitLog(try abort(after: 60)))
        #expect(hasCommitLog(try abort(after: 61)))
    }

    // The committed mark is set whether or not anything was recorded. Without it there is a risk
    // of committing twice (REQ-LOG-019).
    @Test func shortSessionIsStillMarkedCommitted() throws {
        let presets = standardPresets()
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: "p", taskSnapshot: "タスク"),
            context: .idle(now: t0), presets: presets, now: t0
        ).get()
        let aborted = try TimerEngine.reduce(
            action: .abort, context: started.context, presets: presets,
            now: t0.addingTimeInterval(6)
        ).get()
        #expect(aborted.context.committedAt != nil)
        #expect(aborted.context.runState == .idle)
    }

    // Time spent paused does not count towards the net time (REQ-TIM-005).
    // 100 seconds on the wall clock, 70 of them stopped, leaves a net 30 and is never recorded.
    @Test func pausedTimeDoesNotCountTowardTheSixtySeconds() throws {
        let presets = standardPresets()
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: "p", taskSnapshot: "タスク"),
            context: .idle(now: t0), presets: presets, now: t0
        ).get()
        let paused = try TimerEngine.reduce(
            action: .pause, context: started.context, presets: presets, now: t0.addingTimeInterval(20)
        ).get()
        let resumed = try TimerEngine.reduce(
            action: .resume, context: paused.context, presets: presets, now: t0.addingTimeInterval(90)
        ).get()
        let aborted = try TimerEngine.reduce(
            action: .abort, context: resumed.context, presets: presets, now: t0.addingTimeInterval(100)
        ).get()
        #expect(!hasCommitLog(aborted.effects), "a net 30 seconds is under the threshold, so nothing is recorded")
    }
}

// Consistency of the display. If the remaining time jumps on a pause, what is moving stops being
// trustworthy.
@Suite("Pausing does not change the remaining time")
struct PauseRoundingTests {

    private func presets() -> PresetContext {
        let p = Preset(id: "p", name: "Standard", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
                       longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
        return PresetContext(presets: [p], activePresetId: p.id)
    }

    // The display rounds up. Were pausing to round down, a second would appear to go on the press.
    @Test func pauseKeepsTheDisplayedSecond() throws {
        let ctx = presets()
        for offsetMilliseconds in [0, 1, 250, 500, 999] {
            let started = try TimerEngine.reduce(
                action: .startWork(presetId: "p", taskSnapshot: nil),
                context: .idle(now: t0), presets: ctx, now: t0
            ).get().context
            let endAt = started.sessionEndAt!

            let pauseAt = t0.addingTimeInterval(10 + Double(offsetMilliseconds) / 1000)
            let displayedWhileRunning = Int(endAt.timeIntervalSince(pauseAt).rounded(.up))

            let paused = try TimerEngine.reduce(
                action: .pause, context: started, presets: ctx, now: pauseAt
            ).get().context

            #expect(paused.remainingSeconds == displayedWhileRunning,
                    "pausing at +\(offsetMilliseconds)ms must not move the display away from \(displayedWhileRunning)")
        }
    }

    // Resuming does not shorten it. The rounding up only pushes the end time slightly later.
    @Test func resumeDoesNotShortenTheSession() throws {
        let ctx = presets()
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: "p", taskSnapshot: nil),
            context: .idle(now: t0), presets: ctx, now: t0
        ).get().context
        let paused = try TimerEngine.reduce(
            action: .pause, context: started, presets: ctx, now: t0.addingTimeInterval(10.4)
        ).get().context
        let resumeAt = t0.addingTimeInterval(60)
        let resumed = try TimerEngine.reduce(action: .resume, context: paused, presets: ctx, now: resumeAt).get().context

        let remaining = resumed.sessionEndAt!.timeIntervalSince(resumeAt)
        #expect(remaining >= Double(paused.remainingSeconds!))
    }
}
