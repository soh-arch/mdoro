import Testing
import Foundation
@testable import PomodoroCore

private let reference = Date(timeIntervalSince1970: 1_700_000_000)

private func preset(work: Int = 25 * 60, interval: Int = 4) -> Preset {
    Preset(
        id: "preset-1", name: "標準",
        workSeconds: work, shortBreakSeconds: 5 * 60, longBreakSeconds: 15 * 60,
        longBreakInterval: interval, extendSeconds: 5 * 60
    )
}

private func context(_ p: Preset) -> PresetContext {
    PresetContext(presets: [p], activePresetId: p.id)
}

// 「開始した WORK セッション」を作り、指定した時刻まで進めずに返す。
private func startedWork(_ p: Preset, at start: Date = reference) throws -> TimerContext {
    let presets = context(p)
    return try TimerEngine.reduce(
        action: .startWork(presetId: p.id, taskSnapshot: "タスクA"),
        context: .idle(now: start), presets: presets, now: start
    ).get().context
}

@Suite("復元判定 (REQ-PER-003)")
struct RestoreTests {

    // (a) 確定済みは IDLE で復元し、ログを再度書かない。
    @Test func committedSessionRestoresToIdleWithoutRewritingLog() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        // 猶予を過ぎるまで動かし、確定させる。
        let committed = TimerEngine.tick(context: started, presets: presets, now: endAt.addingTimeInterval(120))
        #expect(committed.effects.count == 1)
        #expect(committed.context.committedAt != nil)

        let restored = TimerEngine.restore(context: committed.context, presets: presets, now: endAt.addingTimeInterval(9 * 3600))
        #expect(restored.context.runState == .idle)
        #expect(restored.effects.isEmpty, "REQ-PER-003(a): 確定済みのセッションのログを再度書いてはならない")
    }

    // (b) 終了時刻が未来ならそのまま RUNNING。
    @Test func futureSessionRestoresAsRunning() throws {
        let p = preset()
        let started = try startedWork(p)
        let restored = TimerEngine.restore(context: started, presets: context(p), now: reference.addingTimeInterval(10 * 60))
        #expect(restored.context.runState == .running)
        #expect(restored.context.sessionEndAt == started.sessionEndAt)
        #expect(restored.effects.isEmpty)
    }

    // (c) 猶予内は FINISHED のまま。延長も中断もまだ選べる。
    @Test func withinGraceRestoresAsFinished() throws {
        let p = preset()
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        let restored = TimerEngine.restore(context: started, presets: context(p), now: endAt.addingTimeInterval(30))
        #expect(restored.context.runState == .finished)
        #expect(restored.context.finishedAt == endAt)
        #expect(restored.context.committedAt == nil, "猶予内なのでまだ確定してはならない")
        #expect(restored.effects.isEmpty)
        #expect(TimerEngine.isWithinExtensionWindow(restored.context, now: endAt.addingTimeInterval(30)),
                "REQ-PER-003(c): 猶予内なら通常運転と同じく延長できる")
    }

    // (d) 猶予超過は必ずユーザーに聞く。黙って実績にしない。
    @Test func beyondGraceAsksTheUser() throws {
        let p = preset()
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        let restored = TimerEngine.restore(context: started, presets: context(p), now: endAt.addingTimeInterval(3 * 3600))

        #expect(restored.context.runState == .pendingDecision)
        #expect(restored.context.pendingDecision?.reason == .restoredAfterEnd)
        #expect(restored.context.pendingDecision?.endedAt == endAt)
        #expect(restored.context.committedAt == nil, "応答までログを記録してはならない")
        #expect(restored.context.loopCount == 0, "応答まで周回数を加算してはならない")
        #expect(restored.effects.isEmpty == false)
    }

    // tick() と restore() を取り違えると、閉じている間に過ぎたセッションが黙って実績になる。
    @Test func restoreDoesNotSilentlyCompleteWhatTickWould() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let wayLater = started.sessionEndAt!.addingTimeInterval(3 * 3600)

        let ticked = TimerEngine.tick(context: started, presets: presets, now: wayLater)
        #expect(ticked.effects.count == 1, "tick() は猶予超過を完了として確定させる")

        let restored = TimerEngine.restore(context: started, presets: presets, now: wayLater)
        #expect(!restored.effects.contains { if case .commitLog = $0 { return true } else { return false } },
                "REQ-PER-003(d): 復元では確定させず、判断を仰ぐ")
        #expect(restored.context.runState == .pendingDecision)
    }

    // 休憩は猶予を持たない (REQ-TIM-044)。未確定のまま終了時刻を過ぎていて、
    // かつ猶予相当の時間内なら、待たせる理由がないのでここで確定させる。
    @Test func uncommittedBreakWithinGraceCommitsImmediately() throws {
        let p = preset()
        let presets = context(p)
        let idle = TimerContext.idle(now: reference)
        let started = try TimerEngine.reduce(
            action: .startBreak(type: .shortBreak, presetId: p.id),
            context: idle, presets: presets, now: reference
        ).get().context
        let endAt = started.sessionEndAt!

        let restored = TimerEngine.restore(context: started, presets: presets, now: endAt.addingTimeInterval(30))
        #expect(restored.context.runState == .idle, "REQ-TIM-044: 休憩に猶予はない")
        #expect(restored.context.committedAt != nil)
        #expect(restored.effects.contains { if case .commitLog = $0 { return true } else { return false } })
    }

    // 放置しすぎた一時停止は、復元時も確認へ倒す (REQ-TIM-033)。
    @Test func longPausedSessionRestoresToPendingDecision() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let paused = try TimerEngine.reduce(action: .pause, context: started, presets: presets, now: reference.addingTimeInterval(60)).get().context

        let restored = TimerEngine.restore(context: paused, presets: presets, now: reference.addingTimeInterval(20 * 3600))
        #expect(restored.context.runState == .pendingDecision)
        #expect(restored.context.pendingDecision?.reason == .pausedTooLong)

        let soon = TimerEngine.restore(context: paused, presets: presets, now: reference.addingTimeInterval(2 * 3600))
        #expect(soon.context.runState == .paused, "idleResetHours 未満なら一時停止のまま")
    }
}

@Suite("PENDING_DECISION の副作用と自動確定 (REQ-PER-004 / 008 / 009)")
struct PendingDecisionTests {

    private func restoredPending() throws -> (TimerContext, PresetContext) {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let restored = TimerEngine.restore(context: started, presets: presets, now: started.sessionEndAt!.addingTimeInterval(3 * 3600))
        return (restored.context, presets)
    }

    // REQ-PER-008 / 009: 遷移時に通知の取り消しと Live Activity の終了を伝える。
    @Test func enteringPendingDecisionCancelsNotificationsAndEndsLiveActivity() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let restored = TimerEngine.restore(context: started, presets: presets, now: started.sessionEndAt!.addingTimeInterval(3 * 3600))
        #expect(restored.effects.contains(.cancelScheduledNotifications))
        #expect(restored.effects.contains(.endLiveActivity))
    }

    @Test func longPauseAlsoEmitsThoseEffects() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let paused = try TimerEngine.reduce(action: .pause, context: started, presets: presets, now: reference.addingTimeInterval(60)).get().context
        let resumed = try TimerEngine.reduce(action: .resume, context: paused, presets: presets, now: reference.addingTimeInterval(20 * 3600)).get()
        #expect(resumed.context.runState == .pendingDecision)
        #expect(resumed.effects.contains(.cancelScheduledNotifications))
        #expect(resumed.effects.contains(.endLiveActivity))
    }

    // REQ-PER-004: 未応答のまま論理日が変われば discard として確定する。
    @Test func unansweredDecisionIsDiscardedOnLogicalDayRollover() throws {
        let (pending, presets) = try restoredPending()
        let nextDay = reference.addingTimeInterval(36 * 3600)
        #expect(LogicalDay.date(for: nextDay, dayStartHour: 4) != pending.logicalDate)

        let rolled = TimerEngine.tick(context: pending, presets: presets, now: nextDay)
        #expect(rolled.context.committedAt != nil, "論理日をまたいだら確定させる")
        guard case let .commitLog(entry) = rolled.effects.first else {
            Issue.record("commitLog が出ていない")
            return
        }
        #expect(entry.outcome == .aborted, "REQ-PER-004: discard (中断扱い) として確定する")
        #expect(entry.endedAt == pending.pendingDecision?.endedAt,
                "REQ-PER-004: 放置された実時間を含めず、異常検知時点を終了時刻とする")
        #expect(entry.elapsedSeconds <= 25 * 60)
    }

    @Test func sameLogicalDayDoesNotAutoCommit() throws {
        let (pending, presets) = try restoredPending()
        let stillToday = TimerEngine.tick(context: pending, presets: presets, now: pending.lastUpdatedAt.addingTimeInterval(600))
        #expect(stillToday.context.committedAt == nil)
        #expect(stillToday.context.runState == .pendingDecision)
        #expect(stillToday.effects.isEmpty)
    }

    // REQ-PER-004: 境界そのものを動かしただけでは自動確定してはならない。
    @Test func changingLogicalDayStartHourDoesNotTriggerAutoCommit() throws {
        let (pending, presets) = try restoredPending()
        let now = pending.lastUpdatedAt.addingTimeInterval(60)

        // この時点で境界を動かすと論理日が変わってしまう設定に切り替える。
        var shifted = AppSettings.default
        shifted.logicalDayStartHour = (AppSettings.default.logicalDayStartHour + 12) % 24

        let updated = try TimerEngine.reduce(
            action: .updateSettings(shifted), context: pending, presets: presets,
            settings: .default, now: now
        ).get()
        #expect(updated.context.committedAt == nil, "設定変更そのもので確定させてはならない")
        #expect(updated.context.runState == .pendingDecision)

        // 続けて tick しても、新しい境界を基準にしているので発火しない。
        let ticked = TimerEngine.tick(context: updated.context, presets: presets, settings: shifted, now: now.addingTimeInterval(60))
        #expect(ticked.context.committedAt == nil)
        #expect(ticked.effects.isEmpty)
    }
}

@Suite("永続化 (REQ-PER-001 / 002)")
struct StateStoreTests {

    private func sample(now: Date = reference) throws -> PersistedState {
        let p = preset()
        let presets = context(p)
        let started = try TimerEngine.reduce(
            action: .startWork(presetId: p.id, taskSnapshot: "タスクA"),
            context: .idle(now: now), presets: presets, now: now
        ).get().context
        return PersistedState(
            timer: started, presets: presets, settings: .default,
            selectedTaskId: "abc123", selectedTaskSnapshot: "タスクA", savedAt: now
        )
    }

    @Test func fileStoreRoundTripsEverythingREQPER001Requires() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileStateStore(fileURL: directory.appendingPathComponent("state.json"))

        #expect(try store.load() == nil, "保存が無いときは nil。壊れているのとは区別する")

        let state = try sample()
        try store.save(state)
        #expect(try store.load() == state)

        // 上書き保存でも壊れないこと (差し替え先が既に存在する経路)。
        var updated = state
        updated.selectedTaskSnapshot = "タスクB"
        updated.savedAt = reference.addingTimeInterval(60)
        try store.save(updated)
        let reloaded = try store.load()
        #expect(reloaded?.selectedTaskSnapshot == "タスクB")
        #expect(reloaded?.presets.activePresetId == state.presets.activePresetId)
        #expect(reloaded?.timer.sessionTaskSnapshot == "タスクA")
    }

    @Test func corruptedFileThrowsInsteadOfSilentlyResetting() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        try Data("{ これは JSON ではない".utf8).write(to: url)

        let store = FileStateStore(fileURL: url)
        #expect(throws: StateStoreError.corrupted) { try store.load() }
    }

    @Test func newerSchemaIsRefusedRatherThanMisread() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PomodoroStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = FileStateStore(fileURL: url)

        var future = try sample()
        future.schemaVersion = PersistedState.currentSchemaVersion + 1
        try store.save(future)

        #expect(throws: StateStoreError.unsupportedSchemaVersion(
            found: PersistedState.currentSchemaVersion + 1,
            supported: PersistedState.currentSchemaVersion
        )) { try store.load() }
    }

    // REQ-PER-002: 起動時は読み込みと復元判定が一続きであること。
    @Test func loadAndRestoreAppliesTheRestoreRules() throws {
        let state = try sample()
        let store = InMemoryStateStore(initial: state)
        let endAt = state.timer.sessionEndAt!

        let stillRunning = try store.loadAndRestore(now: endAt.addingTimeInterval(-60))
        #expect(stillRunning.context.runState == .running)

        let longGone = try store.loadAndRestore(now: endAt.addingTimeInterval(5 * 3600))
        #expect(longGone.context.runState == .pendingDecision)
    }

    @Test func emptyStoreStartsFromTheStandardPresetOnly() throws {
        let store = InMemoryStateStore()
        let restored = try store.loadAndRestore(now: reference)
        #expect(restored.context.runState == .idle)
        #expect(restored.presets.presets.count == 1, "REQ-PRS-010: 同梱するのは「標準」だけ")
        #expect(restored.presets.activePreset?.name == "標準")
    }
}
