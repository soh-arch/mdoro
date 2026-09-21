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
    // REQ-PER-011 / REQ-NTF-011: **nothing on this screen is settled until a `stateSnapshot` has
    // arrived over a live connection.** Raised wherever a state that was not received this run goes
    // on show — the snapshot restored from disk (REQ-PER-010) and a launch from a notification —
    // and `receivedSnapshot` is the only thing that puts it back down.
    private(set) var isAwaitingFirstSync = false
    // The reason comes back only when there is a problem. **Nothing fails quietly.**
    var liveActivityProblem: String? { liveActivity.isHealthy ? nil : liveActivity.diagnostic }

    // Whether the focus view is being shown (REQ-UIX-013).
    var isFocusViewPresented = false

    // REQ-COL-003 / Decision 0027: **the appearance is a setting for this device alone.** It is not sent to the Mac.
    private(set) var appearance: AppearancePreference = .system

    // REQ-SEC-002 / Decision 0040: the Keychain is outside this process. **The default is the same
    // as production**, and only when it is replaced does a test write into the reader's own.
    private let tokens: any TokenStoring
    // REQ-PER-010: where the last snapshot and this device's own settings are kept. **The default is
    // the same as production**, the way the Keychain above is: the suite runs inside this app, so
    // `.standard` is the user's own store, and a test that seeds a snapshot replaces this instead.
    private let defaults: UserDefaults
    // **Where the client the app runs is made.** REQ-COM-005's five seconds are whatever is — or,
    // as here, is not — passed to it, so `SilenceDetectionTests` reads the interval back off this
    // property rather than off a client it built to the same initializer.
    let client: MdoroClient
    private let notifications = NotificationScheduler()
    private let liveActivity = LiveActivityController()
    // REQ-UIX-020 gates the Live Activity's start on this; facts: docs/PLATFORM.md.
    private var isForeground = true
    // **There is no telling how many hours old a restored snapshot (REQ-PER-010) is.**
    // Only what was received while connected may be passed to the Live Activity.
    private var hasLiveSnapshot = false
    private let browser = ServerBrowser()
    private var ticker: Task<Void, Never>?
    // Whether the app has been started. **`start()` was not idempotent**: `browser.start()` and
    // `startTicking()` fold whatever stood before them, and nothing above them does. A second pass
    // would ask for notification permission again, open a second ten-second sweep for a leftover
    // Live Activity, and — the one that could be seen — read the stored snapshot back over what
    // the screen is already showing.
    //
    // **Whether a second pass happens is not established here.** The one call site is the `.task`
    // on `MdoroiOSApp`'s root view; how often SwiftUI runs it is not written down anywhere in
    // `docs/platform/`, and nothing in this repository has measured it. The guard does not rest on
    // that: **an entrance that folds its own repetition is right whatever the count turns out to
    // be**, and the count is the part that could change under us.
    //
    // The Mac carries the same guard on `AppModel.start()`, where the repetition *was* measured —
    // a second listener and a second Bonjour registration on the user's machine. A hole found on
    // one platform is looked for on the other.
    //
    // `stop()` puts this back, so a deliberate restart still works; only repetition is refused.
    private var hasStarted = false

    init(tokens: any TokenStoring = TokenKeychain(), defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
        self.client = MdoroClient(tokens: tokens)
    }

    // MARK: - Launch

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
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
        // What has been taken down may be raised again. Only repetition is refused, not restart.
        hasStarted = false
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
            issuedToken: { [weak self] token, serverId in
                self?.tokens.save(token, serverId: serverId)
            }
        ))
    }

    // Decision 0040: **the code goes back to the Mac that asked for it.** Looking the target up by
    // matching `$0.name` (the Bonjour instance name) against `client.serverName` (what the Mac
    // called itself in `welcome`) is a match across two different name spaces that share a variable
    // name, and it falls through to `servers.first` whenever they do not agree — which is every time
    // the two differ and any time two Macs are listed. The client already knows which one it is
    // dialling; nothing has to be matched at all.
    func submitPairingCode(_ code: String) {
        guard let server = client.target ?? servers.first else { return }
        lastRefusal = nil
        connect(to: server, pairingCode: code)
    }

    // REQ-COM-004 / REQ-PRT-004: **dialling again, with nothing new to send.** A refusal stops the
    // client for good, which is right for an answer the Mac meant — but two of those answers are
    // ones a second attempt may get past on its own, and **neither of them is mended by six
    // digits**: a Mac whose user did not approve this connection, and a version the user has since
    // updated one end of.
    //
    // Without this there is no way back from either short of quitting the app: `stopDialling`
    // cancels the reconnect, `connect` is the only thing that clears the flag it sets, and the
    // browser dials by itself only out of `.idle`.
    //
    // It is `submitPairingCode` with the code left out — the same target, and the token already
    // held goes back out as it stands. **Nothing loops**: this runs when the user presses it, and a
    // Mac that has not changed its mind refuses again.
    func redial() {
        guard let server = client.target ?? servers.first else { return }
        lastRefusal = nil
        connect(to: server)
    }

    var isConnected: Bool { status == .connected }

    // REQ-UIX-004 / REQ-COM-013: the connection state must be visible at all times.
    var connectionStatus: ConnectionStatus {
        switch status {
        case .connected: return .connected
        case .connecting, .reconnecting: return .reconnecting
        // REQ-COM-004: a refusal is one of the ways of not being connected, the same as the rest.
        // **And it stays that way**: nothing is dialling any more, so `.reconnecting` would be a
        // spinner over a line nobody is trying to open.
        case .idle, .failed, .refused, .needsPairing: return .disconnected
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

    // REQ-NTF-011: called when the app was launched by tapping a notification. **No longer the only
    // way in** — `restoreLastSnapshot()` raises the same flag for REQ-PER-011, which covers the
    // launches that went through no notification at all.
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

    // REQ-SEC-002 / Decision 0040: the Mac this iPhone holds a token for — **found by id, shown
    // by name.**
    //
    // The id comes from the TXT record of a Mac that is on the air; the name is whatever that Mac
    // is calling itself. Neither is used to find the other. When no Mac is answering there is
    // nothing to show and nothing to forget, which is the state this was already in.
    private var pairedMac: (serverId: ServerID, name: String)? {
        if let target = client.target, let serverId = target.serverId,
           tokens.load(serverId: serverId) != nil {
            // `welcome.serverName` once it has arrived; until then, the name it is advertising under.
            return (serverId, client.serverName ?? target.name)
        }
        for server in servers {
            guard let serverId = server.serverId, tokens.load(serverId: serverId) != nil else { continue }
            return (serverId, server.name)
        }
        return nil
    }

    // The name of the Mac that is remembered.
    var pairedServerName: String? { pairedMac?.name }

    // **Throws this device's registration away.** All that is lost is the token; the timer's state is on the Mac.
    func forgetPairedMac() {
        if let paired = pairedMac { tokens.delete(serverId: paired.serverId) }
        client.disconnect()
        hasLiveSnapshot = false
        liveActivity.end()
        browser.start()
    }

    // MARK: - Appearance (a setting for this device alone)

    private static let appearanceKey = "appearance"

    func setAppearance(_ new: AppearancePreference) {
        appearance = new
        defaults.set(new.rawValue, forKey: Self.appearanceKey)
    }

    private func restoreAppearance() {
        guard let raw = defaults.string(forKey: Self.appearanceKey),
              let value = AppearancePreference(rawValue: raw) else { return }
        appearance = value
    }

    // MARK: - Persistence (REQ-PER-010)

    private static let snapshotKey = "lastStateSnapshot"
    private static let snapshotAtKey = "lastStateSnapshotAt"

    private func persistSnapshot(_ snapshot: StateSnapshot) {
        guard let data = try? MessageCoder.encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
        defaults.set(Date(), forKey: Self.snapshotAtKey)
    }

    // REQ-PER-010: right after launch and while not connected, it is shown as "the state last confirmed".
    //
    // **The app reaches this through `start()`; it is not private so that the suite can read what it
    // leaves behind** without browsing for Bonjour services, asking for notification permission or
    // opening a Live Activity on the reader's phone.
    func restoreLastSnapshot() {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let restored = try? MessageCoder.decoder.decode(StateSnapshot.self, from: data) else { return }
        snapshot = restored
        snapshotReceivedAt = defaults.object(forKey: Self.snapshotAtKey) as? Date
        // REQ-PER-011: **how many hours old this is, is not known here** — the same reason
        // `hasLiveSnapshot` stays down. So the screen says it is not synced yet from the moment the
        // restored state goes on it, **whatever route the launch took.** Raising it only from the
        // notification tap (`markAwaitingSync`) left the user who simply opened the app to read the
        // age off the received-at time beside a state shown as if it stood. `receivedSnapshot` is
        // what puts it back down.
        isAwaitingFirstSync = true
    }
}
