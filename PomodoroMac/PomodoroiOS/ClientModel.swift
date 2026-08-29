import Foundation
import SwiftUI
import Observation
import MdoroCore

// The state the iPhone holds.
//
// **It does not settle a session as complete** (REQ-COM-012 / the second principle).
// The countdown may go on being shown, but the loop count is never added to and nothing is logged.
@MainActor
@Observable
final class ClientModel {

    // MARK: - State

    private(set) var snapshot: StateSnapshot?
    private(set) var taskList: TaskListPayload?
    private(set) var status: MdoroClient.Status = .idle
    private(set) var servers: [DiscoveredServer] = []
    // REQ-ERR-016 / 10.2 / Decision 0035: **a refusal that arrives goes on the screen.** Do not leave
    // behind a state where pressing something does nothing. Only the code is kept — `error.message` is
    // for diagnosis, and the Mac does not decide the wording on the iPhone's screen. The iPhone has no
    // diagnostic log (Decision 0018), so `message` is thrown away.
    private(set) var lastRefusal: ProtocolErrorCode?
    // REQ-PER-011: when a persisted state is shown, the time it was received is shown alongside it.
    private(set) var snapshotReceivedAt: Date?
    private(set) var localNetworkDenied = false
    private(set) var displayNow = Date()
    // REQ-NTF-011: right after launching from a notification, do not show anything as settled until a
    // sync has happened.
    private(set) var isAwaitingFirstSync = false
    // The reason comes back only when there is a problem. **Nothing fails quietly.**
    var liveActivityProblem: String? { liveActivity.isHealthy ? nil : liveActivity.diagnostic }

    // Whether the focus view is being shown (REQ-UIX-013).
    var isFocusViewPresented = false

    // REQ-COL-003 / Decision 0027: **the appearance is a setting for this device alone.** It is not sent to the Mac.
    private(set) var appearance: AppearancePreference = .system

    private let client = MdoroClient()
    private let notifications = NotificationScheduler()
    private let liveActivity = LiveActivityController()
    // REQ-UIX-020 gates the Live Activity's start on this; facts: docs/PLATFORM.md.
    private var isForeground = true
    // **There is no telling how many hours old a restored snapshot (REQ-PER-010) is.**
    // Only what was received while connected may be passed to the Live Activity.
    private var hasLiveSnapshot = false
    private let browser = ServerBrowser()
    private var ticker: Task<Void, Never>?

    // MARK: - Launch

    func start() {
        Task { await notifications.requestAuthorization() }
        // A Live Activity the previous process left behind is folded away if no connection can be made.
        liveActivity.discardOrphansIfUnconfirmed()
        restoreAppearance()
        restoreLastSnapshot()
        browser.onChange = { [weak self] found in
            self?.servers = found
            // REQ-ERR-005: with one, connect quietly; with more than one, let the user choose.
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

    // REQ-UIX-020: a session that began in the background is started on return.
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

    // REQ-UIX-023: staleDate is pushed out only while the connection is alive. While disconnected,
    // being treated as old is correct.
    private func refreshLiveActivityIfNeeded() {
        guard isConnected, hasLiveSnapshot, let snapshot else { return }
        liveActivity.refreshIfNeeded(
            snapshot: snapshot, clockOffset: clockOffset,
            isForeground: isForeground, isConnected: true, serverName: client.serverName ?? "Mac"
        )
    }

    // MARK: - Connection

    func connect(to server: DiscoveredServer, pairingCode: String? = nil) {
        client.connect(to: server, pairingCode: pairingCode, callbacks: MdoroClient.Callbacks(
            statusChanged: { [weak self] status in
                guard let self else { return }
                self.status = status
                guard !self.isConnected else { return }
                // REQ-COM-013: when it drops, the controls go. **Nor is a new one started from the values at hand.**
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
                // REQ-NTF-003 / 009: the notifications are rebuilt each time a state arrives.
                self.notifications.reschedule(for: snapshot, clockOffset: self.clockOffset)
                // REQ-UIX-020 / 022: the Live Activity follows along only while the app is running.
                self.liveActivity.sync(
                    snapshot: snapshot, clockOffset: self.clockOffset,
                    isForeground: self.isForeground, isConnected: true,
                    serverName: self.client.serverName ?? "Mac"
                )
            },
            receivedTaskList: { [weak self] in self?.taskList = $0 },
            receivedEvent: { _ in },
            receivedError: { [weak self] in self?.lastRefusal = $0.code },
            issuedToken: { token, serverName in
                TokenKeychain.save(token, serverName: serverName)
            }
        ))
    }

    func submitPairingCode(_ code: String) {
        guard let server = servers.first(where: { $0.name == connectedServerName }) ?? servers.first else { return }
        lastRefusal = nil
        connect(to: server, pairingCode: code)
    }

    private var connectedServerName: String? { client.serverName }

    var isConnected: Bool { status == .connected }

    // REQ-UIX-004 / REQ-COM-013: the connection state must be visible at all times.
    var connectionStatus: ConnectionStatus {
        switch status {
        case .connected: return .connected
        case .connecting, .reconnecting: return .reconnecting
        case .idle, .failed, .needsPairing: return .disconnected
        }
    }

    // MARK: - Remaining time

    // REQ-COM-009 / 011 / 012: the offset is applied to the server's time. **Even at 00:00 it is not
    // treated as complete.**
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

    // REQ-COM-012: reaching 00:00 must not settle it as complete. It is shown as "waiting for sync".
    var isAwaitingSync: Bool {
        guard let timer = snapshot?.timer, timer.runState == .running else { return false }
        return remainingSeconds() == 0
    }

    // REQ-ERR-007: warn when the clocks are far apart.
    var needsClockWarning: Bool { client.timeSync.needsClockWarning }

    private var clockOffset: TimeInterval { client.timeSync.offset }

    // REQ-NTF-011: called when the app was launched by tapping a notification.
    func markAwaitingSync() { isAwaitingFirstSync = true }

    // MARK: - Actions

    // REQ-COM-013: while disconnected, the controls are disabled.
    func send(_ action: CommandAction, params: CommandParams? = nil) {
        guard isConnected else { return }
        // REQ-ERR-016: the moment the next command goes out, the previous refusal is over.
        // If the same command is refused again, it comes back out as the response.
        lastRefusal = nil
        client.send(command: action, params: params)
    }

    // REQ-ERR-016: only the user can say it has been read. **Do not clear it after a time.**
    func acknowledgeRefusal() { lastRefusal = nil }

    // MARK: - Unpairing

    // The name of the Mac that is remembered.
    var pairedServerName: String? {
        guard let name = client.serverName ?? servers.first?.name else { return nil }
        return TokenKeychain.load(serverName: name) == nil ? nil : name
    }

    // **Throws this device's registration away.** All that is lost is the token; the timer's state is on the Mac.
    func forgetPairedMac() {
        if let name = pairedServerName { TokenKeychain.delete(serverName: name) }
        client.disconnect()
        hasLiveSnapshot = false
        liveActivity.end()
        browser.start()
    }

    // MARK: - Appearance (a setting for this device alone)

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

    // MARK: - Persistence (REQ-PER-010)

    private static let snapshotKey = "lastStateSnapshot"
    private static let snapshotAtKey = "lastStateSnapshotAt"

    private func persistSnapshot(_ snapshot: StateSnapshot) {
        guard let data = try? MessageCoder.encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        UserDefaults.standard.set(Date(), forKey: Self.snapshotAtKey)
    }

    // REQ-PER-010: right after launch and while not connected, it is shown as "the state last confirmed".
    private func restoreLastSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let restored = try? MessageCoder.decoder.decode(StateSnapshot.self, from: data) else { return }
        snapshot = restored
        snapshotReceivedAt = UserDefaults.standard.object(forKey: Self.snapshotAtKey) as? Date
    }
}
