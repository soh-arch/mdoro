import Foundation
import ActivityKit
import Observation
import PomodoroCore

// REQ-UIX-020 / 022 / 028: Live Activity の開始・更新・終了。
//
// 開始できるのは**アプリがフォアグラウンドにある間だけ**、更新できるのは
// **アプリが running である間だけ**（`docs/CONTEXT.md` §3 の確定事項 / Decision 0009）。
// ここを MUST に戻す実装を書かないこと。
// @Observable にしないと、状態が変わってもビューが読み直さない。
// 実機で「理由すら表示されない」状態になったのはこれが原因のひとつ。
@MainActor
@Observable
final class LiveActivityController {

    private var activity: Activity<PomodoroActivityAttributes>?
    private var startedAt: Date?
    private var lastPushedAt: Date?

    // **何が起きたかを常に文字で残す。**
    // 「エラーが無い」と「そもそも呼ばれていない」は別物で、
    // 後者を無表示にしていたため実機で切り分けられなかった。
    private(set) var diagnostic: String = "まだ開始していません"
    // 正常に動いているときは黙る。問題があるときだけ画面に出す。
    private(set) var isHealthy = false

    // OS が把握している自アプリの Live Activity 数。0 なら本当に存在しない。
    var systemActivityCount: Int { Activity<PomodoroActivityAttributes>.activities.count }

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
            diagnostic = "セッションが動いていません（\(timer.runState.rawValue)）"
            isHealthy = true
            end()
            return
        }
        guard let serverStart = timer.sessionStartedAt else {
            diagnostic = "開始時刻がありません"
            isHealthy = false
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
            diagnostic = "更新中（OS 上に \(systemActivityCount) 件）"
            isHealthy = true
            lastPushedAt = Date()
            Task { await activity.update(content(state)) }
        } else {
            // REQ-UIX-020: フォアグラウンドでないと開始できない。
            // バックグラウンド中に Mac 側で始まったセッションは、復帰時にここで開始される。
            start(state: state, serverName: serverName, isForeground: isForeground)
        }
    }

    private func start(state: PomodoroActivityAttributes.ContentState, serverName: String, isForeground: Bool) {
        // REQ-UIX-020: フォアグラウンドでないと開始できない（プラットフォーム制約）。
        guard isForeground else {
            // これは制約であって不具合ではない（REQ-UIX-020）。騒がない。
            diagnostic = String(localized: "アプリが前面にある間しか開始できません")
            isHealthy = true
            return
        }
        guard isSupported else {
            diagnostic = String(localized: "iOS の設定でライブアクティビティが無効です")
            isHealthy = false
            return
        }
        do {
            let requested = try Activity.request(
                attributes: PomodoroActivityAttributes(serverName: serverName),
                content: content(state)
            )
            activity = requested
            startedAt = Date()
            lastPushedAt = Date()
            diagnostic = "開始しました id=\(requested.id.prefix(8)) / OS 上に \(systemActivityCount) 件"
            isHealthy = true
        } catch {
            diagnostic = "開始に失敗: \(String(describing: error))"
            isHealthy = false
        }
    }

    // REQ-UIX-023: staleDate は「次に状態を確認できる保証がない時刻」であって、
    // 「最後に状態が変わってからの経過時間」ではない。
    // 状態が変わらないまま走り続けるセッションでもこちらを回し続けないと、
    // アプリが前面にあって接続も生きているのに 90 秒で「情報が古い」と出る。
    // 逆にアプリが suspend されればこの呼び出しごと止まり、意図どおり陳腐化する。
    func refreshIfNeeded(
        snapshot: StateSnapshot, clockOffset: TimeInterval, isForeground: Bool, serverName: String
    ) {
        guard activity != nil, let lastPushedAt else { return }
        guard Date().timeIntervalSince(lastPushedAt) >= PomodoroActivityAttributes.staleRefreshInterval else { return }
        sync(snapshot: snapshot, clockOffset: clockOffset, isForeground: isForeground, serverName: serverName)
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        startedAt = nil
        lastPushedAt = nil
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
