import Foundation
import MdoroCore

// REQ-ERR-009: a broken message is thrown away on its own, but ten in a row say the line itself
// is no good, not the one message. Counting is the whole of it — the reconnect belongs to the client.
struct BrokenMessageCounter {
    // REQ-ERR-009: "ten in a row". The number the requirement names, in one place.
    static let limit = 10

    private(set) var count = 0

    // True when this failure is the tenth in a row, and the count starts over at that point:
    // anything still in flight on the doomed connection must not ask for a second reconnect.
    mutating func recordBroken() -> Bool {
        count += 1
        guard count >= Self.limit else { return false }
        count = 0
        return true
    }

    // A message that decodes puts the count back to zero — the requirement says *in a row*.
    mutating func reset() {
        count = 0
    }
}

// REQ-COM-001: the iPhone is the child (the client).
// **It does not settle a session as complete** (REQ-COM-012). It only passes the state it receives straight up.
@MainActor
final class MdoroClient {

    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting
        case failed(AuthFailureCode)
        case needsPairing
    }

    struct Callbacks {
        var statusChanged: (Status) -> Void
        var receivedSnapshot: (StateSnapshot) -> Void
        var receivedTaskList: (TaskListPayload) -> Void
        var receivedEvent: (SessionEventPayload) -> Void
        var receivedError: (ProtocolErrorPayload) -> Void
        // Decision 0040: the token, and the id it belongs to. **Never a name** — the Mac's name
        // is the user's to change and the OS's to rewrite, and this is what the token is filed
        // under.
        var issuedToken: (String, ServerID) -> Void
    }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { callbacks?.statusChanged(status) } }
    }
    private(set) var timeSync = TimeSyncEstimator()
    // What the Mac calls itself (`welcome.serverName`, 9.3 `displayName`). **For showing, and
    // for nothing else** — it is not looked up by, compared on, or saved under.
    private(set) var serverName: String?

    private var link: (any MessageLink)?
    private var callbacks: Callbacks?
    private var backoff = ReconnectPolicy()
    // The Mac being dialled. Readable so the model does not have to guess which of the
    // discovered rows a pairing code belongs to — it used to match on names from two different
    // name spaces and fall through to `servers.first`.
    private(set) var target: DiscoveredServer?
    private var pairingCode: String?
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStopping = false
    private var brokenMessages = BrokenMessageCounter()
    // REQ-COM-005: when something last arrived. `Heartbeat.isStale` reads it against the clock
    // below, and nothing else does.
    private var lastReceivedAt: Date?
    // REQ-COM-005: how many times the keepalive has come round. **Every other effect the loop has
    // goes out through `link`** — the beat is sent on it, the silence is acted on by cancelling it
    // — and a line let go is a `link` of nil, so a loop that is still turning and a loop that has
    // stopped look alike from outside unless the rounds themselves are counted.
    //
    // The injected clock is read once a round too, and can be counted instead — **but only while
    // `endLineIfSilent` reads it before it reaches for `link`.** Order those two the other way and
    // the reading disappears for exactly the loop that must not be turning. **This count rests on
    // no ordering of statements**: the round happened, or it did not.
    private(set) var beats = 0

    private let deviceName = "iPhone"
    // POL-047 / Decision 0040: the Keychain is outside this process, and the suite runs inside
    // this app. **The default is the same as production.**
    private let tokens: any TokenStoring
    // REQ-ERR-009 / REQ-COM-004: the same seam, for the line itself. **The default is the same as
    // production**, so only a test ever opens anything other than a WebSocket over the LAN.
    private let links: any ClientLinkMaking
    // REQ-COM-005: the clock the fifteen seconds of silence are measured on, and **only that**.
    // The time-sync samples keep their own `Date()` on purpose: they measure the wire between the
    // two devices (REQ-COM-008), and a clock a test can move would rewrite the offset estimate.
    private let clock: () -> Date
    // REQ-COM-005: how often a heartbeat goes out and the silence is looked at. The requirement's
    // five seconds is the default; a test shortens it so the wiring can be driven in milliseconds.
    // **The fifteen-second threshold is not here** — that is `Heartbeat.timeout`, shared with the Mac.
    let heartbeatInterval: TimeInterval

    init(
        tokens: any TokenStoring = TokenKeychain(),
        links: any ClientLinkMaking = WebSocketLinks(),
        clock: @escaping () -> Date = { Date() },
        heartbeatInterval: TimeInterval = Heartbeat.interval
    ) {
        self.tokens = tokens
        self.links = links
        self.clock = clock
        self.heartbeatInterval = heartbeatInterval
    }

    // MARK: - Connection

    func connect(to server: DiscoveredServer, pairingCode: String? = nil, callbacks: Callbacks) {
        self.callbacks = callbacks
        self.target = server
        self.pairingCode = pairingCode
        isStopping = false
        openConnection()
    }

    func disconnect() {
        isStopping = true
        keepaliveTask?.cancel(); keepaliveTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        link?.cancel(); link = nil
        status = .idle
    }

    private func openConnection() {
        guard let target, let link = links.makeLink(to: target) else { return }
        status = (status == .connected) ? .reconnecting : .connecting
        // REQ-ERR-009: every connection counts its own broken messages from zero.
        brokenMessages.reset()

        self.link = link
        link.start { [weak self] event in
            guard let self else { return }
            switch event {
            case .ready: self.sendHello()
            case let .message(data): self.handle(data)
            case .ended: self.scheduleReconnect()
            }
        }
    }

    // REQ-COM-004: reconnect with exponential backoff (one second the first time, thirty seconds at most).
    private func scheduleReconnect() {
        guard !isStopping else { return }
        keepaliveTask?.cancel(); keepaliveTask = nil
        link = nil
        if status == .connected { status = .reconnecting }

        let delay = backoff.nextDelay()
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.openConnection() }
        }
    }

    private func sendHello() {
        // Decision 0040: **the id, not the name.** A Mac advertising without one is a version
        // that cannot be paired with; it gets as far as the version check and is refused there.
        let token = target?.serverId.flatMap { tokens.load(serverId: $0) }
        // With neither a token nor a code, ask for one to be entered.
        if token == nil, pairingCode == nil {
            status = .needsPairing
            return
        }
        send(.hello(HelloPayload(deviceToken: token, pairingCode: pairingCode, deviceName: deviceName)))
    }

    // MARK: - Receiving

    private func handle(_ data: Data) {
        // REQ-COM-005: **anything that arrives is proof the Mac is still there.** 10.2 gives the
        // server no heartbeat of its own to send back, so what is counted is receipt itself and
        // not a message of one kind; rubbish counts too, since a peer that emits it is answering
        // (what to do about ten of those in a row is REQ-ERR-009's, below).
        lastReceivedAt = clock()

        let decoded: Envelope<ServerMessage>?
        do {
            decoded = try MessageCoder.decodeServer(data)
        } catch {
            // REQ-ERR-009: a broken message is thrown away and the connection is kept —
            // until ten have come in a row, and then the connection is made again.
            if brokenMessages.recordBroken() {
                // **The backoff is left where it is, on purpose.** REQ-COM-004 winds it back on a
                // `welcome`, which is the only proof the line carries this protocol again. A peer
                // that emits rubbish goes on emitting it, and a reset would send us knocking every
                // second. This reconnect says the peer is wrong, not that the network dropped.
                //
                // REQ-COM-004: **hanging up is all that happens here.** The line reports its own
                // ending (`MessageLink.cancel`) and the reconnect hangs off that one event, so the
                // backoff moves one step per disconnect however the line came to end.
                link?.cancel()
            }
            return
        }
        // The envelope was well formed, so the peer is speaking: the run of ten starts over.
        brokenMessages.reset()
        // REQ-PRT-005: a type this version does not know decodes to nil. That is forward
        // compatibility, not corruption — it is ignored and it is not counted as broken.
        guard let envelope = decoded else { return }

        switch envelope.body {
        case let .welcome(payload):
            backoff.reset()
            serverName = payload.serverName
            pairingCode = nil
            status = .connected
            if let serverId = target?.serverId { callbacks?.issuedToken(payload.deviceToken, serverId) }
            startKeepalive()

        case let .authFailed(payload):
            status = .failed(payload.code)
            // A token that cannot be used is thrown away.
            if payload.code == .unknownDeviceToken, let serverId = target?.serverId {
                tokens.delete(serverId: serverId)
            }

        case let .timeSyncPong(payload):
            // REQ-COM-007 / 008: t4 is when the reply was received.
            guard let t2 = payload.t2, let t3 = payload.t3 else { return }
            timeSync.add(TimeSyncSample(t1: payload.t1, t2: t2, t3: t3, t4: Date()))

        case let .stateSnapshot(snapshot):
            callbacks?.receivedSnapshot(snapshot)

        case let .taskList(payload):
            callbacks?.receivedTaskList(payload)

        case let .sessionEvent(payload):
            callbacks?.receivedEvent(payload)

        case let .error(payload):
            callbacks?.receivedError(payload)
        }
    }

    // MARK: - Sending

    func send(_ message: ClientMessage) {
        guard let link, let data = try? MessageCoder.encode(Envelope(body: message)) else { return }
        link.send(data)
    }

    // REQ-PRT-003: a command carries a clientRequestId. Resending does not take effect twice.
    func send(command action: CommandAction, params: CommandParams? = nil) {
        send(.command(CommandPayload(action: action, params: params)))
    }

    // REQ-COM-005 / 007: a heartbeat and a time sync go out every five seconds, and the same
    // five seconds are when the silence coming the other way is looked at.
    //
    // REQ-COM-005: **both messages go out on every beat, unconditionally**, and each one carries
    // one end's watch. Put a condition on either and that end reads a healthy connection as fifteen
    // seconds of silence, one beat after the fifteenth second.
    private func startKeepalive() {
        keepaliveTask?.cancel()
        let interval = heartbeatInterval
        // REQ-COM-005: **the watch begins on a message, never on an empty line.** This is reached
        // from the `welcome`, which `handle` has already stamped, so the first look has something
        // to measure from. `Heartbeat.isStale` reads "nothing has ever arrived" as stale, so a
        // watch started anywhere else would end the connection it had just accepted.
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    // A keepalive that has been let go does not get to beat once more.
                    //
                    // **This closes a hop nothing is known to arrive through.** The loop is entered
                    // only from `startKeepalive`, every reconnect that reaches one sleeps a second
                    // or more first (REQ-COM-004), and `disconnect` cancels before anything can be
                    // queued behind it — so no cancellation reaches this hop by any path there is.
                    // The guard keeps that true of whatever path is added next.
                    guard !Task.isCancelled, let self else { return }
                    // REQ-COM-005: the round is counted first, so that it is counted whatever the
                    // rest of the body comes to do or not do.
                    self.beats += 1
                    // REQ-COM-005: **the only message the Mac's watch counts.** `MdoroServer` moves
                    // `lastHeartbeatAt` on this and on accepting the connection, and on nothing
                    // else — a `timeSyncPing` does not move it. A beat that skips this one is
                    // silence to the Mac, and the Mac hangs up at fifteen seconds of it.
                    self.send(.heartbeat)
                    // REQ-COM-005 / 007: **what the Mac answers**, every one it receives. On a line
                    // where nothing else is happening that answer is the only thing that arrives
                    // here, so it is the whole of what this end's watch counts — see
                    // `endLineIfSilent`, which is what the silence would otherwise be read as.
                    self.send(.timeSyncPing(TimeSyncPayload(t1: Date())))
                    self.endLineIfSilent()
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // REQ-COM-005: fifteen seconds without anything arriving counts as disconnected.
    //
    // **This rests on something arriving on every beat of a line that is live**, and that is what
    // makes silence mean the Mac is gone rather than that it had nothing to say. What arrives is
    // the answer to the time sync: `startKeepalive` sends a `timeSyncPing` every beat and the Mac
    // answers every `timeSyncPing` it receives (REQ-COM-007). **Both halves are load-bearing** —
    // put a condition on either the ping or the answer and this watch cuts healthy connections
    // one beat after every fifteen seconds of quiet.
    //
    // Nothing else can be counted on. State is sent only when it changes (REQ-COM-006), and 10.2
    // gives the server no heartbeat of its own to send back. The WebSocket's own pong is not
    // evidence either: `WebSocketLink` hands up text and binary frames and nothing else, so a
    // control frame the transport answered by itself never reaches `handle` and never stamps
    // `lastReceivedAt`. **What does reach it is whatever the peer put in a data frame, readable or
    // not** — being unreadable is REQ-ERR-009's business, and it is proof of life all the same.
    //
    // REQ-COM-004: **hanging up is all that happens here.** The line reports its own ending
    // (`MessageLink.cancel`) and the reconnect hangs off that one event, so silence climbs the
    // backoff by one step, the same as any other way a line comes to end.
    private func endLineIfSilent() {
        guard Heartbeat.isStale(lastReceivedAt: lastReceivedAt, now: clock()) else { return }
        link?.cancel()
    }

    func requestSnapshot() {
        send(.requestSnapshot)
    }
}
