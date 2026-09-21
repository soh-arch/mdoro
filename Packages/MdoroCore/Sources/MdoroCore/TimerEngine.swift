import Foundation

// REQ-TIM: the state machine of chapter 4. It writes no log, raises no notification and touches
// no file; all of that leaves as an Effect for the caller.
public enum TimerEngine {
    // REQ-TIM-043: the grace after FINISHED is fixed and does not depend on the preset. It is kept
    // in step with the window of REQ-TIM-046.
    public static let extensionGraceSeconds: TimeInterval = 60
    // REQ-TIM-046: the most time that may remain for RUNNING or PAUSED to accept an extension.
    public static let extensionWindowSeconds: TimeInterval = 5 * 60

    public struct Reduction: Equatable {
        public let context: TimerContext
        public let presets: PresetContext
        public let effects: [Effect]
    }

    public static func canAccept(_ action: TimerAction, in runState: RunState) -> Bool {
        StateTransitionMatrix.canAccept(action, in: runState)
    }

    // REQ-TIM-046 / Decision 0010: five minutes or less remaining for RUNNING / PAUSED; within one
    // minute of the end for FINISHED.
    public static func isWithinExtensionWindow(_ context: TimerContext, now: Date) -> Bool {
        switch context.runState {
        case .running:
            guard let endAt = context.sessionEndAt else { return false }
            return endAt.timeIntervalSince(now) <= extensionWindowSeconds
        case .paused:
            // REQ-TIM-002: a pause holds the remainder of the session in remainingSeconds, so that is
            // what the window is measured against. With no remainder to measure, the window cannot be
            // decided — and this falls to the same side as the two branches around it: closed.
            // A default of 0 would put the widest possible answer on the accepting side.
            guard let remaining = context.remainingSeconds else { return false }
            return TimeInterval(remaining) <= extensionWindowSeconds
        case .finished:
            guard let finishedAt = context.finishedAt else { return false }
            return now.timeIntervalSince(finishedAt) <= extensionGraceSeconds
        default:
            return false
        }
    }

    // MARK: - PENDING_DECISION

    // REQ-PER-008 / 009: cancel the notifications and end the Live Activity. Nothing is rescheduled.
    static let pendingDecisionEffects: [Effect] = [.cancelScheduledNotifications, .endLiveActivity]

    static func enterPendingDecision(
        _ context: TimerContext,
        reason: PendingDecision.Reason,
        endedAt: Date,
        now: Date
    ) -> TimerContext {
        var ctx = context
        let elapsed = computeElapsedSeconds(context: ctx, endedAt: endedAt)
        ctx.runState = .pendingDecision
        ctx.pendingDecision = PendingDecision(reason: reason, endedAt: endedAt, elapsedSeconds: elapsed)
        ctx.lastUpdatedAt = now
        return ctx
    }

    // MARK: - Restoring at launch (REQ-PER-002 / 003)

    // REQ-PER-003(d): kept apart from tick(). A session that ended while nobody was there must not be
    // taken for completed without asking.
    public static func restore(
        context: TimerContext,
        presets: PresetContext,
        settings: AppSettings = .default,
        now: Date
    ) -> Reduction {
        var ctx = context
        let interval = presets.activePreset?.longBreakInterval ?? 4

        switch ctx.runState {
        case .idle, .pendingDecision:
            // Anything already waiting on a decision carries straight over. Committing it when the day turns
            // is tick()'s work (REQ-PER-004).
            return Reduction(context: ctx, presets: presets, effects: [])

        case .paused:
            // REQ-TIM-033: a pause has no end time. Left too long, it falls through to a question.
            guard let pausedAt = ctx.pausedAt,
                  now.timeIntervalSince(pausedAt) >= Double(settings.idleResetHours) * 3600 else {
                return Reduction(context: ctx, presets: presets, effects: [])
            }
            ctx = enterPendingDecision(ctx, reason: .pausedTooLong, endedAt: pausedAt, now: now)
            return Reduction(context: ctx, presets: presets, effects: pendingDecisionEffects)

        case .running, .finished:
            break
        }

        // (a) Already committed → restored as completed, in IDLE, and the log is not written again.
        //     By REQ-TIM-044 a break normally comes through here.
        if ctx.committedAt != nil {
            ctx.runState = .idle
            ctx.pendingDecision = nil
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        guard let endAt = ctx.sessionEndAt else {
            // An uncommitted session with no end time cannot be restored. It drops to IDLE and carries on.
            ctx.runState = .idle
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        // (b) Uncommitted, and the end time is still ahead → restored as it was, RUNNING.
        if now < endAt {
            ctx.runState = .running
            ctx.finishedAt = nil
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        // From here on, the end time passed while nobody was there.
        // Reaching FINISHED itself follows the same rules tick() uses.
        if ctx.runState == .running {
            ctx.finishedAt = endAt
            ctx.runState = .finished
            if ctx.sessionType == .work {
                let next = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: interval)
                ctx.loopCount += 1
                ctx.nextSessionType = next
            } else {
                ctx.nextSessionType = .work
            }
        }
        let finishedAt = ctx.finishedAt ?? endAt
        ctx.lastUpdatedAt = now

        // (c) Within the grace → WORK is restored still FINISHED. A break has no grace, so it is
        //     committed here (REQ-TIM-044).
        if now.timeIntervalSince(finishedAt) <= extensionGraceSeconds {
            if ctx.sessionType == .work {
                return Reduction(context: ctx, presets: presets, effects: [])
            }
            let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
            return Reduction(context: finalized, presets: presets, effects: effs)
        }

        // (d) Past the grace → ask. Until the answer comes, the loop count does not move and nothing
        //     is logged. The count added on reaching FINISHED is taken back here, for the reason
        //     REQ-TIM-042 gives.
        if ctx.sessionType == .work {
            ctx.loopCount = max(0, ctx.loopCount - 1)
            ctx.nextSessionType = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: interval)
        }
        ctx = enterPendingDecision(ctx, reason: .restoredAfterEnd, endedAt: finishedAt, now: now)
        return Reduction(context: ctx, presets: presets, effects: pendingDecisionEffects)
    }

    // MARK: - Transitions time makes on its own

    // REQ-TIM-010/020/043/044: reaching the end time, and the extension grace running out, take
    // effect with nobody having to do anything.
    public static func tick(
        context: TimerContext,
        presets: PresetContext,
        settings: AppSettings = .default,
        now: Date
    ) -> Reduction {
        var ctx = context
        var effects: [Effect] = []
        let interval = presets.activePreset?.longBreakInterval ?? 4

        if ctx.runState == .running, let endAt = ctx.sessionEndAt, now >= endAt {
            ctx.finishedAt = endAt
            ctx.runState = .finished
            ctx.lastUpdatedAt = now

            if ctx.sessionType == .work {
                // REQ-TIM-012/015/020: the next type is decided from the loopCount before the completion is
                // assumed, and only then is the count raised.
                let next = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: interval)
                ctx.loopCount += 1
                ctx.nextSessionType = next
                // WORK has a grace for extending, so nothing is committed here (REQ-TIM-043).
            } else {
                ctx.nextSessionType = .work
                // REQ-TIM-044: a break has no grace; it commits the moment it is reached.
                let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
                ctx = finalized
                effects.append(contentsOf: effs)
            }
        }

        // REQ-PER-004: if the logical day turns while the question raised at restore is still unanswered,
        // it commits as discard, which the log records as stopped. The time it sat there is not part of
        // the elapsed time (REQ-TIM-005), so the end time used is when the trouble was noticed.
        if ctx.runState == .pendingDecision, ctx.committedAt == nil,
           let pending = ctx.pendingDecision, pending.reason == .restoredAfterEnd,
           LogicalDay.date(for: now, dayStartHour: settings.logicalDayStartHour) != ctx.logicalDate {
            ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
            let (finalized, effs) = finalize(
                context: ctx, presets: presets, settings: settings, now: now,
                outcome: .aborted, endedAtOverride: pending.endedAt
            )
            ctx = finalized
            effects.append(contentsOf: effs)
        }

        if ctx.runState == .finished, ctx.sessionType == .work, ctx.committedAt == nil,
           let finishedAt = ctx.finishedAt, now.timeIntervalSince(finishedAt) > extensionGraceSeconds {
            // REQ-TIM-043: it commits the moment the grace runs out.
            let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
            ctx = finalized
            effects.append(contentsOf: effs)
        }

        return Reduction(context: ctx, presets: presets, effects: effects)
    }

    // MARK: - Applying an action

    public static func reduce(
        action: TimerAction,
        context: TimerContext,
        presets: PresetContext,
        settings: AppSettings = .default,
        now: Date
    ) -> Result<Reduction, TimerFailure> {
        let ticked = tick(context: context, presets: presets, settings: settings, now: now)
        var ctx = ticked.context
        var pr = ticked.presets
        var effects = ticked.effects

        // REQ-LOG-018: even on a refusal, the effects from the preceding tick() — and any gathered while
        // handling the action up to this point — are not lost.
        func fail(_ error: TimerError) -> Result<Reduction, TimerFailure> {
            .failure(TimerFailure(error: error, effects: effects))
        }

        guard canAccept(action, in: ctx.runState) else {
            return fail(.invalidStateForAction)
        }

        switch action {
        case let .startWork(presetId, taskSnapshot):
            guard let preset = pr.preset(id: presetId) else { return fail(.presetNotFound) }
            if ctx.runState == .finished {
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .completed)
                ctx = finalized
                effects.append(contentsOf: effs)
            }
            ctx = startSession(type: .work, preset: preset, settings: settings, now: now, context: ctx, taskSnapshot: taskSnapshot)

        case let .startBreak(type, presetId):
            guard type != .work else { return fail(.invalidStateForAction) }
            guard let preset = pr.preset(id: presetId) else { return fail(.presetNotFound) }
            if ctx.runState == .finished {
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .completed)
                ctx = finalized
                effects.append(contentsOf: effs)
            }
            ctx = startSession(type: type, preset: preset, settings: settings, now: now, context: ctx, taskSnapshot: nil)

        case .pause:
            // Rounded up, as the display rounds. Truncating would take a second off the remainder the instant
            // the timer was paused.
            ctx.remainingSeconds = max(0, Int((ctx.sessionEndAt ?? now).timeIntervalSince(now).rounded(.up)))
            ctx.pausedAt = now
            ctx.runState = .paused
            ctx.lastUpdatedAt = now

        case .resume:
            guard let pausedAt = ctx.pausedAt else { return fail(.invalidStateForAction) }
            let idleSeconds = now.timeIntervalSince(pausedAt)
            if idleSeconds >= Double(settings.idleResetHours) * 3600 {
                // REQ-TIM-033: a pause left too long does not resume on its own; it asks first.
                ctx = enterPendingDecision(ctx, reason: .pausedTooLong, endedAt: pausedAt, now: now)
                effects.append(contentsOf: pendingDecisionEffects)
            } else {
                // REQ-TIM-002: the end time is recalculated from "now + the remainder the pause held".
                // Nothing stands in for a missing remainder: now + 0 is the same shape as a session that
                // has just ended, so the very next tick() finishes it with nobody having touched
                // anything — work raises the loop count there and commits once the extension grace is
                // out, a break commits at once — and the session reaches `MdoroLog.md` as completed. The
                // long-pause branch above never reads the remainder, so it is left alone; only this one
                // refuses.
                guard let remaining = ctx.remainingSeconds else { return fail(.invalidStateForAction) }
                ctx.accumulatedPausedSeconds += Int(idleSeconds)
                ctx.sessionEndAt = now.addingTimeInterval(TimeInterval(remaining))
                ctx.remainingSeconds = nil
                ctx.pausedAt = nil
                ctx.runState = .running
                ctx.lastUpdatedAt = now
            }

        case .skip:
            // REQ-TIM-016: after a skip the suggestion is always SHORT_BREAK, when what was skipped was WORK.
            ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
            let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .skipped)
            ctx = finalized
            effects.append(contentsOf: effs)

        case .abort:
            if ctx.runState == .finished {
                // REQ-TIM-036: take back the loop count that was already added.
                ctx.loopCount = max(0, ctx.loopCount - 1)
            }
            ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
            let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .aborted)
            ctx = finalized
            effects.append(contentsOf: effs)

        case .extend:
            // REQ-TIM-044: a break cannot be extended.
            guard ctx.sessionType == .work else { return fail(.invalidStateForAction) }
            guard let activePreset = pr.activePreset else { return fail(.presetNotFound) }
            let extendSeconds = activePreset.extendSeconds
            // REQ-TIM-046: an extension outside the window is not accepted.
            guard isWithinExtensionWindow(ctx, now: now) else { return fail(.extendWindowClosed) }
            switch ctx.runState {
            case .running:
                ctx.sessionEndAt = (ctx.sessionEndAt ?? now).addingTimeInterval(TimeInterval(extendSeconds))
            case .paused:
                // REQ-TIM-002: while PAUSED the extension is added to the remainder the pause holds.
                // The window check above already turns a missing remainder away, so this is the second
                // door rather than the first. It stays shut anyway: a default that is only safe because
                // nothing can reach it comes back quietly the day the check upstream changes.
                guard let remaining = ctx.remainingSeconds else { return fail(.invalidStateForAction) }
                ctx.remainingSeconds = remaining + extendSeconds
            case .finished:
                // REQ-TIM-042: take back the loop count already added, then return to RUNNING.
                ctx.loopCount = max(0, ctx.loopCount - 1)
                ctx.nextSessionType = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: activePreset.longBreakInterval)
                ctx.sessionEndAt = (ctx.sessionEndAt ?? now).addingTimeInterval(TimeInterval(extendSeconds))
                ctx.finishedAt = nil
                ctx.runState = .running
            default:
                return fail(.invalidStateForAction)
            }
            ctx.extendedSeconds += extendSeconds
            ctx.lastUpdatedAt = now

        case .resetLoopCount:
            if ctx.runState == .running || ctx.runState == .paused || ctx.runState == .finished {
                if ctx.runState == .finished {
                    ctx.loopCount = max(0, ctx.loopCount - 1)
                }
                ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .aborted)
                ctx = finalized
                effects.append(contentsOf: effs)
            }
            // REQ-TIM-022(a) / REQ-TIM-012: after a deliberate reset it goes back to 0 and WORK.
            ctx.loopCount = 0
            ctx.nextSessionType = .work
            ctx.lastUpdatedAt = now

        case let .confirmRestoredSession(decision):
            guard let pending = ctx.pendingDecision else { return fail(.invalidStateForAction) }
            switch decision {
            case .continueSession:
                // REQ-TIM-033 raises this question from PAUSED, and nowhere else; PAUSED holds both the
                // moment the pause began and the remainder at that moment (REQ-TIM-002), and entering
                // PENDING_DECISION changes neither. Both are required here for the same reason as in
                // .resume — now + 0 is the same shape as a session that has just ended.
                guard pending.reason == .pausedTooLong,
                      let pausedAt = ctx.pausedAt,
                      let remaining = ctx.remainingSeconds else {
                    return fail(.invalidStateForAction)
                }
                ctx.accumulatedPausedSeconds += Int(now.timeIntervalSince(pausedAt))
                ctx.sessionEndAt = now.addingTimeInterval(TimeInterval(remaining))
                ctx.remainingSeconds = nil
                ctx.pausedAt = nil
                ctx.pendingDecision = nil
                ctx.runState = .running
                ctx.lastUpdatedAt = now
            case .complete:
                if ctx.sessionType == .work {
                    let next = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: pr.activePreset?.longBreakInterval ?? 4)
                    ctx.loopCount += 1
                    ctx.nextSessionType = next
                } else {
                    ctx.nextSessionType = .work
                }
                ctx.finishedAt = pending.endedAt
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .completed)
                ctx = finalized
                effects.append(contentsOf: effs)
            case .discard:
                ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
                // REQ-PER-004: the time it sat there is not part of the elapsed time. The end time used is
                // when the trouble was noticed (pending.endedAt), not now.
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .aborted, endedAtOverride: pending.endedAt)
                ctx = finalized
                effects.append(contentsOf: effs)
            }

        case let .updateSettings(updated):
            // REQ-PER-004: the boundary moved, but no day was crossed. The basis for the comparison is reset
            // so nothing commits by itself.
            if updated.logicalDayStartHour != settings.logicalDayStartHour {
                ctx.logicalDate = LogicalDay.date(for: now, dayStartHour: updated.logicalDayStartHour)
                ctx.lastUpdatedAt = now
            }

        case .selectTask, .clearTaskSelection, .reloadTasks:
            // Holding the task list is TaskContext's job. All that is guaranteed here is that the action is accepted.
            break

        case let .selectPreset(id):
            guard pr.preset(id: id) != nil else { return fail(.presetNotFound) }
            pr.activePresetId = id

        case let .updatePreset(updated):
            guard let old = pr.preset(id: updated.id) else { return fail(.presetNotFound) }
            guard updated.isWithinValidRanges() else { return fail(.settingOutOfRange) }
            guard !pr.hasNameConflict(updated.name, excluding: updated.id) else { return fail(.presetNameConflict) }
            if let idx = pr.presets.firstIndex(where: { $0.id == updated.id }) {
                pr.presets[idx] = updated
            }
            // REQ-CFG-017: a group A setting was edited on the preset the running session is using.
            let aGroupChanged = old.workSeconds != updated.workSeconds
                || old.shortBreakSeconds != updated.shortBreakSeconds
                || old.longBreakSeconds != updated.longBreakSeconds
            if updated.id == ctx.sessionPresetId, aGroupChanged,
               [.running, .paused, .finished].contains(ctx.runState) {
                ctx.presetEditedDuringSession = true
                ctx.lastUpdatedAt = now
            }

        case let .createPreset(newPreset):
            guard pr.presets.count < 10 else { return fail(.presetLimitReached) }
            guard newPreset.isWithinValidRanges() else { return fail(.settingOutOfRange) }
            guard !pr.hasNameConflict(newPreset.name) else { return fail(.presetNameConflict) }
            pr.presets.append(newPreset)

        case let .duplicatePreset(id):
            guard let original = pr.preset(id: id) else { return fail(.presetNotFound) }
            guard pr.presets.count < 10 else { return fail(.presetLimitReached) }
            var copy = original
            copy.id = UUID().uuidString
            copy.isBuiltInDefault = false
            copy.name = uniqueName(base: original.name, in: pr)
            pr.presets.append(copy)

        case let .deletePreset(id):
            guard pr.preset(id: id) != nil else { return fail(.presetNotFound) }
            guard pr.presets.count > 1 else { return fail(.cannotDeleteLastPreset) }
            guard id != pr.activePresetId else { return fail(.cannotDeleteActivePreset) }
            pr.presets.removeAll { $0.id == id }

        case let .reorderPresets(order):
            guard Set(order) == Set(pr.presets.map(\.id)) else { return fail(.invalidStateForAction) }
            pr.presets = order.compactMap { pr.preset(id: $0) }

        case .restoreDefaultPreset:
            guard pr.presets.count < 10 else { return fail(.presetLimitReached) }
            var preset = Preset.standard(id: UUID().uuidString)
            preset.name = uniqueName(base: "Standard", in: pr)
            pr.presets.append(preset)
        }

        return .success(Reduction(context: ctx, presets: pr, effects: effects))
    }

    // MARK: - Internal helpers

    // REQ-TIM-012/015: the next session, assuming the current one — or the one just past — completed
    // normally. The multiple is tested against loopCount + 1, the value after completion.
    static func standardNextSessionType(after type: SessionType, loopCount: Int, longBreakInterval: Int) -> SessionType {
        switch type {
        case .work:
            guard longBreakInterval > 0 else { return .shortBreak }
            return (loopCount + 1) % longBreakInterval == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }

    // REQ-TIM-005: the net working time, with the accumulated pauses taken out.
    static func computeElapsedSeconds(context: TimerContext, endedAt: Date) -> Int {
        guard let startedAt = context.sessionStartedAt else { return 0 }
        var paused = context.accumulatedPausedSeconds
        if context.runState == .paused, let pausedAt = context.pausedAt {
            paused += max(0, Int(endedAt.timeIntervalSince(pausedAt)))
        }
        return max(0, Int(endedAt.timeIntervalSince(startedAt)) - paused)
    }

    // REQ-LOG-018/019: committedAt makes this idempotent, and REQ-TIM-035 sends it on to IDLE.
    // endedAtOverride: for cases like REQ-PER-004, where the elapsed time should end at the moment
    // the trouble was noticed rather than at the moment of committing (now).
    static func finalize(
        context: TimerContext,
        presets: PresetContext,
        settings: AppSettings,
        now: Date,
        outcome: LogOutcome,
        endedAtOverride: Date? = nil
    ) -> (TimerContext, [Effect]) {
        // REQ-LOG-019: a non-nil committedAt means this session is committed. It does not commit twice.
        guard context.committedAt == nil else {
            return (context, [])
        }

        let endedAt: Date
        if let endedAtOverride {
            endedAt = endedAtOverride
        } else {
            switch outcome {
            case .completed:
                endedAt = context.finishedAt ?? context.sessionEndAt ?? now
            case .skipped, .aborted:
                endedAt = now
            }
        }

        let elapsed = computeElapsedSeconds(context: context, endedAt: endedAt)
        let interval = presets.activePreset?.longBreakInterval ?? 4

        // REQ-LOG-019: committedAt is set before the move to IDLE.
        var committed = context
        committed.committedAt = now

        var effects: [Effect] = []
        // REQ-TIM-032: net working time under 60 seconds is not logged.
        if elapsed >= 60, let startedAt = committed.sessionStartedAt {
            let entry = LogEntry(
                sessionType: committed.sessionType,
                startedAt: startedAt,
                endedAt: endedAt,
                elapsedSeconds: elapsed,
                outcome: outcome,
                presetName: committed.sessionPresetName ?? "",
                presetEditedDuringSession: committed.presetEditedDuringSession,
                taskSnapshot: committed.sessionType == .work ? committed.sessionTaskSnapshot : nil,
                extendedSeconds: committed.extendedSeconds,
                loopCountAfterCompletion: (outcome == .completed && committed.sessionType == .work) ? committed.loopCount : nil,
                longBreakInterval: interval,
                logicalDate: committed.logicalDate
            )
            effects.append(.commitLog(entry))
        }

        var idleContext = TimerContext.idle(now: now, settings: settings)
        idleContext.loopCount = committed.loopCount
        idleContext.nextSessionType = committed.nextSessionType
        idleContext.lastSessionEndedAt = now
        idleContext.committedAt = committed.committedAt
        return (idleContext, effects)
    }

    static func startSession(
        type: SessionType,
        preset: Preset,
        settings: AppSettings,
        now: Date,
        context: TimerContext,
        taskSnapshot: String?
    ) -> TimerContext {
        var ctx = context
        var loopCount = ctx.loopCount

        // REQ-TIM-022(b): idle for idleResetHours or more, and the count resets.
        if let lastEnded = ctx.lastSessionEndedAt, now.timeIntervalSince(lastEnded) >= Double(settings.idleResetHours) * 3600 {
            loopCount = 0
        }

        let newLogicalDate = LogicalDay.date(for: now, dayStartHour: settings.logicalDayStartHour)
        // REQ-TIM-022(c): the logical day changed, so the count resets.
        if newLogicalDate != ctx.logicalDate {
            loopCount = 0
        }

        let duration: Int
        switch type {
        case .work: duration = preset.workSeconds
        case .shortBreak: duration = preset.shortBreakSeconds
        case .longBreak: duration = preset.longBreakSeconds
        }

        ctx.sessionType = type
        ctx.runState = .running
        ctx.sessionStartedAt = now
        ctx.sessionEndAt = now.addingTimeInterval(TimeInterval(duration))
        ctx.remainingSeconds = nil
        ctx.pausedAt = nil
        ctx.accumulatedPausedSeconds = 0
        ctx.finishedAt = nil
        ctx.plannedDurationSeconds = duration
        ctx.extendedSeconds = 0
        ctx.loopCount = loopCount
        // REQ-TIM-013: the same rule recalculates it when a type is started against the suggestion.
        ctx.nextSessionType = standardNextSessionType(after: type, loopCount: loopCount, longBreakInterval: preset.longBreakInterval)
        ctx.logicalDate = newLogicalDate
        ctx.committedAt = nil
        ctx.sessionPresetId = preset.id
        ctx.sessionPresetName = preset.name
        ctx.presetEditedDuringSession = false
        ctx.pendingDecision = nil
        ctx.lastUpdatedAt = now
        ctx.sessionTaskSnapshot = (type == .work) ? taskSnapshot : nil
        return ctx
    }

    // REQ-PRS-012: a number is appended, and anything past 30 characters is cut from the end.
    // **What is cut is the base.** Trimming the whole to 30 would drop the number, leaving the
    // candidate equal to the base and the loop turning for ever.
    static func uniqueName(base: String, in presets: PresetContext) -> String {
        guard presets.hasNameConflict(base) else { return base }
        var suffix = 2
        while true {
            let suffixText = " \(suffix)"
            let maxBaseLength = max(0, 30 - suffixText.count)
            let truncatedBase = base.count > maxBaseLength ? String(base.prefix(maxBaseLength)) : base
            let candidate = truncatedBase + suffixText
            if !presets.hasNameConflict(candidate) {
                return candidate
            }
            suffix += 1
        }
    }
}
