import Foundation
import ActivityKit
import PomodoroCore

// REQ-UIX-020 / 022 / 028: Live Activity の開始・更新・終了。
//
// 開始できるのは**アプリがフォアグラウンドにある間だけ**、更新できるのは
// **アプリが running である間だけ**（`docs/CONTEXT.md` §3 の確定事項 / Decision 0009）。
// ここを MUST に戻す実装を書かないこと。
@MainActor
final class LiveActivityController {

    private var activity: Activity<PomodoroActivityAttributes>?
    private var startedAt: Date?

    // REQ-UIX-028: アクティブ8時間の上限。超えたら復帰時に新しく開始し直す。
    private static let maximumLifetime: TimeInterval = 8 * 60 * 60

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // スナップショットを受けて、開始・更新・終了のどれかへ寄せる。
    func sync(snapshot: StateSnapshot, clockOffset: TimeInterval, isForeground: Bool, serverName: String) {
        let timer = snapshot.timer

        // REQ-PER-009: PENDING_DECISION へ遷移した時点で終了させる。
        // REQ-UIX-022: セッション終了・中断時も終了させる。
        guard timer.runState == .running || timer.runState == .paused else {
            end()
            return
        }
        guard let serverStart = timer.sessionStartedAt else {
            end()
            return
        }

        let state = contentState(snapshot: snapshot, serverStart: serverStart, clockOffset: clockOffset)

        if let activity {
            // 上限を超えたぶんは作り直す。
            if let startedAt, Date().timeIntervalSince(startedAt) > Self.maximumLifetime, isForeground {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                self.activity = nil
                start(state: state, serverName: serverName, isForeground: isForeground)
                return
            }
            Task { await activity.update(content(state)) }
        } else {
            // REQ-UIX-020: フォアグラウンドでないと開始できない。
            // バックグラウンド中に Mac 側で始まったセッションは、復帰時にここで開始される。
            start(state: state, serverName: serverName, isForeground: isForeground)
        }
    }

    private func start(state: PomodoroActivityAttributes.ContentState, serverName: String, isForeground: Bool) {
        guard isForeground, isSupported else { return }
        activity = try? Activity.request(
            attributes: PomodoroActivityAttributes(serverName: serverName),
            content: content(state)
        )
        startedAt = Date()
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        startedAt = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // REQ-UIX-023: 次に状態を確認できる保証がない時刻を staleDate に置く。
    private func content(_ state: PomodoroActivityAttributes.ContentState) -> ActivityContent<PomodoroActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(PomodoroActivityAttributes.staleAfter)
        )
    }

    private func contentState(
        snapshot: StateSnapshot, serverStart: Date, clockOffset: TimeInterval
    ) -> PomodoroActivityAttributes.ContentState {
        let timer = snapshot.timer
        let preset = snapshot.presets.activePreset ?? Preset.standard()

        // REQ-COM-009: サーバー時刻を端末の時計へ直してから渡す。
        // 拡張側では時計合わせができない（REQ-UIX-026）。
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

        return PomodoroActivityAttributes.ContentState(
            sessionType: timer.sessionType,
            sessionStartedAt: localStart,
            sessionEndAt: localEnd,
            pauseTime: pauseTime,
            loopDisplay: timer.displayLoop(longBreakInterval: preset.longBreakInterval),
            longBreakInterval: preset.longBreakInterval,
            taskName: timer.sessionTaskSnapshot ?? snapshot.task.selectedTaskSnapshot,
            isConnected: snapshot.connection.isConnected
        )
    }
}
