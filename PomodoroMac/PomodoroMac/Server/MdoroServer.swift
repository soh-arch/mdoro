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
    // Readable so that a test can see the listener a second `start` replaced, and see that it was
    // cancelled rather than dropped. **A dropped NWListener keeps listening** — Network.framework
    // holds it for its queue, and nothing releases the port or the Bonjour name but `cancel()`, so
    // a listener let go goes on answering and advertising with nothing left holding a reference
    // to it.
    private(set) var listener: NWListener?
    private(set) var connection: NWConnection?
    private(set) var connectedDeviceName: String?
    // REQ-SEC-002 / Decision 0040: the token the current connection authenticated with, kept so
    // a revocation can find it. The device name cannot serve — the record's copy is frozen at
    // issue, and the hello's copy may since have changed.
    private(set) var connectedTokenValue: String?
    private(set) var lastHeartbeatAt: Date?

    // **No clause asks for these lines.** The reader Decision 0018 wrote the log for — a stranger
    // on an issue — is the whole of why they exist: what happens here happens nowhere else, and the
    // person reporting it cannot see any of it. Without a line, "it will not pair" reaches an issue
    // with no way to tell five wrong codes from a token the Mac no longer knows (`conn.refused`),
    // and "it disconnected" with no way to tell a phone that went quiet from a line that dropped
    // (`conn.end`, `ConnectionEnding`).
    private let diagnostics: DiagnosticLog

    // REQ-COM-004: the read loop's one call into the transport, taken as a seam so that what the
    // loop does with an ending can be driven from a test (`ServerLineReading`). The default is the
    // real one, so nothing but a test ever names it.
    private let reads: any ServerLineReading

    init(diagnostics: DiagnosticLog, reads: any ServerLineReading = WebSocketLineReads()) {
        self.diagnostics = diagnostics
        self.reads = reads
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

    // **It returns only once the port is settled, and only with a port.** REQ-COM-002 / 003: the
    // number that comes back here is the one `advertise` puts on the air as TXT `ws`, and nothing
    // downstream questions it — so `ListenerReadiness` throws for a listener that went ready with
    // no port rather than answering 0, which is `.any` and not a refusal.
    //
    // **Whatever is listening now is folded first.** Overwrite `self.listener` and leave the old one
    // running, and a second start is a second port and a second Bonjour registration: mDNSResponder
    // numbers them `(2)`, `(3)` — seen on the reader's own Mac, 2026-08-30 — and the iPhone has no
    // way to tell which of the identically named Macs is the one holding the pairing code. The
    // tidying up is the one already in `stop()` — there is no second version of it to fall behind.
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

    // REQ-COM-002 / 003: the Bonjour registration rides this listener. `GET /info` is gone (v2.25)
    // and this process holds no second listener, so TXT `ws` names this listener's own port and can
    // name no other. The browsing side reads the port from the TXT record either way
    // (`ServerBrowser.read`).
    //
    // REQ-COM-003: the fold-before-bind at the top of `start()` is also what keeps a failed start
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
        // REQ-SEC-004 / REQ-ERR-010: **the question is let go of before the line it stood on is hung
        // up on.** That is the order `foldPendingApproval` keeps, for the same reason: the hang-up's
        // `.cancelled` echo reaches `handleDisconnect`, and a `pendingApproval` still standing when it
        // arrives is folded there — `approval.withdrawn` written and `resolveApproval(false)` called,
        // on every stop, for a question nobody withdrew and a banner nobody put up.
        //
        // **The two orders behave alike today, and the reason is mechanical**: the echo is a hop of the
        // main actor away, and between these two statements there is nothing for it to arrive before.
        // A stop written the other way round is quiet, and goes on being quiet until somebody puts a
        // statement between them. That is the whole reason the order is written down rather than left
        // to be noticed: `FoldingWhatIsStandingTests` reads these three lines and asks which is first.
        let askingLine = pendingApproval?.connection
        pendingApproval = nil
        askingLine?.cancel()
        // REQ-ERR-010: **this fold is the one ending that makes no callback at all.** The cancel
        // below reaches `handleDisconnect` only after `connection` has been let go of, so its echo
        // is refused by the guard and `connectionChanged` is never called — which is why
        // `stopServer()` puts the model's view of the connection right by hand. The deliberate
        // route writes `server.stop` next to this line; **the fold at the top of `start()` writes
        // nothing**, and a rename goes through it, so that ending was silent in every log.
        if connection != nil { record(ending: .serverStopped) }
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
        handleDisconnect(connection, ended: .tokenRevoked)
    }

    // MARK: - Connections

    private func accept(_ incoming: NWConnection) {
        // REQ-SEC-004: whether to accept is decided on the authenticate side. Here it just connects and
        // waits for a hello.
        incoming.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                // REQ-ERR-010: **the two states are told apart, because they mean different
                // things.** `.failed` is the transport giving up on a line nobody here touched.
                // `.cancelled` normally *is* one of this class's own endings coming back as an
                // echo — every one of them cancels and hands the connection back in the same
                // breath, so by the time the echo arrives `connection` has already been let go of
                // and the guard below refuses it. Which means a `.cancelled` that gets past that
                // guard was asked for by nobody here, and that is worth its own word rather than
                // being filed under `.failed`.
                case .failed:
                    self?.handleDisconnect(incoming, ended: .transportFailed)
                case .cancelled:
                    self?.handleDisconnect(incoming, ended: .transportCancelled)
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
    //
    // REQ-COM-004: **the read itself goes through `reads`, and that is the only part of this
    // connection that does.** The two things this loop does with an ending — hand the connection
    // back, and stop asking — are what a test could not reach, because an `NWConnection` dials the
    // moment it is started and there was nowhere to stand and give the loop a read. The seam is one
    // call wide: `cancel()` below is still the connection's own, and so is everything else about it.
    private func receive(on connection: NWConnection, counting brokenMessages: BrokenMessageCounter = BrokenMessageCounter()) {
        reads.read(from: connection) { [weak self] data, context, isComplete, error in
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
                    // REQ-COM-004: **the connection is handed back, not merely let go of.** Two of
                    // the endings above reach here with nobody having cancelled anything — a read
                    // that failed, and a peer that closed politely — and an `NWConnection` nobody
                    // cancels keeps its endpoint and its path monitor, the same way a dropped
                    // `NWListener` goes on listening. Cancelling one already cancelled does
                    // nothing, so the ending that arrives by way of a `cancel()` costs a second
                    // call and no more. It is the order the three other endings in this class use
                    // (`disconnect(tokenValue:)`, `checkHeartbeat`, the tenth broken message).
                    //
                    // **`handleDisconnect` bounces every connection but the one being held, and
                    // those are the ones this matters most for.** `accept` starts a read loop on
                    // every incoming connection, but only a hello that is accepted makes one
                    // `self.connection` — so a stranger who reaches the port and then goes away
                    // has a line that ends here and is refused by the guard below, and no other
                    // path in this class would ever cancel it: `checkHeartbeat` and `stop` reach
                    // only the held connection. The two questions are different. Whether this line
                    // is over was just answered by the read; whether it was the one the Mac
                    // believed in is what the guard is for.
                    connection.cancel()
                    self.handleDisconnect(connection, ended: .lineEnded)
                    return
                }
                self.receive(on: connection, counting: counter)
            }
        }
    }

    // REQ-ERR-010: **every ending says which it was**, and it is said here because this is where
    // they all arrive — a reason handed in at the door cannot be forgotten by a path added later,
    // the same shape `refuse` uses to keep a refusal from going unrecorded.
    //
    // `at` is the moment the ending was judged, and it is a parameter for one reason:
    // `checkHeartbeat` decides on a `now` of its own, and the `silent` this writes is the very
    // number that decision was made on. Read the clock again here and a test that ages the clock
    // gets a line whose reason says fifteen seconds of silence and whose number says none.
    private func handleDisconnect(
        _ closed: NWConnection, ended ending: ConnectionEnding, at now: Date = Date(),
        brokenRun: Int? = nil
    ) {
        // REQ-SEC-004: **a line still waiting for an answer is not what the guard below is about,
        // so its ending is heard just before it.** That guard asks whether this was the connection
        // the Mac believed in, and a connection held for approval never is one — but it arrives at
        // this same door, because **every ending in this class comes through here and three of them
        // can be carrying a pending line**: the read loop's `.end`, the tenth broken message
        // (`handle` is reached before any `source === connection` gate), and the transport's own
        // `.failed` / `.cancelled`. Taken at the door rather than at those three sites for the same
        // reason the ending itself is handed in at the door: a path added later cannot forget it.
        foldPendingApproval(endedWith: closed, ended: ending)
        guard closed === connection else { return }
        // **Written before the clean-up, because the clean-up destroys the evidence.**
        // `lastHeartbeatAt` is the only value that can say how long the phone had been quiet, and
        // the line below clears it — at the exact moment an ending needs explaining.
        record(ending: ending, at: now, brokenRun: brokenRun)
        connection = nil
        connectedDeviceName = nil
        connectedTokenValue = nil
        lastHeartbeatAt = nil
        callbacks?.connectionChanged(ConnectionState(isConnected: false))
    }

    // REQ-SEC-004 / REQ-UIX-004: **the phone that was asking went away, so the question goes with
    // it.** (The user's ruling of 2026-09-19 named REQ-COM-013 — the connection state being visible
    // at all times. On the Mac that display is REQ-UIX-004's; REQ-COM-013 governs the iPhone's.
    // Both say the same thing about this: showing connected while holding a line that is over is
    // the one shape they most want to avoid.)
    //
    // **Nothing else lets a pending question go.** `pendingApproval` is released by the user's
    // answer and by the 60-second timeout (`startApprovalTimeout`) and by nothing else, so before
    // this the record outlived the line it belonged to. An "Allow" pressed afterwards then ran
    // `settle(.accept)` on a finished connection: it became `self.connection`, `connectionChanged`
    // reported `isConnected: true`, no read ever came back because nobody re-armed the loop, and
    // the Mac showed a phone that had gone until `checkHeartbeat` noticed fifteen seconds later.
    //
    // **The banner comes down through `resolveApproval(false)`, which is the same call the denial
    // and the timeout make** — it is what clears `pendingConnectionRequest` and drops the hello the
    // Authenticator is holding, and the two must go together or the next hello from a third device
    // would be settled against this one's. What is deliberately *not* done is `refuse(...)`: there
    // is nobody left to send an `authFailed` to, and the user did not reject anything, so writing
    // `conn.refused why=connectionRejectedByUser` would put a reason in the log that never happened.
    //
    // The connection is handed back as well as let go of, for the reason the `.end` arm gives: two
    // of the endings that reach here have had nothing cancelled, and an `NWConnection` nobody
    // cancels keeps its endpoint and its path monitor. Cancelling one already cancelled does
    // nothing, and the `.cancelled` echo finds `pendingApproval` already nil.
    private func foldPendingApproval(endedWith closed: NWConnection, ended ending: ConnectionEnding) {
        guard let pending = pendingApproval, pending.connection === closed else { return }
        // Released before anything else here runs, so neither the echo of the cancel below nor
        // anything the callback does can find the question still standing.
        pendingApproval = nil
        approvalTimeout?.cancel()
        approvalTimeout = nil
        record(approvalWithdrawnBy: ending)
        closed.cancel()
        _ = callbacks?.resolveApproval(false)
    }

    // REQ-ERR-010 / REQ-SEC-004: **a line of its own, not `conn.end`.** Two things would be wrong
    // about borrowing that one. It is written beside `conn up=no` and says why the connection the
    // Mac was holding ended — and this line was never held, so a reader would count a disconnection
    // that never happened. And it carries `silent`, which is read from `lastHeartbeatAt`: that stamp
    // belongs to the authenticated connection, which in this case is usually still up and beating
    // (a standing connection is why approval was being asked for at all), so the number would
    // describe a different line entirely. **The word for how the line went is the same vocabulary**,
    // and so is its level — a transport that failed under a pending line failed just as it would
    // under a held one, and a reader scanning the levels should not have to know which line it was.
    private func record(approvalWithdrawnBy ending: ConnectionEnding) {
        diagnostics.write(
            ConnectionEndingLine.approvalWithdrawnCode, level: ending.level,
            [DiagnosticField(ConnectionEndingLine.howKey, ending.rawValue)]
        )
    }

    // REQ-ERR-010 / Decision 0018: one word for how it ended and one number for how quiet the
    // phone had gone. **Nothing of the device**: not its name, not its address, not its token.
    //
    // It sits beside `conn up=no`, which `AppModel` writes from `connectionChanged` — that line
    // says the connection is over, this one says why. Two of the endings never reach that callback
    // at all (`serverStopped`, `displacedByNewHello`), which is why they call this directly.
    private func record(ending: ConnectionEnding, at now: Date = Date(), brokenRun: Int? = nil) {
        var fields = [
            DiagnosticField(ConnectionEndingLine.howKey, ending.rawValue),
            DiagnosticField(
                ConnectionEndingLine.silentKey,
                ConnectionEndingLine.silence(since: lastHeartbeatAt, now: now)
            ),
        ]
        // REQ-ERR-009: the length of the run that ended the line, on the one ending that has one.
        if let brokenRun { fields.append(DiagnosticField(ConnectionEndingLine.brokenKey, brokenRun)) }
        diagnostics.write(ConnectionEndingLine.code, level: ending.level, fields)
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
                // REQ-ERR-009 / REQ-ERR-010: the run that did it is named from
                // `BrokenMessageCounter.limit` rather than read off the counter, because the counter
                // starts over at the tenth by design — by the time this line is reached its count is
                // zero again. The limit is the one place the number "ten" lives, so a log line and
                // the requirement cannot come to say different things.
                handleDisconnect(source, ended: .brokenMessageRun, brokenRun: BrokenMessageCounter.limit)
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
            // accept in `settle`; a `timeSyncPing` arriving does not, and `handleDisconnect` reads
            // it once — for the `silent` on the line that says how the connection ended
            // (REQ-ERR-010) — and then clears it. It rests on the phone sending a `heartbeat` on
            // every beat, unconditionally (`MdoroClient.startKeepalive`).
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
            // REQ-SEC-004 / REQ-ERR-010: **the standing connection is ending here, and this is the
            // only place that can be said.** The cancel reaches `handleDisconnect` after
            // `connection` has become `source`, so the guard refuses it, and `connectionChanged`
            // reports `isConnected: true` throughout — no `conn up=no` is ever written. Read from
            // the log alone, a phone that dialled again over a line the Mac was still holding was
            // indistinguishable from one that had never been away. **`displacedByNewHello` is the
            // ending this branch alone has to write**, which is why it is the one handed to `fold`.
            //
            // **Whether `source` is what is standing is `fold`'s question, not this branch's** — both
            // branches asked it separately once, and what came of that is written over there.
            //
            // `connection = source` stays outside the exemption. A hello from a line that is not the
            // held one is what this branch is mostly for, and where the two are the same line the
            // assignment writes the object that is already there.
            fold(connection, displacedBy: source, recording: .displacedByNewHello)
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
            //
            // **Nothing is recorded for the request this displaces, and that is deliberate.** The
            // `conn.end` vocabulary describes the line the Mac was holding, and a request that never
            // got past a question was never that line — a word for it here would put a disconnection
            // in the log that the reader cannot match to any connection (REQ-ERR-010 / Decision 0018).
            // The accept above is the opposite case and says why.
            //
            // **Whether `source` is what is standing is `fold`'s question, not this branch's.**
            fold(pendingApproval?.connection, displacedBy: source, recording: nil)
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

    // REQ-SEC-004 / REQ-ERR-010: **one declaration decides what it means to fold what is standing.**
    // Both of `settle`'s branches make room for the hello they are settling — the accept folds the
    // line the Mac is holding, the approval folds the request a question was already waiting on — and
    // each used to write the judgement out for itself. Written twice, it was corrected twice and
    // neither time completely: the exemption for `source` was missing from one branch, and in the
    // other it covered the log line but not the hang-up beside it. **A judgement in two places is a
    // judgement that can be half-fixed**, so it is in one.
    //
    // **`source` is exempt, and for the same reason in both branches — down to the mechanism.** A
    // second hello arriving on the line that is already standing is not one connection displacing
    // another: there is no other connection, and what the cancel would reach is the very line the
    // caller is in the middle of setting up. **It would not merely be a wasted call.** The
    // `.cancelled` echo reaches a gate that is holding that same connection by the time it arrives —
    // `handleDisconnect`'s `closed === connection` for the accept, `foldPendingApproval`'s
    // `pending.connection === closed` for the approval — so in both cases the gate lets the echo
    // through and the branch tears down what it had just stood up. The accept would write `conn.end`,
    // let the connection go and report `isConnected: false` one hop of the main actor after telling
    // the screen it was connected; the approval would withdraw the question it had just put up.
    //
    // **`ending` is nil for the caller that writes nothing**, rather than a word chosen here: only
    // the accept displaces a connection the Mac was holding, and only that ending needs a line of its
    // own (`handleDisconnect` refuses its echo, so no `conn up=no` is ever written for it). The
    // approval's is deliberately silent — its own branch says why — and this parameter is what keeps
    // the two apart without either of them owning the fold.
    //
    // The line goes in before the hang-up, the order `handleDisconnect` keeps and for its reason: the
    // ending is what `record` explains, and folding a line is what destroys the state it is explained
    // from.
    private func fold(_ standing: NWConnection?, displacedBy source: NWConnection, recording ending: ConnectionEnding?) {
        guard let standing, standing !== source else { return }
        if let ending { record(ending: ending) }
        standing.cancel()
    }

    // **The only ways a refusal leaves this process**, so the record cannot be forgotten on a path
    // someone adds later. **No clause asks for that record either** — the reason it is written is
    // beside `diagnostics`, where the log is taken in. Two of them, because 10.2 carries the two
    // kinds of reason in two different messages — and both of them write the line first.
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
        // REQ-SEC-003 (v2.28) / REQ-SEC-004: settled against the hello held when the question was
        // asked, not by authenticating it afresh. A code that passed inside the window may reach
        // issue on the strength of the approval alone, and the window can close or be shut while
        // the user is deciding — authenticating again at that point refuses the very hello being
        // approved.
        guard let decision = callbacks?.resolveApproval(true) else { return }
        // Only an approval that ends in an accept drops the existing connection — `settle`'s
        // accept branch folds it on its way in. REQ-SEC-004: only a new connection that is
        // accepted costs the standing one, so an approval the Authenticator refused (the token was
        // revoked while the question waited) keeps it, exactly as the Authenticator's own record of
        // it is kept.
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

    // **Internal, and it takes its own `now`**, so that the one decision it makes can be exercised
    // without a test having to sit through fifteen seconds of real silence — the same reason
    // `AppModel.startServer` is internal. Production passes nothing and reads the clock.
    //
    // REQ-ERR-010: the `now` goes on to the record, so the seconds in the line are the seconds this
    // judgement was made on. `Heartbeat.isStale` already takes its `now` the same way.
    func checkHeartbeat(now: Date = Date()) {
        guard let connection else { return }
        if Heartbeat.isStale(lastReceivedAt: lastHeartbeatAt, now: now) {
            connection.cancel()
            handleDisconnect(connection, ended: .heartbeatTimeout, at: now)
        }
    }
}


// Wait until the NWListener is ready, then return the port that was settled on.
// The state handler runs on its own queue, so a box guards against resuming the continuation twice.
enum ListenerReadiness {

    // REQ-COM-003: **a listener that is ready with no port on it is a start that failed, and this
    // is what says so.** Deliberately not an `NWError` like the two arms below: nothing in the
    // transport reported a failure — it reported `.ready` — so there is no error to pass on, and
    // minting a POSIX code for one would write a cause into the diagnostic log (REQ-ERR-010) that
    // nothing observed. **A reader of that log sees this type's own name as the domain rather than
    // `Mdoro:n`**: Decision 0034 hands out a fixed number per case from the bands in
    // `ErrorCode.swift`, and none of those bands covers listening, so taking a number here would
    // mean opening a new one — a decision about that ledger, not about this line.
    //
    // `nonisolated` for the same reason `ConnectionEnding` and `WebSocketLineReads` are: this
    // target's default isolation is the main actor, and this is raised from the listener's own
    // queue, which is no actor at all.
    nonisolated struct NoPortOnAReadyListener: Error {}

    // **Nothing is handed back that is not a port.** `NWEndpoint.Port(rawValue: 0)` is not a
    // refusal — 0 is `.any`, the request to be given whichever port is free — so a 0 returned from
    // here is taken for a port everywhere a real one would be: `advertise` writes it into the
    // Bonjour TXT record as `ws` (REQ-COM-002 / 003), `DiscoveredServer.read` parses it back
    // without complaint, and the iPhone dials a port nothing listens on. **The only symptom is
    // silence**, which is the shape `docs/CONTEXT.md` ("failures must not be silenced") names.
    //
    // **This arm is written from the documented fact, not from a reproduction.** `NWListener.port`
    // states that "The listener's port is available once the listener is in the ready state"
    // (developer.apple.com/documentation/network/nwlistener/port, read 2026-09-19), and its one
    // caller reads it inside the `.ready` arm — so nothing should ever reach the throw. What it
    // must not do if something does is answer with a number.
    //
    // Kept apart from `awaitReady` because an `NWListener` cannot be made to go ready without a
    // port, so this is the only place the decision can be exercised at all
    // (`AReadyListenerHasAPortTests`).
    nonisolated static func settledPort(_ raw: UInt16?) throws -> UInt16 {
        guard let raw, raw != 0 else { throw NoPortOnAReadyListener() }
        return raw
    }

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
                    do {
                        let port = try ListenerReadiness.settledPort(listener.port?.rawValue)
                        continuation.resume(returning: port)
                    } catch {
                        continuation.resume(throwing: error)
                    }
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
