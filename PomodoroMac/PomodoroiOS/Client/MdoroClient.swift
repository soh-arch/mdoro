import Foundation
import MdoroCore

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
        // REQ-COM-004 / REQ-PRT-004 / 10.2: refused, with the reason travelling on `error` because
        // `authFailed.code` has no word for it. The mirror of `Authenticator.Decision` on the Mac,
        // which grew `rejectWithProtocolError(ProtocolRefusal)` beside `reject(AuthFailureCode)`
        // for the same reason: one case per message 10.2 carries a refusal in, each carrying that
        // message's own reason type.
        //
        // **Not folded into `failed`.** The five `AuthFailureCode`s are all about what the hello
        // carried as credentials, and every one of them leads the user to the same next thing —
        // six digits. This one does not: REQ-PRT-004 asks for an update, and no code can mend a
        // version. **Nor named after the remedy** (`needsUpdate`), which would leave the next
        // `ProtocolRefusal` case with no state to arrive in.
        case refused(ProtocolRefusal)
        // REQ-SEC-001: **the Mac is waiting for six digits, and said so.** Reached when a `hello`
        // that carried no pairing code is refused as `invalidPairingCode` — the only shape that
        // answer can have when nothing was sent to be wrong (`handle`). **No longer a decision this
        // client makes without asking**: it used to be set in place of sending the hello at all,
        // which put a pairing field in front of a user whose trouble was a version (REQ-PRT-004).
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
    // discovered rows a pairing code belongs to. Without it the model matches on names from two
    // different name spaces and falls through to `servers.first`.
    private(set) var target: DiscoveredServer?
    private var pairingCode: String?
    // REQ-SEC-001: whether the last `hello` to go out carried a pairing code. **Written where the
    // hello is built, because it cannot be read back afterwards**: `stopDialling` lets the code go
    // on every refusal (REQ-COM-004), so by the time an `authFailed` is being read `pairingCode` is
    // nil whatever it held when the hello left. Recording it at the one place a hello is built also
    // rests on no ordering of statements in `handle`.
    private var helloCarriedAPairingCode = false
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    // **Whether this client is done dialling until it is asked again.** `disconnect()` sets it,
    // and so does either refusal (REQ-COM-004) — both are answers rather than accidents, and
    // `connect` is the only thing that clears it. Every reconnect there is reads it, which is why
    // a refusal does not have to race the `.ended` the Mac sends straight afterwards.
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
    // REQ-SEC-002 / Decision 0040: the Keychain is outside this process, and the suite runs inside
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

    // REQ-COM-004: **a connection somebody asked for does not inherit a wait.** Every caller of
    // this is the user, or the discovery that stands in for them the one time it dials by itself:
    // six digits entered (`ClientModel.submitPairingCode`), "Try again" pressed
    // (`ClientModel.redial`), a Mac chosen from the list, and the single Mac found at launch
    // (`ClientModel.start`).
    //
    // **Not in `openConnection`**, which is the door the backoff itself comes back in through.
    // Wound back there, the ladder would never leave its first rung.
    //
    // Without this, a dial that gets as far as the network and no further is followed by however
    // far the last run of failures had climbed — up to thirty seconds of a screen saying nothing is
    // happening, because the user pressed something and this client kept its place in a queue they
    // cannot see.
    //
    // **This is not that clause being widened.** REQ-COM-004 governs a temporary network outage,
    // where the doubling is the whole point of it, and says nothing either way about a dial the user
    // asked for. The ladder is untouched, and every retry the backoff makes still doubles.
    func connect(to server: DiscoveredServer, pairingCode: String? = nil, callbacks: Callbacks) {
        self.callbacks = callbacks
        self.target = server
        self.pairingCode = pairingCode
        isStopping = false
        backoff.reset()
        // REQ-COM-004: **and the wait already running is called off.** A retry scheduled before the
        // user pressed anything is still asleep with its own delay, and waking it after this dial
        // has opened a line would displace that line for one the user did not ask for. Resetting
        // the ladder shortens the next wait; it does nothing to the one already counting down.
        reconnectTask?.cancel(); reconnectTask = nil
        openConnection()
    }

    // REQ-COM-003 / REQ-COM-004: **a Mac that was renamed is still the Mac being dialled.** The
    // Bonjour instance name is rewritten when the user changes `displayName` and when mDNSResponder
    // settles a collision, and the old registration then resolves to nothing — so a client that kept
    // dialling it would climb the backoff for ever. What identifies the Mac is the TXT `id`, so a
    // discovery result carrying the same `serverId` becomes the target, and the next dial the backoff
    // makes goes to it. The ladder and the wait already running are left as they are: this is not a
    // dial anybody asked for.
    //
    // Nothing moves while the old registration is still listed, nor for a target with no `serverId`
    // (a version that predates it, which has nothing to be followed by).
    func follow(_ found: [DiscoveredServer]) {
        guard !isStopping, let current = target,
              let successor = Self.successor(of: current, in: found) else { return }
        target = successor
    }

    // The registration that stands for `target` in `found`, when `target` itself has gone.
    static func successor(of target: DiscoveredServer, in found: [DiscoveredServer]) -> DiscoveredServer? {
        guard let serverId = target.serverId, !found.contains(target) else { return nil }
        return found.first { $0.serverId == serverId }
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

        // REQ-COM-004: **the line being displaced is hung up on, and its ending is not listened
        // to.** `openConnection` is reached from more than one place — the backoff, and the user
        // asking for a Mac while a dial is already in flight (`ClientModel.forgetPairedMac`,
        // "Choose a Mac") — and a line left here when the next one opens is under nobody's control.
        // Left open it keeps its socket; listened to, its `.ended` would reach `scheduleReconnect`,
        // which would clear the line that had taken its place and dial again on a backoff nothing
        // had wound back.
        //
        // **The displaced line is keeping its own contract** — `.ended` exactly once, and last — so
        // no guard inside it could tell this apart. The two lines are different objects, and only
        // this end knows which one it is holding.
        let displaced = self.link
        self.link = link
        // The identity is held as a value, not as a reference: the closure is kept by the line, and
        // a closure that held the line back would be a cycle neither could leave.
        let held = ObjectIdentifier(link)
        displaced?.cancel()

        link.start { [weak self] event in
            guard let self else { return }
            // REQ-COM-004: an event from a line this client has already let go of is not acted on.
            guard let current = self.link, ObjectIdentifier(current) == held else { return }
            switch event {
            case .ready: self.sendHello()
            case let .message(data): self.handle(data)
            // REQ-COM-004: **an ending is not by itself a reason to dial again.** A refusal has
            // already set the flag `scheduleReconnect` guards on, so the ending the Mac sends
            // right after one is read as the answer it belongs to and not as a dropped network.
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

    // REQ-COM-004: **an answer the Mac meant is not something to ask again.** The same `hello`
    // returns the same refusal, so dialling on climbs to the thirty-second ceiling and stays there
    // for ever, telling the user nothing.
    //
    // The line is hung up here rather than waited for: the Mac closes it straight after either
    // refusal (`MdoroServer.sendThenClose`), but nothing about stopping should rest on the peer
    // doing that. Either way the `.ended` that follows finds the flag already set.
    private func stopDialling() {
        isStopping = true
        reconnectTask?.cancel(); reconnectTask = nil
        keepaliveTask?.cancel(); keepaliveTask = nil
        link?.cancel(); link = nil
        // REQ-COM-004: **and the code at hand goes with it.** Held, it keeps `sendHello` out of the
        // one branch that asks for a new one, so the same six digits go back for the same refusal
        // and the user is left waiting without being asked anything.
        pairingCode = nil
    }

    private func sendHello() {
        // Decision 0040: **the id, not the name.** A Mac advertising without one is a version
        // that cannot be paired with; it gets as far as the version check and is refused there.
        let token = target?.serverId.flatMap { tokens.load(serverId: $0) }
        // REQ-PRT-004 / REQ-COM-004: **the hello goes out even with nothing to put in it.** What is
        // wrong may not be the credentials at all — `Authenticator.authenticate` reads the version
        // before it reads a token or a code, so an empty hello still comes back
        // `protocolVersionMismatch` when that is the truth of it.
        //
        // Deciding here that six digits are what is wanted answers for the Mac without asking it,
        // and answers wrong for the user who most needs the truth: a first pairing refused over a
        // version, who presses "Try again" and watches "update both devices" become "enter the
        // code". **A way forward, for a trouble it is not the way out of.** The code had already
        // gone with `stopDialling`, so this was the branch they landed in.
        //
        // **Which leaves this end reading the answer rather than guessing it**: `pairingModeNotActive`
        // is the Mac saying to start pairing, and `invalidPairingCode` for a hello that carried no
        // code is the Mac saying it is waiting for one. Both are sorted in `handle`.
        helloCarriedAPairingCode = pairingCode != nil
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
            // REQ-COM-004: whatever the reason, this is the Mac's considered answer. Stop dialling
            // and let the code go — then put the user in the state that answer means, because the
            // state they are left in has to carry both the reason and a way out of it.
            stopDialling()
            // REQ-SEC-001: **a code cannot have been wrong when none was sent.** With no token and
            // no code the hello goes out all the same (`sendHello`), and a Mac whose pairing window
            // is open answers a hello carrying no code with `invalidPairingCode` —
            // `Authenticator.authenticate` reaches that without verifying anything, and without
            // spending one of REQ-ERR-006's five attempts. Shown as `.failed(.invalidPairingCode)`
            // it reads "That code is not correct" to a user who has not typed a digit.
            // `.needsPairing` is what the answer actually means: the Mac is waiting for the six.
            if payload.code == .invalidPairingCode, !helloCarriedAPairingCode {
                status = .needsPairing
            } else {
                status = .failed(payload.code)
            }
            // A token that cannot be used is thrown away. **Only for this one reason** — a refusal
            // over a version arrives as `error` (REQ-PRT-004), and a token is not what is wrong
            // with it.
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
            // REQ-PRT-004 / REQ-COM-004 / 10.2: **one code on `error` is a refused connection, not
            // a refused action.** `ProtocolRefusal` is the list of them, and the reverse lookup is
            // taken off the same forward map the Mac sends by, so neither end can drift and a
            // second refusal added there is picked up here without being named twice.
            //
            // Everything else on `error` answers a command that was sent on a connection that
            // stands (REQ-ERR-016), and it goes where it went before.
            if let refusal = ProtocolRefusal.allCases.first(where: { $0.protocolErrorCode == payload.code }) {
                // REQ-COM-004: stop dialling, let the pairing code go — **and keep the token.**
                // REQ-PRT-004 asks for an update; the registration this iPhone holds is not what is
                // wrong, and throwing it away would cost the user a pairing over a version number.
                stopDialling()
                status = .refused(refusal)
                return
            }
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
