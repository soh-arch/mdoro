import Foundation

// REQ-TIM: 4章の状態機械。`canAccept` はマトリクス(4.6)のみを参照する純粋関数、
// `reduce` / `tick` が副作用(周回数・確定・延長など)を計算する。
// 実際のログ書き込み・通知・ファイル入出力は行わず、Effect として呼び出し側に委譲する。
public enum TimerEngine {
    // REQ-TIM-043: FINISHED の猶予はプリセット非依存の固定値。REQ-TIM-046 の受付ウィンドウと一致させる。
    public static let extensionGraceSeconds: TimeInterval = 60
    // REQ-TIM-046: RUNNING / PAUSED で延長を受け付ける残り時間の上限。
    public static let extensionWindowSeconds: TimeInterval = 5 * 60

    public struct Reduction: Equatable {
        public let context: TimerContext
        public let presets: PresetContext
        public let effects: [Effect]
    }

    public static func canAccept(_ action: TimerAction, in runState: RunState) -> Bool {
        StateTransitionMatrix.canAccept(action, in: runState)
    }

    // REQ-TIM-046: 延長受付ウィンドウ。RUNNING / PAUSED は残り 5 分以下、FINISHED は終了から 1 分以内。
    // 「押した時点」ではなく「区切りを意識している時点」でのみ延長できるようにするための制約 (Decision 0010)。
    public static func isWithinExtensionWindow(_ context: TimerContext, now: Date) -> Bool {
        switch context.runState {
        case .running:
            guard let endAt = context.sessionEndAt else { return false }
            return endAt.timeIntervalSince(now) <= extensionWindowSeconds
        case .paused:
            return TimeInterval(context.remainingSeconds ?? 0) <= extensionWindowSeconds
        case .finished:
            guard let finishedAt = context.finishedAt else { return false }
            return now.timeIntervalSince(finishedAt) <= extensionGraceSeconds
        default:
            return false
        }
    }

    // MARK: - PENDING_DECISION

    // REQ-PER-008 / 009: PENDING_DECISION へ入るときは、発火時刻を過ぎた通知を取り消し、
    // Live Activity を終了させる。再スケジュールは行わない。
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

    // MARK: - 起動時の復元 (REQ-PER-002 / 003)

    // 永続化された状態から復元する。tick() と分けているのは、`tick()` が
    // 「アプリが動き続けている前提」で猶予超過を完了として確定させるのに対し、
    // 復元時は不在中に終わっていたセッションを無条件に完了扱いしてはならないため (REQ-PER-003(d))。
    // 同じ経路を使うと、閉じている間に過ぎたセッションが黙って実績になる。
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
            // 既に判断待ちのものはそのまま引き継ぐ。日跨ぎの自動確定は tick() が扱う (REQ-PER-004)。
            return Reduction(context: ctx, presets: presets, effects: [])

        case .paused:
            // 一時停止は終了時刻を持たない。放置しすぎた場合の判定は resume 時の
            // REQ-TIM-033 と同じ規則で、ここでも先に確認へ倒す。
            guard let pausedAt = ctx.pausedAt,
                  now.timeIntervalSince(pausedAt) >= Double(settings.idleResetHours) * 3600 else {
                return Reduction(context: ctx, presets: presets, effects: [])
            }
            ctx = enterPendingDecision(ctx, reason: .pausedTooLong, endedAt: pausedAt, now: now)
            return Reduction(context: ctx, presets: presets, effects: pendingDecisionEffects)

        case .running, .finished:
            break
        }

        // (a) 確定済み → 完了しているものとして IDLE で復元し、ログを再度書かない。
        //     休憩は REQ-TIM-044 により通常この経路を通る。
        if ctx.committedAt != nil {
            ctx.runState = .idle
            ctx.pendingDecision = nil
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        guard let endAt = ctx.sessionEndAt else {
            // 終了時刻を持たない未確定セッションは復元しようがない。IDLE へ落として続行する。
            ctx.runState = .idle
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        // (b) 未確定かつ終了時刻が未来 → そのまま RUNNING で復元する。
        if now < endAt {
            ctx.runState = .running
            ctx.finishedAt = nil
            ctx.lastUpdatedAt = now
            return Reduction(context: ctx, presets: presets, effects: [])
        }

        // ここから先は「不在中に終了時刻を過ぎていた」場合。
        // FINISHED への到達そのものは tick() と同じ規則で反映する。
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

        // (c) 猶予内 → FINISHED のまま復元する。残り猶予は finishedAt から UI が算出する。
        //     ただし休憩には猶予がなく到達と同時に確定する (REQ-TIM-044) ため、WORK に限る。
        //     猶予を過ぎていない休憩は、待たせる理由がないのでここで確定させる。
        if now.timeIntervalSince(finishedAt) <= extensionGraceSeconds {
            if ctx.sessionType == .work {
                return Reduction(context: ctx, presets: presets, effects: [])
            }
            let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
            return Reduction(context: finalized, presets: presets, effects: effs)
        }

        // (d) 猶予超過 → 判断を仰ぐ。応答まで周回数を加算せずログも記録しない。
        //     FINISHED 到達時に加算した周回数はここで戻す (REQ-TIM-042 と同じ理由)。
        if ctx.sessionType == .work {
            ctx.loopCount = max(0, ctx.loopCount - 1)
            ctx.nextSessionType = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: interval)
        }
        ctx = enterPendingDecision(ctx, reason: .restoredAfterEnd, endedAt: finishedAt, now: now)
        return Reduction(context: ctx, presets: presets, effects: pendingDecisionEffects)
    }

    // MARK: - 時間経過による自動遷移

    // REQ-TIM-010/020/043/044: 終了時刻到達・延長猶予満了を、明示的な操作なしに反映する。
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
                // REQ-TIM-012/015/020: 完了と仮定する前の loopCount で次種別を決めてから加算する。
                let next = standardNextSessionType(after: .work, loopCount: ctx.loopCount, longBreakInterval: interval)
                ctx.loopCount += 1
                ctx.nextSessionType = next
                // WORK は延長猶予があるため、ここでは確定しない (REQ-TIM-043)。
            } else {
                ctx.nextSessionType = .work
                // REQ-TIM-044: 休憩には猶予がなく、到達と同時に確定する。
                let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
                ctx = finalized
                effects.append(contentsOf: effs)
            }
        }

        // REQ-PER-004: 復元時の確認が未応答のまま論理日が変われば、discard (中断扱い) として確定する。
        // 放置された実時間はログに含めない (REQ-TIM-005) ため、終了時刻は異常検知時点を使う。
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
            // REQ-TIM-043: 猶予超過時点で確定する。
            let (finalized, effs) = finalize(context: ctx, presets: presets, settings: settings, now: now, outcome: .completed)
            ctx = finalized
            effects.append(contentsOf: effs)
        }

        return Reduction(context: ctx, presets: presets, effects: effects)
    }

    // MARK: - 操作の適用

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

        // REQ-LOG-018: 拒否された場合でも、直前の tick() (および action 処理中にここまで積まれた) Effect は失わない。
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
            // 表示に合わせて切り上げる。表示側が切り上げ、ここが切り捨てだと、
            // 一時停止した瞬間に残り時間が1秒減って見える。
            ctx.remainingSeconds = max(0, Int((ctx.sessionEndAt ?? now).timeIntervalSince(now).rounded(.up)))
            ctx.pausedAt = now
            ctx.runState = .paused
            ctx.lastUpdatedAt = now

        case .resume:
            guard let pausedAt = ctx.pausedAt else { return fail(.invalidStateForAction) }
            let idleSeconds = now.timeIntervalSince(pausedAt)
            if idleSeconds >= Double(settings.idleResetHours) * 3600 {
                // REQ-TIM-033: 放置しすぎた一時停止は自動再開せず、確認を要求する。
                ctx = enterPendingDecision(ctx, reason: .pausedTooLong, endedAt: pausedAt, now: now)
                effects.append(contentsOf: pendingDecisionEffects)
            } else {
                ctx.accumulatedPausedSeconds += Int(idleSeconds)
                ctx.sessionEndAt = now.addingTimeInterval(TimeInterval(ctx.remainingSeconds ?? 0))
                ctx.remainingSeconds = nil
                ctx.pausedAt = nil
                ctx.runState = .running
                ctx.lastUpdatedAt = now
            }

        case .skip:
            // REQ-TIM-016: スキップ後の推奨は常に SHORT_BREAK (WORK の場合)。
            ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
            let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .skipped)
            ctx = finalized
            effects.append(contentsOf: effs)

        case .abort:
            if ctx.runState == .finished {
                // REQ-TIM-036: 加算済みの周回数を取り消す。
                ctx.loopCount = max(0, ctx.loopCount - 1)
            }
            ctx.nextSessionType = (ctx.sessionType == .work) ? .shortBreak : .work
            let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .aborted)
            ctx = finalized
            effects.append(contentsOf: effs)

        case .extend:
            // REQ-TIM-044: 休憩に延長はない。
            guard ctx.sessionType == .work else { return fail(.invalidStateForAction) }
            guard let activePreset = pr.activePreset else { return fail(.presetNotFound) }
            let extendSeconds = activePreset.extendSeconds
            // REQ-TIM-046: 受付ウィンドウ外の延長は受理しない。
            guard isWithinExtensionWindow(ctx, now: now) else { return fail(.extendWindowClosed) }
            switch ctx.runState {
            case .running:
                ctx.sessionEndAt = (ctx.sessionEndAt ?? now).addingTimeInterval(TimeInterval(extendSeconds))
            case .paused:
                ctx.remainingSeconds = (ctx.remainingSeconds ?? 0) + extendSeconds
            case .finished:
                // 猶予超過は tick() が先に確定させ、受付ウィンドウは上のガードが担保する。
                // REQ-TIM-042: 加算済みの周回数を取り消したうえで RUNNING へ戻す。
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
            // REQ-TIM-022(a) / REQ-TIM-012: 明示リセット後は 0 / WORK に戻す。
            ctx.loopCount = 0
            ctx.nextSessionType = .work
            ctx.lastUpdatedAt = now

        case let .confirmRestoredSession(decision):
            guard let pending = ctx.pendingDecision else { return fail(.invalidStateForAction) }
            switch decision {
            case .continueSession:
                guard pending.reason == .pausedTooLong, let pausedAt = ctx.pausedAt else {
                    return fail(.invalidStateForAction)
                }
                ctx.accumulatedPausedSeconds += Int(now.timeIntervalSince(pausedAt))
                ctx.sessionEndAt = now.addingTimeInterval(TimeInterval(ctx.remainingSeconds ?? 0))
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
                // REQ-PER-004: 実経過時間には放置していた実時間を含めない。now ではなく
                // 異常検知時点 (pending.endedAt) を終了時刻として使う。
                let (finalized, effs) = finalize(context: ctx, presets: pr, settings: settings, now: now, outcome: .aborted, endedAtOverride: pending.endedAt)
                ctx = finalized
                effects.append(contentsOf: effs)
            }

        case let .updateSettings(updated):
            // REQ-PER-004: `logicalDayStartHour` の設定変更に起因する logicalDate の変化では
            // PENDING_DECISION の自動確定を発火させてはならない。境界そのものが動いただけで、
            // 日をまたいだわけではないため、比較の基準を新しい境界へ張り替える。
            if updated.logicalDayStartHour != settings.logicalDayStartHour {
                ctx.logicalDate = LogicalDay.date(for: now, dayStartHour: updated.logicalDayStartHour)
                ctx.lastUpdatedAt = now
            }

        case .selectTask, .clearTaskSelection, .reloadTasks:
            // タスク一覧 (第6章) の保持は TaskContext の担当。
            // 状態遷移マトリクス上は常に受理されることのみをここで保証する。
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
            // REQ-CFG-017: 実行中セッションが使っているプリセットの A 群項目が編集された。
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

    // MARK: - 内部ヘルパー

    // REQ-TIM-012/015: 「現在(または直前)のセッションが正常完了したと仮定したときの次」。
    // 倍数判定は loopCount + 1 (完了後の値) に対して行う。
    static func standardNextSessionType(after type: SessionType, loopCount: Int, longBreakInterval: Int) -> SessionType {
        switch type {
        case .work:
            guard longBreakInterval > 0 else { return .shortBreak }
            return (loopCount + 1) % longBreakInterval == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }

    // REQ-TIM-005: 一時停止累計を差し引いた正味稼働時間。
    static func computeElapsedSeconds(context: TimerContext, endedAt: Date) -> Int {
        guard let startedAt = context.sessionStartedAt else { return 0 }
        var paused = context.accumulatedPausedSeconds
        if context.runState == .paused, let pausedAt = context.pausedAt {
            paused += max(0, Int(endedAt.timeIntervalSince(pausedAt)))
        }
        return max(0, Int(endedAt.timeIntervalSince(startedAt)) - paused)
    }

    // REQ-LOG-018/019: committedAt を見て冪等に確定し、REQ-TIM-035 に従って IDLE へ遷移する。
    // endedAtOverride: REQ-PER-004 のように、実際に確定した時刻 (now) ではなく
    // 異常を検知した時刻を実経過時間の終端として使いたい場合に指定する。
    static func finalize(
        context: TimerContext,
        presets: PresetContext,
        settings: AppSettings,
        now: Date,
        outcome: LogOutcome,
        endedAtOverride: Date? = nil
    ) -> (TimerContext, [Effect]) {
        // REQ-LOG-019: committedAt が非 nil ならこのセッションは確定済み。再確定しない。
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

        // REQ-LOG-019: IDLE へ遷移する前に committedAt を設定し、「確定済みのセッション」を
        // 呼び出し側が識別できるようにする。
        var committed = context
        committed.committedAt = now

        var effects: [Effect] = []
        // REQ-TIM-032: 正味稼働時間が60秒未満はログに記録しない。
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

        // REQ-TIM-022(b): 未使用時間が idleResetHours 以上ならリセット。
        if let lastEnded = ctx.lastSessionEndedAt, now.timeIntervalSince(lastEnded) >= Double(settings.idleResetHours) * 3600 {
            loopCount = 0
        }

        let newLogicalDate = LogicalDay.date(for: now, dayStartHour: settings.logicalDayStartHour)
        // REQ-TIM-022(c): 論理日が変化していたらリセット。
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
        // REQ-TIM-013: 推奨に従わず任意の種別を開始した場合も、この規則で再計算する。
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

    // REQ-PRS-012: 連番付与、30文字超は末尾切り詰め。
    // 切り詰めは base 側で行い、常に連番 (" \(suffix)") が残る余地を確保する。
    // base 側を削らずに丸ごと 30 文字へ切り詰めると、連番が失われて base と同一の
    // candidate になり、hasNameConflict が永久に真のままハングしていた。
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
