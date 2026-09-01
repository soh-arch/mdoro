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
        var handleCommand: (CommandPayload) -> Void
        var provideSnapshot: () -> StateSnapshot
        var provideTaskList: () -> TaskListPayload?
        // Decision 0040: the name the user gave this Mac (9.3 `displayName`). Asked for at the
        // moment of the welcome rather than held, so a rename between two connections is not a
        // stale copy kept here.
        var provideDisplayName: () -> String
        var connectionChanged: (ConnectionState) -> Void
    }

    private(set) var listenPort: UInt16?
    // POL-114: readable so that a test can see the listener a second `start` replaced, and see that
    // it was cancelled rather than dropped. **A dropped NWListener keeps listening** — Network.framework
    // holds it for its queue, and nothing releases the port or the Bonjour name but `cancel()`.
    private(set) var listener: NWListener?
    private(set) var connection: NWConnection?
    private(set) var connectedDeviceName: String?
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
        listenPort = nil
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

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.handleDisconnect(connection)
                    return
                }
                if let data, !data.isEmpty,
                   let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .text || metadata.opcode == .binary {
                    // Both text and binary are read as JSON.
                    self.handle(data, from: connection)
                }
                self.receive(on: connection)
            }
        }
    }

    private func handleDisconnect(_ closed: NWConnection) {
        guard closed === connection else { return }
        connection = nil
        connectedDeviceName = nil
        lastHeartbeatAt = nil
        callbacks?.connectionChanged(ConnectionState(isConnected: false))
    }

    // MARK: - Receiving

    private func handle(_ data: Data, from source: NWConnection) {
        // REQ-ERR-009: a broken message is thrown away and the connection is kept.
        guard let envelope = try? MessageCoder.decodeClient(data) else { return }

        switch envelope.body {
        case let .hello(payload):
            handleHello(payload, from: source)

        case let .timeSyncPing(payload):
            // REQ-COM-007: t2 is when it arrived, t3 is when the answer was sent.
            let t2 = Date()
            send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)

        case .heartbeat:
            // REQ-COM-005: 10.2 has no Server → Client heartbeat, so nothing is sent back.
            // The client side judges liveness from the WebSocket ping/pong.
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
        switch decision {
        case let .accept(token):
            connection?.cancel()
            connection = source
            connectedDeviceName = payload.deviceName
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
        }
    }

    // POL-054: **the only way a refusal leaves this process**, so the record cannot be forgotten on
    // a path someone adds later.
    private func refuse(_ code: AuthFailureCode, of hello: HelloPayload, to connection: NWConnection) {
        record(refusal: code, of: hello)
        sendThenClose(.authFailed(AuthFailedPayload(code: code)), to: connection)
    }

    // REQ-ERR-010 / Decision 0018: the code, and nothing beside it.
    //
    // **The hello is taken and deliberately not written.** The device name, the token and the
    // pairing code are all in hand at this exact moment; Decision 0018 keeps them out of the file
    // by never putting them in, not by masking them on the way out, and a test hands one of each
    // in and reads the whole file back. What is left is one of six codes, which is what tells a
    // stranger on an issue five wrong codes from a token this Mac no longer knows.
    func record(refusal code: AuthFailureCode, of hello: HelloPayload) {
        diagnostics.write("conn.refused", level: .warn, [DiagnosticField("why", code.diagnosticSummary)])
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
            refuse(.connectionRejectedByUser, of: pending.hello, to: pending.connection)
            return
        }
        // Drop the existing connection, then have it authenticate afresh.
        connection?.cancel()
        connection = nil
        connectedDeviceName = nil
        handleHello(pending.hello, from: pending.connection)
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
