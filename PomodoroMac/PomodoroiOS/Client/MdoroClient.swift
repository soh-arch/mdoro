import Foundation
import Network
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
        case needsPairing
    }

    struct Callbacks {
        var statusChanged: (Status) -> Void
        var receivedSnapshot: (StateSnapshot) -> Void
        var receivedTaskList: (TaskListPayload) -> Void
        var receivedEvent: (SessionEventPayload) -> Void
        var receivedError: (ProtocolErrorPayload) -> Void
        var issuedToken: (String, String) -> Void
    }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { callbacks?.statusChanged(status) } }
    }
    private(set) var timeSync = TimeSyncEstimator()
    private(set) var serverName: String?

    private var connection: NWConnection?
    private var callbacks: Callbacks?
    private var backoff = ReconnectPolicy()
    private var target: DiscoveredServer?
    private var pairingCode: String?
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStopping = false

    private let deviceName = "iPhone"

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

    private func openConnection() {
        guard let target, let port = target.websocketPort,
              case let .service(name, type, domain, interface) = target.endpoint else { return }
        status = (status == .connected) ? .reconnecting : .connecting

        // Connect to the host Bonjour points at, on the port taken from the TXT record.
        _ = (name, type, domain, interface)
        let host = NWEndpoint.hostPort(
            host: NWEndpoint.Host("\(name).local"),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )

        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let connection = NWConnection(to: host, using: parameters)
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
        let token = target.map { TokenKeychain.load(serverName: $0.name) } ?? nil
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
        // REQ-ERR-009: a broken message is thrown away and the connection is kept.
        guard let envelope = try? MessageCoder.decodeServer(data) else { return }

        switch envelope.body {
        case let .welcome(payload):
            backoff.reset()
            serverName = payload.serverName
            pairingCode = nil
            status = .connected
            if let target { callbacks?.issuedToken(payload.deviceToken, target.name) }
            startKeepalive()

        case let .authFailed(payload):
            status = .failed(payload.code)
            // A token that cannot be used is thrown away.
            if payload.code == .unknownDeviceToken, let target {
                TokenKeychain.delete(serverName: target.name)
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
