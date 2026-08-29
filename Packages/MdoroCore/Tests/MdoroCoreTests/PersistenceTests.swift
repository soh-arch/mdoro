import Testing
import Foundation
@testable import MdoroCore

private let reference = Date(timeIntervalSince1970: 1_700_000_000)

// REQ-ERR-010 / Decision 0034: only that a write failed matters here.
private let writeRefused = LogWriteError.writeFailed(
    ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
)

private func preset(work: Int = 25 * 60, interval: Int = 4) -> Preset {
    Preset(
        id: "preset-1", name: "Standard",
        workSeconds: work, shortBreakSeconds: 5 * 60, longBreakSeconds: 15 * 60,
        longBreakInterval: interval, extendSeconds: 5 * 60
    )
}

private func context(_ p: Preset) -> PresetContext {
    PresetContext(presets: [p], activePresetId: p.id)
}

// Build a WORK session that has started, and return it without advancing time any further.
private func startedWork(_ p: Preset, at start: Date = reference) throws -> TimerContext {
    let presets = context(p)
    return try TimerEngine.reduce(
        action: .startWork(presetId: p.id, taskSnapshot: "タスクA"),
        context: .idle(now: start), presets: presets, now: start
    ).get().context
}

@Suite("Restore decision (REQ-PER-003)")
struct RestoreTests {

    // (a) An already committed session restores to IDLE, and the log is never written again.
    @Test func committedSessionRestoresToIdleWithoutRewritingLog() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        // Run it past the grace so that it commits.
        let committed = TimerEngine.tick(context: started, presets: presets, now: endAt.addingTimeInterval(120))
        #expect(committed.effects.count == 1)
        #expect(committed.context.committedAt != nil)

        let restored = TimerEngine.restore(context: committed.context, presets: presets, now: endAt.addingTimeInterval(9 * 3600))
        #expect(restored.context.runState == .idle)
        #expect(restored.effects.isEmpty, "REQ-PER-003(a): must not write the log again for an already committed session")
    }

    // (b) With the end time still in the future, it stays RUNNING.
    @Test func futureSessionRestoresAsRunning() throws {
        let p = preset()
        let started = try startedWork(p)
        let restored = TimerEngine.restore(context: started, presets: context(p), now: reference.addingTimeInterval(10 * 60))
        #expect(restored.context.runState == .running)
        #expect(restored.context.sessionEndAt == started.sessionEndAt)
        #expect(restored.effects.isEmpty)
    }

    // (c) Within the grace it stays FINISHED. Extend and abort are both still available.
    @Test func withinGraceRestoresAsFinished() throws {
        let p = preset()
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        let restored = TimerEngine.restore(context: started, presets: context(p), now: endAt.addingTimeInterval(30))
        #expect(restored.context.runState == .finished)
        #expect(restored.context.finishedAt == endAt)
        #expect(restored.context.committedAt == nil, "still within the grace period, so it must not be committed yet")
        #expect(restored.effects.isEmpty)
        #expect(TimerEngine.isWithinExtensionWindow(restored.context, now: endAt.addingTimeInterval(30)),
                "REQ-PER-003(c): within the grace period, Extend stays available as in normal operation")
    }

    // (d) Past the grace, always ask the user. Never turn it into a record in silence.
    @Test func beyondGraceAsksTheUser() throws {
        let p = preset()
        let started = try startedWork(p)
        let endAt = started.sessionEndAt!
        let restored = TimerEngine.restore(context: started, presets: context(p), now: endAt.addingTimeInterval(3 * 3600))

        #expect(restored.context.runState == .pendingDecision)
        #expect(restored.context.pendingDecision?.reason == .restoredAfterEnd)
        #expect(restored.context.pendingDecision?.endedAt == endAt)
        #expect(restored.context.committedAt == nil, "must not write the log until the user answers")
        #expect(restored.context.loopCount == 0, "must not increment the loop count until the user answers")
        #expect(restored.effects.isEmpty == false)
    }

    // Mix up tick() and restore(), and a session that ran out while the app was closed becomes
    // a record in silence.
    @Test func restoreDoesNotSilentlyCompleteWhatTickWould() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let wayLater = started.sessionEndAt!.addingTimeInterval(3 * 3600)

        let ticked = TimerEngine.tick(context: started, presets: presets, now: wayLater)
        #expect(ticked.effects.count == 1, "tick() commits a session that ran past its grace period")

        let restored = TimerEngine.restore(context: started, presets: presets, now: wayLater)
        #expect(!restored.effects.contains { if case .commitLog = $0 { return true } else { return false } },
                "REQ-PER-003(d): restore must ask the user instead of committing")
        #expect(restored.context.runState == .pendingDecision)
    }

    // A break has no grace (REQ-TIM-044). When it is past its end time uncommitted and still
    // inside the equivalent of the grace, there is no reason to make anyone wait: commit here.
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
        #expect(restored.context.runState == .idle, "REQ-TIM-044: a break has no grace period")
        #expect(restored.context.committedAt != nil)
        #expect(restored.effects.contains { if case .commitLog = $0 { return true } else { return false } })
    }

    // A pause left too long falls through to the confirmation on restore as well (REQ-TIM-033).
    @Test func longPausedSessionRestoresToPendingDecision() throws {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let paused = try TimerEngine.reduce(action: .pause, context: started, presets: presets, now: reference.addingTimeInterval(60)).get().context

        let restored = TimerEngine.restore(context: paused, presets: presets, now: reference.addingTimeInterval(20 * 3600))
        #expect(restored.context.runState == .pendingDecision)
        #expect(restored.context.pendingDecision?.reason == .pausedTooLong)

        let soon = TimerEngine.restore(context: paused, presets: presets, now: reference.addingTimeInterval(2 * 3600))
        #expect(soon.context.runState == .paused, "below idleResetHours it stays PAUSED")
    }
}

@Suite("PENDING_DECISION effects and auto-commit (REQ-PER-004 / 008 / 009)")
struct PendingDecisionTests {

    private func restoredPending() throws -> (TimerContext, PresetContext) {
        let p = preset()
        let presets = context(p)
        let started = try startedWork(p)
        let restored = TimerEngine.restore(context: started, presets: presets, now: started.sessionEndAt!.addingTimeInterval(3 * 3600))
        return (restored.context, presets)
    }

    // REQ-PER-008 / 009: the transition asks for the notifications to be cancelled and for the
    // Live Activity to end.
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

    // REQ-PER-004: left unanswered across a change of logical day, it commits as a discard.
    @Test func unansweredDecisionIsDiscardedOnLogicalDayRollover() throws {
        let (pending, presets) = try restoredPending()
        let nextDay = reference.addingTimeInterval(36 * 3600)
        #expect(LogicalDay.date(for: nextDay, dayStartHour: 4) != pending.logicalDate)

        let rolled = TimerEngine.tick(context: pending, presets: presets, now: nextDay)
        #expect(rolled.context.committedAt != nil, "crossing the logical day boundary must commit the session")
        guard case let .commitLog(entry) = rolled.effects.first else {
            Issue.record("no commitLog was emitted")
            return
        }
        #expect(entry.outcome == .aborted, "REQ-PER-004: discard commits with the aborted outcome, logged as Stopped")
        #expect(entry.endedAt == pending.pendingDecision?.endedAt,
                "REQ-PER-004: the end time is when the anomaly was detected, not after the idle stretch")
        #expect(entry.elapsedSeconds <= 25 * 60)
    }

    @Test func sameLogicalDayDoesNotAutoCommit() throws {
        let (pending, presets) = try restoredPending()
        let stillToday = TimerEngine.tick(context: pending, presets: presets, now: pending.lastUpdatedAt.addingTimeInterval(600))
        #expect(stillToday.context.committedAt == nil)
        #expect(stillToday.context.runState == .pendingDecision)
        #expect(stillToday.effects.isEmpty)
    }

    // REQ-PER-004: moving the boundary itself must not commit the session on its own.
    @Test func changingLogicalDayStartHourDoesNotTriggerAutoCommit() throws {
        let (pending, presets) = try restoredPending()
        let now = pending.lastUpdatedAt.addingTimeInterval(60)

        // Switch to a setting where moving the boundary at this point changes the logical day.
        var shifted = AppSettings.default
        shifted.logicalDayStartHour = (AppSettings.default.logicalDayStartHour + 12) % 24

        let updated = try TimerEngine.reduce(
            action: .updateSettings(shifted), context: pending, presets: presets,
            settings: .default, now: now
        ).get()
        #expect(updated.context.committedAt == nil, "a settings change alone must not commit the session")
        #expect(updated.context.runState == .pendingDecision)

        // A tick that follows does not fire either, because it works from the new boundary.
        let ticked = TimerEngine.tick(context: updated.context, presets: presets, settings: shifted, now: now.addingTimeInterval(60))
        #expect(ticked.context.committedAt == nil)
        #expect(ticked.effects.isEmpty)
    }
}

@Suite("Persistence (REQ-PER-001 / 002)")
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

        #expect(try store.load() == nil, "no saved state must return nil, which stays distinct from corrupted state")

        let state = try sample()
        try store.save(state)
        #expect(try store.load() == state)

        // Saving over an existing file must not break it (the path where the replacement target
        // already exists).
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

    // REQ-PER-002: at launch, loading and the restore decision are one continuous step.
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
        #expect(restored.presets.presets.count == 1, "REQ-PRS-010: only the Standard preset ships with the app")
        #expect(restored.presets.activePreset?.name == "Standard")
    }
}

@Suite("Persisting unwritten log entries (REQ-LOG-005)")
struct PendingLogPersistenceTests {

    private func entry(_ start: Date) -> LogEntry {
        LogEntry(
            sessionType: .work, startedAt: start, endedAt: start.addingTimeInterval(1500),
            elapsedSeconds: 1500, outcome: .completed, presetName: "Standard",
            presetEditedDuringSession: false, taskSnapshot: "タスク", extendedSeconds: 0,
            loopCountAfterCompletion: 1, longBreakInterval: 4, logicalDate: reference
        )
    }

    // committedAt is set on commit (REQ-LOG-019), so losing the queue means the record is never
    // written again.
    @Test func pendingEntriesSurviveARestart() throws {
        let queue = LogWriteQueue()
        queue.enqueue(entry(reference))
        queue.enqueue(entry(reference.addingTimeInterval(1800)))
        _ = queue.flush { _ in throw writeRefused }
        #expect(queue.pendingCount == 2)

        let store = InMemoryStateStore()
        try store.save(PersistedState(
            timer: .idle(now: reference), presets: .initial(),
            pendingLogEntries: queue.pendingEntries, savedAt: reference
        ))

        // Read it back, imitating a restart.
        let reloaded = try #require(try store.load())
        #expect(reloaded.pendingLogEntries.count == 2)

        let revived = LogWriteQueue(entries: reloaded.pendingLogEntries)
        var written: [Date] = []
        let result = revived.flush { written.append($0.startedAt) }
        #expect(result.written == 2)
        #expect(written == [reference, reference.addingTimeInterval(1800)], "the queue order survives the restart")
    }

    // A file saved before this field existed must still load.
    @Test func stateSavedBeforeThisFieldExistedStillLoads() throws {
        let json = """
        {"schemaVersion":1,
         "timer":\(String(data: try JSONEncoder.iso.encode(TimerContext.idle(now: reference)), encoding: .utf8)!),
         "presets":\(String(data: try JSONEncoder.iso.encode(PresetContext.initial()), encoding: .utf8)!),
         "savedAt":"2023-11-14T22:13:20Z"}
        """
        let decoded = try JSONDecoder.iso.decode(PersistedState.self, from: Data(json.utf8))
        #expect(decoded.pendingLogEntries.isEmpty)
        #expect(decoded.settings == .default)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}

@Suite("Hot key bindings (REQ-UIX-033)")
struct HotKeyBindingTests {

    // A binding with no modifier is not accepted. Taking a bare key away stops text entry.
    @Test func modifierIsRequired() {
        let command = NSEventModifierFlagsCommand
        #expect(HotKeyBinding(keyCode: 35, modifierFlags: command, displayName: "⌘P").hasModifier)
        #expect(!HotKeyBinding(keyCode: 35, modifierFlags: 0, displayName: "P").hasModifier)
        // Modifiers such as Caps Lock cannot be used for a binding.
        #expect(!HotKeyBinding(keyCode: 35, modifierFlags: 1 << 16, displayName: "P").hasModifier)
    }

    // REQ-UIX-033 / Decision 0016: unassigned by default. Nothing is registered.
    @Test func defaultIsUnassigned() {
        #expect(AppSettings.default.pauseResumeHotKey == nil)
        #expect(AppSettings.default.launchAtLogin == false)
    }

    @Test func bindingSurvivesPersistence() throws {
        var settings = AppSettings.default
        settings.pauseResumeHotKey = HotKeyBinding(
            keyCode: 35, modifierFlags: NSEventModifierFlagsControl | NSEventModifierFlagsOption,
            displayName: "⌃⌥P"
        )
        settings.launchAtLogin = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.pauseResumeHotKey?.displayName == "⌃⌥P")
        #expect(decoded.launchAtLogin)
    }
}

// The rawValue of NSEvent.ModifierFlags (only the values, with no dependency on AppKit).
private let NSEventModifierFlagsControl: UInt = 1 << 18
private let NSEventModifierFlagsOption: UInt = 1 << 19
private let NSEventModifierFlagsCommand: UInt = 1 << 20
