import Testing
import Foundation
@testable import PomodoroCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func standardPresets() -> PresetContext {
    let p = Preset(id: "p", name: "標準", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
                   longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
    return PresetContext(presets: [p], activePresetId: p.id)
}

private func hasCommitLog(_ effects: [Effect]) -> Bool {
    effects.contains { if case .commitLog = $0 { return true } else { return false } }
}

// REQ-TIM-032 / REQ-TIM-005: 正味稼働時間が 60 秒未満のセッションはログに記録しない。
//
// この規定を知らずに「中断してもログが出ない」を不具合として追いかけたことがある。
// 境界の両側を押さえておく。
@Suite("短すぎるセッションは記録しない (REQ-TIM-032)")
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

    // 確定済みの印は、記録の有無にかかわらず付く。付けないと二重確定の恐れがある (REQ-LOG-019)。
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

    // 一時停止を挟んだぶんは正味時間に入らない (REQ-TIM-005)。
    // 壁時計で 90 秒でも、70 秒止まっていれば記録しない。
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
        #expect(!hasCommitLog(aborted.effects), "正味 30 秒なので記録しない")
    }
}

// 表示の一貫性。一時停止で残り時間が飛ぶと、動いているものが信用できなくなる。
@Suite("一時停止で残り時間が変わらない")
struct PauseRoundingTests {

    private func presets() -> PresetContext {
        let p = Preset(id: "p", name: "標準", workSeconds: 25 * 60, shortBreakSeconds: 5 * 60,
                       longBreakSeconds: 15 * 60, longBreakInterval: 4, extendSeconds: 5 * 60)
        return PresetContext(presets: [p], activePresetId: p.id)
    }

    // 表示は切り上げ。一時停止が切り捨てだと、押した瞬間に1秒減って見える。
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
                    "+\(offsetMilliseconds)ms で一時停止したとき、表示が \(displayedWhileRunning) から動いてはならない")
        }
    }

    // 再開しても縮まない。切り上げたぶん、終了時刻はわずかに後ろへずれるだけ。
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
