import Testing
import Foundation
@testable import MdoroCore

private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

private func presetsForSaysWhen() -> PresetContext {
    let p = Preset(id: "p", name: "Standard", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
                   longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
    return PresetContext(presets: [p], activePresetId: p.id)
}

private func committedEntry(_ effects: [Effect]) -> LogEntry? {
    for effect in effects {
        if case let .commitLog(entry) = effect { return entry }
    }
    return nil
}

// A work session that has run its 25 minutes and reached FINISHED. finishedAt and sessionEndAt are
// both set here, exactly as tick() leaves them; each test then takes away what it wants to be missing.
private func finishedWorkSession() throws -> (TimerContext, PresetContext) {
    let presets = presetsForSaysWhen()
    let started = try TimerEngine.reduce(
        action: .startWork(presetId: "p", taskSnapshot: "Write the report"),
        context: .idle(now: anchor), presets: presets, now: anchor
    ).get().context
    let endAt = try #require(started.sessionEndAt)
    let finished = TimerEngine.tick(context: started, presets: presets, now: endAt).context
    return (finished, presets)
}

// Decision 0002: the log is inserted into and never rewritten, so a time range that reaches
// MdoroLog.md cannot be corrected from inside the app. The end time of a completed session is
// therefore either known or not written at all — `now` is not a stand-in, because "it ended just
// now" is a statement about the session, not an admission that we lost track of it.
@Suite("A completed session says when it ended, or says nothing (Decision 0002)")
struct ASessionThatEndedSaysWhenTests {

    // 1. Neither moment is known. Before this change the log line was written with `now` as its end,
    //    so both assertions below failed: one commitLog effect was produced, and the context came back
    //    as a fresh IDLE rather than untouched.
    @Test func aCompletionWithNoKnownEndTimeCommitsNothing() throws {
        let (finished, presets) = try finishedWorkSession()
        var noEndTime = finished
        noEndTime.finishedAt = nil
        noEndTime.sessionEndAt = nil

        // Half an hour after the session began: long enough that REQ-TIM-032 would not be the thing
        // holding the log line back.
        let commitAt = anchor.addingTimeInterval(30 * 60)
        let (context, effects) = TimerEngine.finalize(
            context: noEndTime, presets: presets, settings: .default, now: commitAt, outcome: .completed
        )

        let wroteNothing = effects.isEmpty
        #expect(wroteNothing, "an end time we cannot vouch for must not reach MdoroLog.md (Decision 0002)")
        let untouched = context == noEndTime
        #expect(untouched, "committing nothing must not mark the session committed either")
    }

    // 2a. The normal shape: tick(), restore() and confirmRestoredSession(.complete) all assign
    //     finishedAt. That moment is what the log records, and it is not `now`.
    @Test func finishedAtIsWhatTheLogRecords() throws {
        let (finished, presets) = try finishedWorkSession()
        let finishedAt = try #require(finished.finishedAt)
        var withoutSessionEndAt = finished
        withoutSessionEndAt.sessionEndAt = nil

        let commitAt = finishedAt.addingTimeInterval(45)
        let (context, effects) = TimerEngine.finalize(
            context: withoutSessionEndAt, presets: presets, settings: .default, now: commitAt, outcome: .completed
        )

        let entry = try #require(committedEntry(effects), "a completion with a known end time is recorded")
        #expect(entry.endedAt == finishedAt)
        #expect(entry.elapsedSeconds == 25 * 60)
        #expect(context.runState == .idle, "REQ-TIM-035: the only way out of FINISHED is IDLE")
        #expect(context.committedAt == commitAt, "REQ-LOG-019")
    }

    // 2b. sessionEndAt alone is still an end time. restore() reaches finalize() with it in hand
    //     whether or not finishedAt survived the launch, so refusing this one would refuse a session
    //     the app has every right to record.
    @Test func sessionEndAtAloneIsEnough() throws {
        let (finished, presets) = try finishedWorkSession()
        let endAt = try #require(finished.sessionEndAt)
        var withoutFinishedAt = finished
        withoutFinishedAt.finishedAt = nil

        let commitAt = endAt.addingTimeInterval(90)
        let (context, effects) = TimerEngine.finalize(
            context: withoutFinishedAt, presets: presets, settings: .default, now: commitAt, outcome: .completed
        )

        let entry = try #require(committedEntry(effects), "sessionEndAt is a known end time, so this is recorded")
        #expect(entry.endedAt == endAt)
        #expect(entry.elapsedSeconds == 25 * 60)
        #expect(context.runState == .idle)
    }

    // 3. REQ-PER-004: the override decides, and it is consulted before anything else. A context with
    //    no end time of its own is still recorded when the caller supplies the moment.
    @Test func theOverrideStillDecidesOnItsOwn() throws {
        let (finished, presets) = try finishedWorkSession()
        var noEndTime = finished
        noEndTime.finishedAt = nil
        noEndTime.sessionEndAt = nil

        let noticedAt = anchor.addingTimeInterval(20 * 60)
        let commitAt = anchor.addingTimeInterval(9 * 3600)
        let (context, effects) = TimerEngine.finalize(
            context: noEndTime, presets: presets, settings: .default, now: commitAt,
            outcome: .aborted, endedAtOverride: noticedAt
        )

        let entry = try #require(committedEntry(effects))
        #expect(entry.endedAt == noticedAt, "REQ-PER-004: the end time is when the trouble was noticed")
        #expect(entry.elapsedSeconds == 20 * 60, "the hours it sat waiting are not working time")
        #expect(context.runState == .idle)
    }

    // 3b. REQ-PER-004 through the action that actually carries the override: the answer "discard"
    //     ends the session at the moment the question was raised, not at the moment it was answered.
    @Test func discardingARestoredSessionKeepsUsingTheMomentItEnded() throws {
        let presets = presetsForSaysWhen()
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: "p", taskSnapshot: nil),
            context: .idle(now: anchor), presets: presets, now: anchor
        ).get().context
        let endAt = try #require(started.sessionEndAt)

        // Nobody was there until past the grace, so restore() asks instead of assuming (REQ-PER-003(d)).
        let restoredAt = endAt.addingTimeInterval(5 * 60)
        let asked = TimerEngine.restore(context: started, presets: presets, now: restoredAt)
        #expect(asked.context.runState == .pendingDecision)
        let pending = try #require(asked.context.pendingDecision)

        let answeredAt = restoredAt.addingTimeInterval(30)
        // The question is answered inside the same logical day, so the automatic commit REQ-PER-004
        // makes when the day turns is not what is being measured here. The logical date is pinned to
        // the answer rather than left to work out from the anchor, because LogicalDay reads the
        // machine's own calendar and a fixed instant falls on either side of 04:00 depending on where
        // the test runs.
        var waiting = asked.context
        waiting.logicalDate = LogicalDay.date(for: answeredAt, dayStartHour: AppSettings.default.logicalDayStartHour)

        let discarded = try TimerEngine.reduce(
            action: .confirmRestoredSession(.discard), context: waiting,
            presets: presets, now: answeredAt
        ).get()

        let entry = try #require(committedEntry(discarded.effects))
        #expect(entry.endedAt == pending.endedAt)
        #expect(entry.endedAt == endAt, "the session ended when its time ran out, not when the question was answered")
        #expect(entry.outcome == .aborted)
    }

    // A skip and a stop are not completions: they end when the person acts, so `now` is the true
    // answer there and nothing about it changes.
    @Test func aStopWithNoEndTimeStillEndsNow() throws {
        let (finished, presets) = try finishedWorkSession()
        var noEndTime = finished
        noEndTime.finishedAt = nil
        noEndTime.sessionEndAt = nil

        let stoppedAt = anchor.addingTimeInterval(10 * 60)
        for outcome in [LogOutcome.aborted, LogOutcome.skipped] {
            let (context, effects) = TimerEngine.finalize(
                context: noEndTime, presets: presets, settings: .default, now: stoppedAt, outcome: outcome
            )
            let entry = try #require(committedEntry(effects), "\(outcome) is still recorded")
            #expect(entry.endedAt == stoppedAt)
            #expect(entry.outcome == outcome)
            #expect(context.runState == .idle)
        }
    }
}
