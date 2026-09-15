import Foundation
import Network
import MdoroCore

// REQ-COM-001 / 002: the Mac is the parent (the server) and the iPhone the child. The state is kept
// in step over a WebSocket (JSON).
// **This class holds no domain judgement.** It does nothing but hand the messages it receives upward.
@MainActor
final class MdoroServer {

    struct Callbacks {
        // The judgement about authentication is made above (Authenticator).
        var authenticate: (HelloPayload) -> Authenticator.Decision
        // REQ-SEC-004: the user's answer to `.needsUserApproval`. The judgement — issue, hand
        // back the record on file, or refuse — is the Authenticator's; nil means nothing was
        // waiting up there.
        var resolveApproval: (Bool) -> Authenticator.Decision?
        var handleCommand: (CommandPayload) -> Void
        var provideSnapshot: () -> StateSnapshot
        var provideTaskList: () -> TaskListPayload?
        // Decision 0040: the name the user gave this Mac (9.3 `displayName`). Asked for at the
        // moment of the welcome rather than held, so a rename between two connections is not a
        // stale copy kept here.
        var provideDisplayName: () -> String
        var connectionChanged: (ConnectionState) -> Void
        // Decision 0040 (judgement 5): the name the registration actually came back under, when
        // it differs from the one asked for — mDNSResponder renamed it, which means another
        // Mdoro shares this LAN. nil says the requested name stood. **Advisory only**: whether
        // `serviceRegistrationUpdateHandler` fires is not on record (`docs/PLATFORM.md`), so
        // nothing may depend on this arriving — a handler that stays silent only means no notice.
        var advertisedNameChanged: (String?) -> Void = { _ in }
    }

    private(set) var listenPort: UInt16?
    // POL-114: readable so that a test can see the listener a second `start` replaced, and see that
    // it was cancelled rather than dropped. **A dropped NWListener keeps listening** — Network.framework
    // holds it for its queue, and nothing releases the port or the Bonjour name but `cancel()`.
    private(set) var listener: NWListener?
    private(set) var connection: NWConnection?
    private(set) var connectedDeviceName: String?
    // REQ-SEC-002 / Decision 0040: the token the current connection authenticated with, kept so
    // a revocation can find it. The device name cannot serve — the record's copy is frozen at
    // issue, and the hello's copy may since have changed.
    private(set) var connectedTokenValue: String?
    private(set) var lastHeartbeatAt: Date?

    // POL-054 / REQ-ERR-010: a refused connection is the one thing that happens here and nowhere
    // else, and the person reporting it cannot see any of it. Without a line, "it will not pair"
    // reaches an issue with no way to tell five wrong codes from a token the Mac no longer knows.
    private let diagnostics: DiagnosticLog

    init(diagnostics: DiagnosticLog) {
        self.diagnostics = diagnostics
    }

    private let queue = DispatchQueue(label: "MdoroMac.Server")
    private var callbacks: Callbacks?
    private var deduplicator = RequestDeduplicator()
    private var heartbeatTimer: Task<Void, Never>?
    // REQ-SEC-004: a connection request waiting for the user to approve it.
    private var pendingApproval: (connection: NWConnection, hello: HelloPayload)?
    private var approvalTimeout: Task<Void, Never>?

    // REQ-SEC-004: the confirmation times out on its own after 60 seconds, and the default is to refuse.
    static let approvalTimeoutSeconds: TimeInterval = 60

    // MARK: - Starting up

    // **It returns only once the port is settled.** Return before it is settled and the value that goes
    // into the Bonjour TXT record is 0.
    //
    // POL-114 / REQ-COM-003: **whatever is listening now is folded first.** This used to overwrite
    // `self.listener` and leave the old one running, so a second start meant a second port and a second
    // Bonjour registration; mDNSResponder numbered them `(2)`, `(3)` and the iPhone had no way to tell
    // which of the identically named Macs was the one holding the pairing code. The tidying up is the
    // one already in `stop()` — there is no second version of it to fall behind.
    func start(callbacks: Callbacks) async throws -> UInt16 {
        stop()
        self.callbacks = callbacks

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let websocket = NWProtocolWebSocket.Options()
        // A ping from the other side is answered by Network.framework. That is a different thing from
        // the heartbeat at the application layer (REQ-COM-005).
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        // Decision 0040 (judgement 5): set before the listener starts, so a registration that
        // comes back renamed is not missed for arriving early. It reports nothing until
        // `advertise` has said what name was asked for.
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            Task { @MainActor in self?.noteRegistration(change) }
        }
        self.listener = listener

        let port = try await ListenerReadiness.awaitReady(listener, on: queue)
        listenPort = port
        startHeartbeatMonitor()
        return port
    }

    // REQ-COM-002 / 003: the Bonjour registration rides this listener now. `GET /info` is gone
    // (v2.25), and with it the listener that used to carry the name — so TXT `ws` names this
    // listener's own port rather than a second one's. The browsing side reads the port from the
    // TXT record either way (`ServerBrowser.read`), so nothing changes for the iPhone.
    //
    // POL-140: the fold-before-bind at the top of `start()` is also what keeps a failed start
    // from leaving a stale advertisement — with one listener, whatever was advertised comes down
    // before anything new is bound, so a `start()` that throws leaves nothing on the air.
    //
    // Decision 0040: the name and the identity are two arguments. The name is whatever the user
    // typed (`displayName`) and mDNSResponder may append ` (2)` to it; the `id` is what the
    // iPhone files its token under, and nothing rewrites that.
    func advertise(displayName: String, serverId: ServerID) {
        guard let listener, let port = listenPort else { return }
        requestedServiceName = displayName
        listener.service = NWListener.Service(
            name: displayName,
            type: BonjourService.type,
            txtRecord: NWTXTRecord(
                BonjourService.txtEntries(websocketPort: port, serverId: serverId)
            )
        )
    }

    func stop() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        approvalTimeout?.cancel()
        approvalTimeout = nil
        pendingApproval?.connection.cancel()
        pendingApproval = nil
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        connectedDeviceName = nil
        connectedTokenValue = nil
        requestedServiceName = nil
        listenPort = nil
    }

    // Decision 0040 (judgement 5): what name the registration actually came back under. The
    // handler fires on the listener's queue; only an `.add` of this service type, compared
    // against the name `advertise` asked for, is worth a word upward.
    private var requestedServiceName: String?

    private func noteRegistration(_ change: NWListener.ServiceRegistrationChange) {
        guard case let .add(endpoint) = change,
              case let .service(name, type, _, _) = endpoint,
              type == BonjourService.type,
              let requested = requestedServiceName else { return }
        callbacks?.advertisedNameChanged(
            BonjourService.alternateRegisteredName(registered: name, requested: requested)
        )
    }

    // REQ-SEC-002 / Decision 0040 (judgement 4): a revoked token's connection does not stay up —
    // the token is no longer valid, and staying connected would say otherwise. A different
    // token's connection is left exactly alone.
    func disconnect(tokenValue: String) {
        guard connectedTokenValue == tokenValue, let connection else { return }
        connection.cancel()
        handleDisconnect(connection)
    }

    // MARK: - Connections

    private func accept(_ incoming: NWConnection) {
        // REQ-SEC-004: whether to accept is decided on the authenticate side. Here it just connects and
        // waits for a hello.
        incoming.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed, .cancelled:
                    self?.handleDisconnect(incoming)
                default:
                    break
                }
            }
        }
        incoming.start(queue: queue)
        receive(on: incoming)
    }

    // REQ-ERR-009: **the run of broken messages belongs to this connection and to no other**, and
    // it rides the read loop rather than sitting on the server. `accept` starts one loop per
    // connection and each turn hands the count to the next, so a connection begins at zero because
    // its loop does, and the count goes when the loop goes — there is no table to key, to clear, or
    // to leak. It is the same thing `MdoroClient.openConnection` does with a `reset()`, said by the
    // shape instead.
    //
    // **A field on the server would be one count shared by every connection at once.** `handle` is
    // reached before any `source === connection` gate, so a stranger who can reach this port could
    // then walk the count up and have the authenticated connection hung up on — nine of theirs and
    // one of anybody's would do it.
    //
    // REQ-COM-004 / REQ-PRT-001: **what one read off this line means is `LineRead`'s, in
    // `MdoroCore`, and the iPhone's read loop asks the same function.** Three things arrive here as
    // reads and only one of them is a message: a read that failed, a close frame, and a completed
    // read with no frame and no bytes are all the line ending, and **a peer that closes politely
    // leaves this `NWConnection` `.ready`** — no `.failed`, no `.cancelled`, so the state handler
    // set up in `accept` is never told and this is the only place the ending is heard.
    //
    // REQ-COM-005: **`checkHeartbeat` is a backstop, not this.** Fifteen seconds of silence ends
    // the connection whatever happens here, so an ending missed here was never permanent — but for
    // those fifteen seconds the Mac shows a phone that has gone, and a loop that re-armed through
    // the ending would spend them turning on the main actor, because a read on a finished
    // connection comes back at once and with nothing on it.
    private func receive(on connection: NWConnection, counting brokenMessages: BrokenMessageCounter = BrokenMessageCounter()) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var counter = brokenMessages
                switch LineRead.of(
                    data: data, frame: context?.webSocketFrame, isComplete: isComplete,
                    failed: error != nil
                ) {
                case let .message(message):
                    // Both text and binary are read as JSON.
                    // REQ-ERR-009: a line that has just been hung up on is not read from again.
                    guard self.handle(message, from: connection, counting: &counter) else { return }
                case .skip:
                    break
                case .end:
                    self.handleDisconnect(connection)
                    return
                }
                self.receive(on: connection, counting: counter)
            }
        }
    }

    private func handleDisconnect(_ closed: NWConnection) {
        guard closed === connection else { return }
        connection = nil
        connectedDeviceName = nil
        connectedTokenValue = nil
        lastHeartbeatAt = nil
        callbacks?.connectionChanged(ConnectionState(isConnected: false))
    }

    // MARK: - Receiving

    // Returns whether this connection is still one to read from. False says a run of ten broken
    // messages has just hung it up (REQ-ERR-009) and there is nothing further to take off it.
    //
    // **The `try?` this replaced flattened two different things into one silence.** `decodeClient`
    // throws when the bytes cannot be read and returns nil when they are read perfectly well and
    // name a message type this version has never heard of — and REQ-PRT-005 makes those opposites:
    // the first is corruption to be counted (REQ-ERR-009), the second is forward compatibility to
    // be ignored. `MdoroClient.handle` has told them apart since it was written; this end had the
    // same comment over an expression that could not.
    private func handle(
        _ data: Data, from source: NWConnection, counting brokenMessages: inout BrokenMessageCounter
    ) -> Bool {
        let decoded: Envelope<ClientMessage>?
        do {
            decoded = try MessageCoder.decodeClient(data)
        } catch {
            // REQ-ERR-009: the message alone is thrown away and the connection is kept — until ten
            // have come in a row, and then what is no good is the line. **The Mac does not
            // reconnect**: the iPhone is always the end that dials, so hanging up here is how
            // REQ-COM-004's reconnect is asked for.
            //
            // REQ-PRT-005: **ten is the earliest this is allowed to happen.** Dropping the
            // connection on the first message that cannot be read is what that clause forbids in a
            // MUST — REQ-ERR-009 is a SHOULD, but this one point is not — and the counter is the
            // whole of what keeps it from happening.
            if brokenMessages.recordBroken() {
                source.cancel()
                handleDisconnect(source)
                return false
            }
            return true
        }
        // The envelope was well formed, so the peer is speaking: the run of ten starts over.
        brokenMessages.reset()
        // REQ-PRT-005: a type this version does not know decodes to nil. That is forward
        // compatibility, not corruption — it is ignored and it is not counted as broken.
        guard let envelope = decoded else { return true }
        dispatch(envelope.body, from: source)
        return true
    }

    private func dispatch(_ message: ClientMessage, from source: NWConnection) {
        switch message {
        case let .hello(payload):
            handleHello(payload, from: source)

        case let .timeSyncPing(payload):
            // REQ-COM-007: t2 is when it arrived, t3 is when the answer was sent.
            //
            // REQ-COM-005: **every ping is answered, with nothing asked of it first.** The phone
            // judges liveness from receipt itself, and on a line where nothing else is happening
            // this answer is the only thing that reaches it. Leave any ping unanswered and the
            // phone reads a healthy connection as fifteen seconds of silence and hangs up a beat
            // later, with every test still green.
            //
            // **The conditions that would do it are the ones that read as care.** A rate limit:
            // the pings arrive one every five seconds by design (REQ-COM-005), so a limit any
            // slower than the beat throws away answers that are owed. A look at the payload:
            // `payload.t1` is the *phone's* wall clock, and the distance between the two clocks is
            // the very thing this exchange is here to measure (REQ-COM-007 / 008) — refuse a `t1`
            // that sits in this Mac's future and a phone whose clock runs ahead is never answered
            // again. **Neither is a fault the phone can see; both are read as the Mac being gone.**
            let t2 = Date()
            send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)

        case .heartbeat:
            // REQ-COM-005: **only the authenticated connection's heartbeat is counted.** The one
            // being judged and the one allowed to postpone the judgement must be the same: a
            // `heartbeat` carries no token and no body, so anyone on this LAN can send one, and
            // without this gate a stranger's beat would keep the authenticated connection's
            // liveness clock alive. This is the same gate `.command` and `.requestSnapshot` carry.
            //
            // **This is the one condition the four legs of REQ-COM-005 tolerate.** The phone does
            // not send its first `heartbeat` until the `welcome` has arrived, so by the time one is
            // sent the sender already *is* `connection`; and before the accept there is no silence
            // check to fail — `checkHeartbeat` returns early while `connection` is nil. Nothing
            // healthy is hung up on. **What holds that ordering up is the other end's code, not a
            // clause**: `MdoroClient.startKeepalive` is reached only from the `welcome`. 10.2 is a
            // catalogue of message types and says nothing about the order they are sent in, so
            // moving that call would break this gate with no clause and no test to say so.
            guard source === connection else { return }
            // REQ-COM-005: **this stamp is the whole of the Mac's watch.** `checkHeartbeat` reads
            // `lastHeartbeatAt` against fifteen seconds, and the only things that carry it forward
            // are this case — for the authenticated connection alone, per the guard above — and the
            // accept in `settle`; a `timeSyncPing` arriving does not, and `handleDisconnect` only
            // clears it. It rests on the phone sending a `heartbeat` on every beat, unconditionally
            // (`MdoroClient.startKeepalive`).
            //
            // 10.2 has no Server → Client heartbeat, so nothing is sent back.
            lastHeartbeatAt = Date()

        case let .command(payload):
            guard source === connection else { return }
            // REQ-PRT-003: a resend carrying the same clientRequestId is ignored.
            guard deduplicator.shouldProcess(payload.clientRequestId) else { return }
            callbacks?.handleCommand(payload)

        case .requestSnapshot:
            guard source === connection, let snapshot = callbacks?.provideSnapshot() else { return }
            send(.stateSnapshot(snapshot), to: source)
        }
    }

    private func handleHello(_ payload: HelloPayload, from source: NWConnection) {
        guard let decision = callbacks?.authenticate(payload) else { return }
        settle(decision, of: payload, from: source)
    }

    // What a decision does to the wire — shared by the hello just received and the one an
    // approval kept waiting (REQ-SEC-004).
    private func settle(_ decision: Authenticator.Decision, of payload: HelloPayload, from source: NWConnection) {
        switch decision {
        case let .accept(token):
            connection?.cancel()
            connection = source
            connectedDeviceName = payload.deviceName
            connectedTokenValue = token.value
            lastHeartbeatAt = Date()
            // Decision 0040: **the Mac's own name does not go out.** `Host.current().localizedName`
            // stood here, so a name with a person in it reached the iPhone, its Keychain and the
            // lock screen. What goes out is the display name, which starts as `Mdoro`.
            send(.welcome(WelcomePayload(deviceToken: token.value,
                                         serverName: callbacks?.provideDisplayName() ?? AppInfo.name)), to: source)
            // **Mark it connected, then take the snapshot.** The other way round and the first state
            // reads as not connected.
            callbacks?.connectionChanged(
                ConnectionState(isConnected: true, lastHeartbeatAt: lastHeartbeatAt, peerDeviceName: payload.deviceName)
            )
            // REQ-COM-004: right after connecting, the whole state goes out, not a delta.
            if let snapshot = callbacks?.provideSnapshot() { send(.stateSnapshot(snapshot), to: source) }
            if let tasks = callbacks?.provideTaskList() { send(.taskList(tasks), to: source) }

        case .needsUserApproval:
            // REQ-SEC-004: **the connection is held open while it waits.** Drop it and by the time
            // "Allow" is pressed the other side is gone.
            pendingApproval.map { $0.connection.cancel() }
            pendingApproval = (source, payload)
            startApprovalTimeout()

        case let .reject(code):
            refuse(code, of: payload, to: source)

        // REQ-PRT-004 / 10.2: the reason has no word in `authFailed.code`, so it leaves on
        // `error` instead. Everything else about a refusal is the same, the record included.
        case let .rejectWithProtocolError(reason):
            refuse(reason, of: payload, to: source)
        }
    }

    // POL-054: **the only ways a refusal leaves this process**, so the record cannot be forgotten
    // on a path someone adds later. Two of them, because 10.2 carries the two kinds of reason in
    // two different messages — and both of them write the line first.
    private func refuse(_ code: AuthFailureCode, of hello: HelloPayload, to connection: NWConnection) {
        record(refusal: code, of: hello)
        sendThenClose(.authFailed(AuthFailedPayload(code: code)), to: connection)
    }

    // REQ-PRT-004 / 10.2: the refusal `authFailed` cannot express. `relatedRequestId` stays nil —
    // a `hello` carries no `clientRequestId` to tie an answer to — and `message` is diagnostic,
    // so the iPhone's wording comes from `code` (Decision 0035).
    private func refuse(_ reason: ProtocolRefusal, of hello: HelloPayload, to connection: NWConnection) {
        record(refusal: reason, of: hello)
        sendThenClose(
            .error(ProtocolErrorPayload(code: reason.protocolErrorCode, message: reason.diagnosticSummary)),
            to: connection
        )
    }

    // REQ-ERR-010 / Decision 0018: the code, and nothing beside it.
    //
    // **The hello is taken and deliberately not written.** The device name, the token and the
    // pairing code are all in hand at this exact moment; Decision 0018 keeps them out of the file
    // by never putting them in, not by masking them on the way out, and a test hands one of each
    // in and reads the whole file back. What is left is the code alone, which is what tells a
    // stranger on an issue five wrong codes from a token this Mac no longer knows.
    func record(refusal code: AuthFailureCode, of hello: HelloPayload) {
        write(refusal: code, of: hello)
    }

    // REQ-PRT-004: and the refusal 10.2 sends as `error` is written the same way, on the same
    // line, so a reader on an issue can tell a version apart from a revoked pairing — which is
    // exactly what they could not do while both went out as `unknownDeviceToken`.
    func record(refusal reason: ProtocolRefusal, of hello: HelloPayload) {
        write(refusal: reason, of: hello)
    }

    // One write for both, so neither kind of refusal can drift into a shape of its own.
    private func write(refusal reason: some DiagnosableError, of hello: HelloPayload) {
        diagnostics.write("conn.refused", level: .warn, [DiagnosticField("why", reason.diagnosticSummary)])
    }

    // REQ-SEC-004: refused on its own after 60 seconds.
    private func startApprovalTimeout() {
        approvalTimeout?.cancel()
        approvalTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.approvalTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resolvePendingApproval(approved: false) }
        }
    }

    // Settle the connection request that was kept waiting.
    func resolvePendingApproval(approved: Bool) {
        approvalTimeout?.cancel()
        approvalTimeout = nil
        guard let pending = pendingApproval else { return }
        pendingApproval = nil

        guard approved else {
            // The 60-second timeout arrives here too, and reads as the same refusal in the log.
            // The Authenticator's held hello is dropped with it, so a refused request cannot be
            // issued for later.
            _ = callbacks?.resolveApproval(false)
            refuse(.connectionRejectedByUser, of: pending.hello, to: pending.connection)
            return
        }
        // REQ-SEC-004 / POL-139: settled against the hello held when the question was asked, not
        // by authenticating it afresh — the pairing window may have expired or been closed while
        // the user was deciding, and a re-authentication then refused the very hello being
        // approved.
        guard let decision = callbacks?.resolveApproval(true) else { return }
        // Only an approval that ends in an accept drops the existing connection — `settle`'s
        // accept branch folds it on its way in. POL-146 / REQ-SEC-004: an approval the
        // Authenticator refused (the token was revoked while the question waited) keeps the
        // standing connection, exactly as the Authenticator's own record of it is kept.
        settle(decision, of: pending.hello, from: pending.connection)
    }

    var hasPendingApproval: Bool { pendingApproval != nil }

    // MARK: - Sending

    // REQ-COM-006: sent only when the state changes. The remaining time is not sent every second.
    func broadcast(_ message: ServerMessage) {
        guard let connection else { return }
        send(message, to: connection)
    }

    private func send(_ message: ServerMessage, to connection: NWConnection) {
        send(message, to: connection, thenClose: false)
    }

    // The reason for a refusal is cut off only **after it has been sent**. Cancel straight away and the
    // reason never arrives.
    private func sendThenClose(_ message: ServerMessage, to connection: NWConnection) {
        send(message, to: connection, thenClose: true)
    }

    private func send(_ message: ServerMessage, to connection: NWConnection, thenClose: Bool) {
        guard let data = try? MessageCoder.encode(Envelope(body: message)) else {
            if thenClose { connection.cancel() }
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in
            if thenClose { connection.cancel() }
        })
    }

    // MARK: - Heartbeat

    // REQ-COM-005: with no answer for 15 seconds, the connection is taken to be down.
    private func startHeartbeatMonitor() {
        heartbeatTimer?.cancel()
        heartbeatTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Heartbeat.interval))
                await MainActor.run { self?.checkHeartbeat() }
            }
        }
    }

    private func checkHeartbeat() {
        guard let connection else { return }
        if Heartbeat.isStale(lastReceivedAt: lastHeartbeatAt, now: Date()) {
            connection.cancel()
            handleDisconnect(connection)
        }
    }
}


// Wait until the NWListener is ready, then return the port that was settled on.
// The state handler runs on its own queue, so a box guards against resuming the continuation twice.
enum ListenerReadiness {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func awaitReady(_ listener: NWListener, on queue: DispatchQueue) async throws -> UInt16 {
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    guard once.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    // REQ-COM-003 (v2.25): `stop()` is reachable from production now (the pairing
                    // screen closing takes the server down), so a listener can be cancelled while
                    // this is still waiting on it. A cancelled listener never becomes ready, and a
                    // continuation that is never resumed hangs its caller forever.
                    guard once.claim() else { return }
                    continuation.resume(throwing: NWError.posix(.ECANCELED))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}
