import Foundation
import Network
import PomodoroCore

// REQ-COM-001 / 002: Mac を親（サーバー）、iPhone を子（クライアント）とする。
// 状態同期は WebSocket（JSON）で行う。
//
// **このクラスはドメインの判断を持たない。** 受け取ったメッセージを上位へ渡し、
// 上位が決めた結果を送り返すだけにする。状態の正本は `TimerEngine` にある（3原則の2つ目）。
@MainActor
final class MdoroServer {

    struct Callbacks {
        // hello を受けた。認証の判断は上位（Authenticator）が行う。
        var authenticate: (HelloPayload) -> Authenticator.Decision
        var handleCommand: (CommandPayload) -> Void
        var provideSnapshot: () -> StateSnapshot
        var provideTaskList: () -> TaskListPayload?
        var connectionChanged: (ConnectionState) -> Void
    }

    private(set) var listenPort: UInt16?
    private(set) var connection: NWConnection?
    private(set) var connectedDeviceName: String?
    private(set) var lastHeartbeatAt: Date?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "MdoroMac.Server")
    private var callbacks: Callbacks?
    private var deduplicator = RequestDeduplicator()
    private var heartbeatTimer: Task<Void, Never>?
    // REQ-SEC-004: ユーザーの承認を待っている接続要求。
    private var pendingApproval: (connection: NWConnection, hello: HelloPayload)?
    private var approvalTimeout: Task<Void, Never>?

    // REQ-SEC-004: 確認は60秒で自動的にタイムアウトし、既定は拒否。
    static let approvalTimeoutSeconds: TimeInterval = 60

    // MARK: - 起動

    // **ポートが確定してから返す。** 確定前に返すと、Bonjour の TXT に載せる
    // WebSocket ポートが 0 になり、クライアントが接続先を知る手段を失う。
    func start(callbacks: Callbacks) async throws -> UInt16 {
        self.callbacks = callbacks

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let websocket = NWProtocolWebSocket.Options()
        // 相手からの ping には Network.framework に返させる。
        // アプリ層のハートビート (REQ-COM-005) とは別物なので、こちらは自動でよい。
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

    // MARK: - 接続

    private func accept(_ incoming: NWConnection) {
        // REQ-SEC-004: 既に別のクライアントが繋がっている場合、
        // 受理の可否は authenticate 側（＝ユーザーの承認）が決める。ここでは繋いで hello を待つ。
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
                    // text / binary の両方を JSON として読む。片方だけ受けると、
                    // 送り方を間違えたクライアントが**何の反応もないまま**繋がったように見える。
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

    // MARK: - 受信

    private func handle(_ data: Data, from source: NWConnection) {
        // REQ-ERR-009: 壊れたメッセージは破棄し、接続は維持する。
        guard let envelope = try? MessageCoder.decodeClient(data) else { return }

        switch envelope.body {
        case let .hello(payload):
            handleHello(payload, from: source)

        case let .timeSyncPing(payload):
            // REQ-COM-007: t2 は受信時刻、t3 は応答送信時刻。
            let t2 = Date()
            send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)

        case .heartbeat:
            // REQ-COM-005: サーバー側の「相手が生きている」判定はこれで更新する。
            // 10.2 の Server → Client にハートビートの種別が無いため、返信はしない。
            // クライアント側の生存判定は WebSocket の ping/pong（autoReplyPing）が担う。
            lastHeartbeatAt = Date()

        case let .command(payload):
            guard source === connection else { return }
            // REQ-PRT-003: 同一 clientRequestId の再送は無視する。
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
            send(.welcome(WelcomePayload(deviceToken: token.value, serverName: Host.current().localizedName ?? "Mac")), to: source)
            // **接続済みにしてからスナップショットを取る。**
            // 順番を逆にすると、クライアントが最初に受け取る状態が「未接続」になる。
            callbacks?.connectionChanged(
                ConnectionState(isConnected: true, lastHeartbeatAt: lastHeartbeatAt, peerDeviceName: payload.deviceName)
            )
            // REQ-COM-004: 接続直後は差分ではなく完全な状態を配る。
            if let snapshot = callbacks?.provideSnapshot() { send(.stateSnapshot(snapshot), to: source) }
            if let tasks = callbacks?.provideTaskList() { send(.taskList(tasks), to: source) }

        case .needsUserApproval:
            // REQ-SEC-004: 承認されるまで受け入れない。**接続は開いたまま待たせる。**
            // ここで切ると、ユーザーが「許可」を押しても相手はもういない。
            pendingApproval.map { $0.connection.cancel() }
            pendingApproval = (source, payload)
            startApprovalTimeout()

        case let .reject(code):
            sendThenClose(.authFailed(AuthFailedPayload(code: code, message: Self.message(for: code))), to: source)
        }
    }

    // REQ-SEC-004: 60秒で自動的に拒否する。放置された確認が接続を掴んだままにならないようにする。
    private func startApprovalTimeout() {
        approvalTimeout?.cancel()
        approvalTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.approvalTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resolvePendingApproval(approved: false) }
        }
    }

    // ユーザーの回答を受けて、待たせていた接続要求を片づける。
    func resolvePendingApproval(approved: Bool) {
        approvalTimeout?.cancel()
        approvalTimeout = nil
        guard let pending = pendingApproval else { return }
        pendingApproval = nil

        guard approved else {
            sendThenClose(.authFailed(AuthFailedPayload(code: .connectionRejectedByUser,
                                                        message: "接続が承認されませんでした")), to: pending.connection)
            return
        }
        // 承認されたので、既存接続を切ってから改めて認証させる。
        connection?.cancel()
        connection = nil
        connectedDeviceName = nil
        handleHello(pending.hello, from: pending.connection)
    }

    var hasPendingApproval: Bool { pendingApproval != nil }

    // MARK: - 送信

    // REQ-COM-006: 状態が変化したときだけ送る。残り時間を毎秒送らない。
    func broadcast(_ message: ServerMessage) {
        guard let connection else { return }
        send(message, to: connection)
    }

    private func send(_ message: ServerMessage, to connection: NWConnection) {
        send(message, to: connection, thenClose: false)
    }

    // 拒否の理由は**送り終えてから**切る。送信直後に cancel すると、
    // まだ流れていないフレームごと捨てられ、クライアントは理由を知らないまま切断される。
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

    // MARK: - ハートビート

    // REQ-COM-005: 15秒応答がなければ接続断とみなす。
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

    private static func message(for code: AuthFailureCode) -> String {
        switch code {
        case .invalidPairingCode: return "ペアリングコードが違います"
        case .pairingModeNotActive: return "Mac 側でペアリングを開始してください"
        case .pairingAttemptsExceeded: return "入力を5回間違えたため、ペアリングを終了しました"
        case .unknownDeviceToken: return "この端末は登録されていません"
        case .anotherClientConnected: return "別の端末が接続中です"
        case .connectionRejectedByUser: return "接続が承認されませんでした"
        }
    }
}


// NWListener が ready になるまで待ち、確定したポートを返す。
// 状態ハンドラは自前のキューで走るため、継続の二重再開を箱で防ぐ。
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
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}
