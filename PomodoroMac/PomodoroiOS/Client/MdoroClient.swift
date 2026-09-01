import Foundation
import Network
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

    private var connection: NWConnection?
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

    private let deviceName = "iPhone"
    // POL-047 / Decision 0040: the Keychain is outside this process, and the suite runs inside
    // this app. **The default is the same as production.**
    private let tokens: any TokenStoring

    init(tokens: any TokenStoring = TokenKeychain()) {
        self.tokens = tokens
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
        connection?.cancel(); connection = nil
        status = .idle
    }

    // REQ-COM-003 / POL-143: dial the discovered service itself. Network.framework resolves a
    // `.service` endpoint by instance name at connect time, so the address and port are whatever
    // the Mac is advertising right now — and since the advertisement rides on the ws listener,
    // the service resolves to the ws port. What stood here dialled "\(instanceName).local": an
    // mDNS host name and an instance name are unrelated, and the two matched only while the
    // instance name happened to be the computer's name. Once the default became "Mdoro", the
    // guess pointed at a host that does not exist.
    nonisolated static func dialEndpoint(for server: DiscoveredServer) -> NWEndpoint? {
        guard case .service = server.endpoint else { return nil }
        return server.endpoint
    }

    private func openConnection() {
        guard let target, let endpoint = Self.dialEndpoint(for: target) else { return }
        status = (status == .connected) ? .reconnecting : .connecting
        // REQ-ERR-009: every connection counts its own broken messages from zero.
        brokenMessages.reset()

        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.sendHello()
                case .failed, .cancelled: self?.scheduleReconnect()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive(on: connection)
    }

    // REQ-COM-004: reconnect with exponential backoff (one second the first time, thirty seconds at most).
    private func scheduleReconnect() {
        guard !isStopping else { return }
        keepaliveTask?.cancel(); keepaliveTask = nil
        connection = nil
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

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.scheduleReconnect(); return }
                if let data, !data.isEmpty,
                   let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .text || metadata.opcode == .binary {
                    self.handle(data)
                }
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ data: Data) {
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
                connection?.cancel()
                scheduleReconnect()
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
        guard let connection, let data = try? MessageCoder.encode(Envelope(body: message)) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    // REQ-PRT-003: a command carries a clientRequestId. Resending does not take effect twice.
    func send(command action: CommandAction, params: CommandParams? = nil) {
        send(.command(CommandPayload(action: action, params: params)))
    }

    // REQ-COM-005 / 007: a heartbeat and a time sync go out every five seconds.
    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.send(.heartbeat)
                    self?.send(.timeSyncPing(TimeSyncPayload(t1: Date())))
                }
                try? await Task.sleep(for: .seconds(Heartbeat.interval))
            }
        }
    }

    func requestSnapshot() {
        send(.requestSnapshot)
    }
}
