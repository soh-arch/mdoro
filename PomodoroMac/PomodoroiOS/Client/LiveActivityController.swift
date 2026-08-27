import Foundation
import ActivityKit
import Observation
import MdoroCore

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

    private var activity: Activity<MdoroActivityAttributes>?
    private var startedAt: Date?
    private var lastPushedAt: Date?
    // 最後に渡した内容と、そのときに置いた期限。
    // 接続が落ちたときは、内容だけ直して**期限は押し出さない**ために要る。
    private var lastState: MdoroActivityAttributes.ContentState?
    private var currentStaleDate: Date?

    // **何が起きたかを常に文字で残す。**
    // 「エラーが無い」と「そもそも呼ばれていない」は別物で、
    // 後者を無表示にしていたため実機で切り分けられなかった。
    private(set) var diagnostic: String = "まだ開始していません"
    // 正常に動いているときは黙る。問題があるときだけ画面に出す。
    private(set) var isHealthy = false

    // OS が把握している自アプリの Live Activity 数。0 なら本当に存在しない。
    var systemActivityCount: Int { Activity<MdoroActivityAttributes>.activities.count }

    // REQ-UIX-028: アクティブ8時間の上限。超えたら復帰時に新しく開始し直す。
    private static let maximumLifetime: TimeInterval = 8 * 60 * 60

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // スナップショットを受けて、開始・更新・終了のどれかへ寄せる。
    //
    // `isConnected` は**呼び出し側の今の接続状態**であり、スナップショットに入っている値ではない。
    // スナップショットの `connection` は Mac が自分について語った値で、
    // それを受け取れなくなった後も残り続ける。
    func sync(
        snapshot: StateSnapshot, clockOffset: TimeInterval,
        isForeground: Bool, isConnected: Bool, serverName: String
    ) {
        adoptOrphanedActivity()
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

        let state = contentState(
            snapshot: snapshot, serverStart: serverStart,
            clockOffset: clockOffset, isConnected: isConnected
        )

        if let activity {
            // 上限を超えたぶんは作り直す。
            if let startedAt, Date().timeIntervalSince(startedAt) > Self.maximumLifetime, isForeground {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                self.activity = nil
                start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
                return
            }
            diagnostic = "更新中（OS 上に \(systemActivityCount) 件）"
            isHealthy = true
            push(state, extendingStaleDate: isConnected)
        } else {
            // REQ-UIX-020: フォアグラウンドでないと開始できない。
            // バックグラウンド中に Mac 側で始まったセッションは、復帰時にここで開始される。
            start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
        }
    }

    // REQ-COM-013 / REQ-UIX-024: 繋がっていないなら、操作できるように見せない。
    //
    // **`staleDate` は押し出さない。** 状態を確認できなくなったのだから、
    // 期限が来て「情報が古い可能性があります」と出るのが正しい（REQ-UIX-023）。
    func setConnected(_ connected: Bool) {
        guard activity != nil, var state = lastState, state.isConnected != connected else { return }
        state.isConnected = connected
        push(state, extendingStaleDate: false)
    }

    // 起動時にロック画面へ残っているものは、**今の状態かどうか確かめようがない。**
    // 接続して状態を受け取れれば引き取って直せるので、少しだけ待つ。
    // **待って来なければ畳む。** 確かめられないものを、正しい顔で残しておかない。
    // セッションが本当に走っていれば、接続直後に開始し直される（REQ-UIX-020）。
    func discardOrphansIfUnconfirmed(within delay: TimeInterval = 10) {
        guard activity == nil, !Activity<MdoroActivityAttributes>.activities.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // この間に生きたスナップショットが来ていれば、引き取られている。
            guard let self, self.activity == nil else { return }
            self.diagnostic = "残っていた Live Activity を畳みました（状態を確認できなかったため）"
            self.isHealthy = true
            self.end()
        }
    }

    // アプリのプロセスが落ちても、Live Activity はロック画面に残る。
    // 起動し直したときに拾い直さないと、**凍ったままの古い1件の横に新しい1件が並ぶ。**
    // 引き取れば、次の更新でそのまま正しい内容へ戻せる。
    private func adoptOrphanedActivity() {
        guard activity == nil else { return }
        let existing = Activity<MdoroActivityAttributes>.activities
        guard let survivor = existing.first else { return }
        activity = survivor
        lastState = survivor.content.state
        // 本当の開始時刻は残っていない。8時間の寿命（REQ-UIX-028）はここから測り直す。
        startedAt = Date()
        lastPushedAt = nil
        // 前のプロセスが置いた期限をそのまま引き継ぐ。**期限なしで引き取らない。**
        currentStaleDate = survivor.content.staleDate
        // 2件以上あったら畳む。**1つの状態に2つの表示があってはならない。**
        for duplicate in existing.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
        diagnostic = "残っていた Live Activity を引き取りました（\(existing.count) 件）"
        isHealthy = true
    }

    private func push(_ state: MdoroActivityAttributes.ContentState, extendingStaleDate: Bool) {
        lastState = state
        if extendingStaleDate {
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
            lastPushedAt = Date()
        }
        guard let activity else { return }
        // 期限を持っていないなら、今この瞬間を期限にする。
        // **確認できていない状態を、期限なしで正しいものとして残さない**（REQ-UIX-023）。
        let deadline = currentStaleDate ?? Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: deadline)) }
    }

    private func start(
        state: MdoroActivityAttributes.ContentState,
        serverName: String, isForeground: Bool, isConnected: Bool
    ) {
        // **状態の正本は Mac**（3原則の2つ目）。繋がっていない間に手元にあるのは
        // 「最後に見た値」でしかなく、復元したスナップショット（REQ-PER-010）に至っては
        // 何時間前のものか分からない。これで開始すると、
        // **とうに終わったセッションが、正しい顔で、動かないままロック画面に居座る。**
        guard isConnected else {
            diagnostic = String(localized: "Mac に接続してから開始します")
            isHealthy = true
            return
        }
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
                attributes: MdoroActivityAttributes(serverName: serverName),
                content: content(state)
            )
            activity = requested
            startedAt = Date()
            lastPushedAt = Date()
            lastState = state
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
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

    // **OS 上にあるものを全部畳む。** 自分が握っている1件だけを畳むと、
    // 前のプロセスが残した残骸が凍ったまま居座る。
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

        return MdoroActivityAttributes.ContentState(
            sessionType: timer.sessionType,
            sessionStartedAt: localStart,
            sessionEndAt: localEnd,
            pauseTime: pauseTime,
            loopDisplay: timer.displayLoop(longBreakInterval: preset.longBreakInterval),
            longBreakInterval: preset.longBreakInterval,
            taskName: timer.sessionTaskSnapshot ?? snapshot.task.selectedTaskSnapshot,
            // **スナップショットの中の接続状態ではない。** そちらは Mac が自分について語った値で、
            // 受け取れなくなった後も真のまま残る。ここで要るのは、この端末が今どうかである。
            isConnected: isConnected
        )
    }
}
