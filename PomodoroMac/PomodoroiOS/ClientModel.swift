import Foundation
import SwiftUI
import Observation
import MdoroCore

// iPhone 側の状態保持。
//
// **セッションの完了を確定しない**（REQ-COM-012 / 3原則の2つ目）。
// 表示上のカウントダウンは続けてよいが、周回数の加算もログ記録も行わない。
// 判断はすべて Mac が行い、ここはその結果を映すだけ。
@MainActor
@Observable
final class ClientModel {

    // MARK: - 状態

    private(set) var snapshot: StateSnapshot?
    private(set) var taskList: TaskListPayload?
    private(set) var status: MdoroClient.Status = .idle
    private(set) var servers: [DiscoveredServer] = []
    private(set) var lastError: String?
    // REQ-PER-011: 永続化された状態を表示するときは取得時刻を併記する。
    private(set) var snapshotReceivedAt: Date?
    private(set) var localNetworkDenied = false
    private(set) var displayNow = Date()
    // REQ-NTF-011: 通知から起動した直後は、同期が取れるまで断定的に表示しない。
    private(set) var isAwaitingFirstSync = false
    // 問題があるときだけ理由を返す。正常時は nil。
    // **失敗を黙らせないこと。** 実機で「何も出ない」に何度も苦しめられた。
    var liveActivityProblem: String? { liveActivity.isHealthy ? nil : liveActivity.diagnostic }

    // 集中表示ビューを出しているか（REQ-UIX-013）。
    var isFocusViewPresented = false

    // REQ-COL-003 / Decision 0027: **外観はこの端末だけの設定。** Mac へは送らない。
    // 見ている画面の明るさは、見ている人の手元の事情で決まる。
    private(set) var appearance: AppearancePreference = .system

    private let client = MdoroClient()
    private let notifications = NotificationScheduler()
    private let liveActivity = LiveActivityController()
    // REQ-UIX-020: 開始できるのはフォアグラウンドにある間だけ。
    private var isForeground = true
    // **復元したスナップショット（REQ-PER-010）は、何時間前のものか分からない。**
    // Live Activity へ流してよいのは、接続中に受け取ったものだけである。
    // ここを見ずに流したため、終わったセッションが凍ったままロック画面に残っていた（2026-08-27、実機）。
    private var hasLiveSnapshot = false
    private let browser = ServerBrowser()
    private var ticker: Task<Void, Never>?

    // MARK: - 起動

    func start() {
        Task { await notifications.requestAuthorization() }
        // REQ-UIX-024: Live Activity のボタンはアプリ本体のプロセスで動く。
        // 送れなかったときに「送れた」と見せないよう、成否をそのまま返す。
        LiveActivityCommandBridge.handler = { [weak self] action in
            guard let self, self.isConnected else { return false }
            self.send(action)
            return true
        }
        // 前のプロセスが残した Live Activity は、接続できなければ畳む。
        // **復元したスナップショットで正当化しない**（それは何時間前のものか分からない）。
        liveActivity.discardOrphansIfUnconfirmed()
        restoreAppearance()
        restoreLastSnapshot()
        browser.onChange = { [weak self] found in
            self?.servers = found
            // 1台だけ見つかったなら黙って繋ぐ。複数なら選ばせる（REQ-ERR-005）。
            if found.count == 1, self?.status == .idle { self?.connect(to: found[0]) }
        }
        browser.onLocalNetworkDenied = { [weak self] in self?.localNetworkDenied = true }
        browser.start()
        startTicking()
    }

    func stop() {
        ticker?.cancel(); ticker = nil
        browser.stop()
        client.disconnect()
        liveActivity.end()
    }

    // REQ-UIX-020: バックグラウンド中に Mac 側で始まったセッションは、
    // フォアグラウンドへ復帰した時点で開始する。
    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        guard foreground, isConnected, hasLiveSnapshot, let snapshot else { return }
        liveActivity.sync(
            snapshot: snapshot, clockOffset: clockOffset,
            isForeground: true, isConnected: true, serverName: client.serverName ?? "Mac"
        )
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    guard let self else { return }
                    self.displayNow = Date()
                    self.refreshLiveActivityIfNeeded()
                }
            }
        }
    }

    // REQ-UIX-023: 接続が生きている限り「状態を確認できている」ので、staleDate を押し出す。
    // 切断中は押し出さない。確認できていないのだから、古い扱いで正しい。
    private func refreshLiveActivityIfNeeded() {
        guard isConnected, hasLiveSnapshot, let snapshot else { return }
        liveActivity.refreshIfNeeded(
            snapshot: snapshot, clockOffset: clockOffset,
            isForeground: isForeground, isConnected: true, serverName: client.serverName ?? "Mac"
        )
    }

    // MARK: - 接続

    func connect(to server: DiscoveredServer, pairingCode: String? = nil) {
        client.connect(to: server, pairingCode: pairingCode, callbacks: MdoroClient.Callbacks(
            statusChanged: { [weak self] status in
                guard let self else { return }
                self.status = status
                guard !self.isConnected else { return }
                // 切れたら Live Activity の操作を落とす（REQ-COM-013）。
                // **手元の状態は「最後に見た値」に落ちたので、これで新しく開始もしない。**
                self.hasLiveSnapshot = false
                self.liveActivity.setConnected(false)
            },
            receivedSnapshot: { [weak self] snapshot in
                guard let self else { return }
                self.snapshot = snapshot
                self.snapshotReceivedAt = Date()
                self.hasLiveSnapshot = true
                self.isAwaitingFirstSync = false
                self.persistSnapshot(snapshot)
                // REQ-NTF-003 / 009: 状態を受け取るたびに通知を組み直す。
                // 接続していない間に始まったセッションも、ここで初めて組まれる。
                self.notifications.reschedule(for: snapshot, clockOffset: self.clockOffset)
                // REQ-UIX-020 / 022: アプリが動いている間だけ Live Activity を追随させる。
                self.liveActivity.sync(
                    snapshot: snapshot, clockOffset: self.clockOffset,
                    isForeground: self.isForeground, isConnected: true,
                    serverName: self.client.serverName ?? "Mac"
                )
            },
            receivedTaskList: { [weak self] in self?.taskList = $0 },
            receivedEvent: { _ in },
            receivedError: { [weak self] in self?.lastError = $0.message },
            issuedToken: { token, serverName in
                TokenKeychain.save(token, serverName: serverName)
            }
        ))
    }

    func submitPairingCode(_ code: String) {
        guard let server = servers.first(where: { $0.name == connectedServerName }) ?? servers.first else { return }
        lastError = nil
        connect(to: server, pairingCode: code)
    }

    private var connectedServerName: String? { client.serverName }

    var isConnected: Bool { status == .connected }

    // REQ-UIX-004 / REQ-COM-013: 接続状態を常時視認できること。
    var connectionStatus: ConnectionStatus {
        switch status {
        case .connected: return .connected
        case .connecting, .reconnecting: return .reconnecting
        case .idle, .failed, .needsPairing: return .disconnected
        }
    }

    // MARK: - 残り時間

    // REQ-COM-009 / 011 / 012: サーバー時刻にオフセットを当てて算出する。
    // 表示は 00:00 に達しても、**完了として扱わない**。
    func remainingSeconds() -> Int {
        guard let timer = snapshot?.timer else { return 0 }
        switch timer.runState {
        case .running:
            guard let endAt = timer.sessionEndAt else { return 0 }
            let local = client.timeSync.localTime(forServerTime: endAt)
            return max(0, Int(local.timeIntervalSince(displayNow).rounded(.up)))
        case .paused:
            return max(0, timer.remainingSeconds ?? 0)
        case .finished, .idle, .pendingDecision:
            return 0
        }
    }

    // 表示が 00:00 に達したが Mac から次の状態が届いていない、という状態。
    // REQ-COM-012: ここで完了を確定してはならない。「同期待ち」として示す。
    var isAwaitingSync: Bool {
        guard let timer = snapshot?.timer, timer.runState == .running else { return false }
        return remainingSeconds() == 0
    }

    // REQ-ERR-007: 時計が大きくずれていたら警告する。
    var needsClockWarning: Bool { client.timeSync.needsClockWarning }

    private var clockOffset: TimeInterval { client.timeSync.offset }

    // REQ-NTF-011: 通知タップで起動したときに呼ぶ。
    func markAwaitingSync() { isAwaitingFirstSync = true }

    // MARK: - 操作

    // REQ-COM-013: 切断中は操作系 UI を無効化する。
    func send(_ action: CommandAction, params: CommandParams? = nil) {
        guard isConnected else { return }
        client.send(command: action, params: params)
    }

    // MARK: - ペアリングの解除

    // 覚えている Mac の名前。解除できるかの判定にも使う。
    var pairedServerName: String? {
        guard let name = client.serverName ?? servers.first?.name else { return nil }
        return TokenKeychain.load(serverName: name) == nil ? nil : name
    }

    // **端末の登録を捨てる。** 次につなぐときは、また6桁のコードから始まる。
    // 失うのはトークンだけで、タイマーの状態は Mac 側にある（3原則の2つ目）。
    func forgetPairedMac() {
        if let name = pairedServerName { TokenKeychain.delete(serverName: name) }
        client.disconnect()
        hasLiveSnapshot = false
        liveActivity.end()
        browser.start()
    }

    // MARK: - 外観（この端末だけの設定）

    private static let appearanceKey = "appearance"

    func setAppearance(_ new: AppearancePreference) {
        appearance = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.appearanceKey)
    }

    private func restoreAppearance() {
        guard let raw = UserDefaults.standard.string(forKey: Self.appearanceKey),
              let value = AppearancePreference(rawValue: raw) else { return }
        appearance = value
    }

    // MARK: - 永続化 (REQ-PER-010)

    private static let snapshotKey = "lastStateSnapshot"
    private static let snapshotAtKey = "lastStateSnapshotAt"

    private func persistSnapshot(_ snapshot: StateSnapshot) {
        guard let data = try? MessageCoder.encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        UserDefaults.standard.set(Date(), forKey: Self.snapshotAtKey)
    }

    // REQ-PER-010: 起動直後・未接続時は「最後に確認した状態」として表示する。
    private func restoreLastSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let restored = try? MessageCoder.decoder.decode(StateSnapshot.self, from: data) else { return }
        snapshot = restored
        snapshotReceivedAt = UserDefaults.standard.object(forKey: Self.snapshotAtKey) as? Date
    }
}
