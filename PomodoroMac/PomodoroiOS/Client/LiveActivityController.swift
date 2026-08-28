import Foundation
import ActivityKit
import Observation
import MdoroCore

// REQ-UIX-020 / 022 / 028 / Decision 0009: Live Activity の開始・更新・終了。
//
// 開始できるのは**フォアグラウンドにある間だけ**、更新できるのは**running である間だけ**。
// これはプラットフォームの制約であり、MUST に戻す実装を書かないこと。
@MainActor
@Observable
final class LiveActivityController {

    private var activity: Activity<MdoroActivityAttributes>?
    private var startedAt: Date?
    private var lastPushedAt: Date?
    // 最後に渡した内容と期限。接続が落ちたら内容だけ直して**期限は押し出さない**。
    private var lastState: MdoroActivityAttributes.ContentState?
    private var currentStaleDate: Date?

    // **何が起きたかを常に文字で残す。**「エラーが無い」と「呼ばれていない」は別物。
    private(set) var diagnostic: String = "Not started yet"
    // 正常に動いているときは黙る。問題があるときだけ画面に出す。
    private(set) var isHealthy = false

    // OS が把握している自アプリの Live Activity 数。
    var systemActivityCount: Int { Activity<MdoroActivityAttributes>.activities.count }

    // REQ-UIX-028: アクティブ8時間の上限。超えたら復帰時に新しく開始し直す。
    private static let maximumLifetime: TimeInterval = 8 * 60 * 60

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // 開始・更新・終了のどれかへ寄せる。
    //
    // `isConnected` は**呼び出し側の今の接続状態**。スナップショットの `connection` は
    // Mac が自分について語った値で、受け取れなくなった後も残り続ける。
    func sync(
        snapshot: StateSnapshot, clockOffset: TimeInterval,
        isForeground: Bool, isConnected: Bool, serverName: String
    ) {
        adoptOrphanedActivity()
        let timer = snapshot.timer

        // REQ-PER-009: PENDING_DECISION へ遷移した時点で終了させる。
        // REQ-UIX-022: セッション終了・中断時も終了させる。
        guard timer.runState == .running || timer.runState == .paused else {
            diagnostic = "No session running (\(timer.runState.rawValue))"
            isHealthy = true
            end()
            return
        }
        guard let serverStart = timer.sessionStartedAt else {
            diagnostic = "No start time"
            isHealthy = false
            end()
            return
        }

        let state = contentState(
            snapshot: snapshot, serverStart: serverStart,
            clockOffset: clockOffset, isConnected: isConnected
        )

        if let activity {
            if let startedAt, Date().timeIntervalSince(startedAt) > Self.maximumLifetime, isForeground {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                self.activity = nil
                start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
                return
            }
            diagnostic = "Updating (\(systemActivityCount) known to the system)"
            isHealthy = true
            push(state, extendingStaleDate: isConnected)
        } else {
            // REQ-UIX-020: フォアグラウンドでないと開始できない。背面で始まったものは復帰時にここへ来る。
            start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
        }
    }

    // REQ-COM-013 / REQ-UIX-024: 繋がっていないなら操作できるように見せない。
    // REQ-UIX-023: **`staleDate` は押し出さない。** 確認できていないのだから期限が来て正しい。
    func setConnected(_ connected: Bool) {
        guard activity != nil, var state = lastState, state.isConnected != connected else { return }
        state.isConnected = connected
        push(state, extendingStaleDate: false)
    }

    // 起動時にロック画面へ残っているものは、**今の状態かどうか確かめようがない。**
    // 少しだけ待ち、**来なければ畳む。** 走っていれば接続直後に開始し直される（REQ-UIX-020）。
    func discardOrphansIfUnconfirmed(within delay: TimeInterval = 10) {
        guard activity == nil, !Activity<MdoroActivityAttributes>.activities.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // この間に生きたスナップショットが来ていれば引き取られている。
            guard let self, self.activity == nil else { return }
            self.diagnostic = "Dismissed a leftover Live Activity: its state could not be confirmed"
            self.isHealthy = true
            self.end()
        }
    }

    // プロセスが落ちても Live Activity はロック画面に残る。
    // 拾い直さないと、**凍ったままの古い1件の横に新しい1件が並ぶ。**
    private func adoptOrphanedActivity() {
        guard activity == nil else { return }
        let existing = Activity<MdoroActivityAttributes>.activities
        guard let survivor = existing.first else { return }
        activity = survivor
        lastState = survivor.content.state
        // 本当の開始時刻は残っていない。REQ-UIX-028 の寿命はここから測り直す。
        startedAt = Date()
        lastPushedAt = nil
        // **期限なしで引き取らない。** 前のプロセスが置いた期限を引き継ぐ。
        currentStaleDate = survivor.content.staleDate
        // 2件以上あったら畳む。**1つの状態に2つの表示があってはならない。**
        for duplicate in existing.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
        diagnostic = "Adopted a leftover Live Activity (\(existing.count) found)"
        isHealthy = true
    }

    private func push(_ state: MdoroActivityAttributes.ContentState, extendingStaleDate: Bool) {
        lastState = state
        if extendingStaleDate {
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
            lastPushedAt = Date()
        }
        guard let activity else { return }
        // REQ-UIX-023: 期限が無いなら今この瞬間を期限にする。**期限なしで残さない。**
        let deadline = currentStaleDate ?? Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: deadline)) }
    }

    private func start(
        state: MdoroActivityAttributes.ContentState,
        serverName: String, isForeground: Bool, isConnected: Bool
    ) {
        // **状態の正本は Mac。** 繋がっていない間に手元にあるのは「最後に見た値」でしかない。
        // これで開始すると、**とうに終わったセッションが動かないままロック画面に居座る。**
        guard isConnected else {
            diagnostic = String(localized: "Starts once connected to your Mac")
            isHealthy = true
            return
        }
        // REQ-UIX-020: フォアグラウンドでないと開始できない（プラットフォーム制約）。
        guard isForeground else {
            // REQ-UIX-020 の制約であって不具合ではない。騒がない。
            diagnostic = String(localized: "Can only start while the app is in the foreground")
            isHealthy = true
            return
        }
        guard isSupported else {
            diagnostic = String(localized: "Live Activities are turned off in iOS Settings")
            isHealthy = false
            return
        }
        do {
            let requested = try Activity.request(
                attributes: MdoroActivityAttributes(serverName: serverName),
                content: content(state)
            )
            activity = requested
            startedAt = Date()
            lastPushedAt = Date()
            lastState = state
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
            diagnostic = "Started id=\(requested.id.prefix(8)) / \(systemActivityCount) known to the system"
            isHealthy = true
        } catch {
            diagnostic = "Could not start: \(String(describing: error))"
            isHealthy = false
        }
    }

    // REQ-UIX-023: staleDate は「次に確認できる保証がない時刻」であって経過時間ではない。
    // 回し続けないと、前面で接続が生きていても 90 秒で「情報が古い」と出る。
    // suspend されればこの呼び出しごと止まり、意図どおり陳腐化する。
    func refreshIfNeeded(
        snapshot: StateSnapshot, clockOffset: TimeInterval,
        isForeground: Bool, isConnected: Bool, serverName: String
    ) {
        guard activity != nil, let lastPushedAt else { return }
        guard Date().timeIntervalSince(lastPushedAt) >= MdoroActivityAttributes.staleRefreshInterval else { return }
        sync(
            snapshot: snapshot, clockOffset: clockOffset,
            isForeground: isForeground, isConnected: isConnected, serverName: serverName
        )
    }

    // **OS 上にあるものを全部畳む。** 1件だけだと前のプロセスの残骸が居座る。
    func end() {
        activity = nil
        startedAt = nil
        lastPushedAt = nil
        lastState = nil
        currentStaleDate = nil
        for existing in Activity<MdoroActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // REQ-UIX-023: 次に状態を確認できる保証がない時刻を staleDate に置く。
    private func content(_ state: MdoroActivityAttributes.ContentState) -> ActivityContent<MdoroActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
        )
    }

    private func contentState(
        snapshot: StateSnapshot, serverStart: Date, clockOffset: TimeInterval, isConnected: Bool
    ) -> MdoroActivityAttributes.ContentState {
        let timer = snapshot.timer
        let preset = snapshot.presets.activePreset ?? Preset.standard()

        // REQ-COM-009 / REQ-UIX-026: 拡張側では時計合わせができないので、ここで直して渡す。
        let localStart = serverStart.addingTimeInterval(-clockOffset)
        let localEnd: Date
        var pauseTime: Date?

        switch timer.runState {
        case .paused:
            // REQ-UIX-029: 停止中は pauseTime を置いてカウントダウンを止める。
            let remaining = TimeInterval(timer.remainingSeconds ?? 0)
            localEnd = Date().addingTimeInterval(remaining)
            pauseTime = Date()
        default:
            localEnd = (timer.sessionEndAt ?? Date()).addingTimeInterval(-clockOffset)
        }

        return MdoroActivityAttributes.ContentState(
            sessionType: timer.sessionType,
            sessionStartedAt: localStart,
            sessionEndAt: localEnd,
            pauseTime: pauseTime,
            loopDisplay: timer.displayLoop(longBreakInterval: preset.longBreakInterval),
            longBreakInterval: preset.longBreakInterval,
            taskName: timer.sessionTaskSnapshot ?? snapshot.task.selectedTaskSnapshot,
            // **スナップショットの中の接続状態ではない。** 要るのは、この端末が今どうかである。
            isConnected: isConnected
        )
    }
}
