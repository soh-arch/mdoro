import Foundation

// 10.2 command.action
public enum CommandAction: String, Equatable, Sendable, Codable {
    case startWork, startBreak
    case pause, resume, skip, abort, extend, resetLoopCount
    case confirmRestoredSession
    case selectTask, clearTaskSelection, reloadTasks
    case updateSettings
    case selectPreset, createPreset, duplicatePreset, updatePreset, deletePreset
    case reorderPresets, restoreDefaultPreset
}

// `confirmRestoredSession` の decision。プロトコル上は `resume`、
// エンジン内部の `continueSession` に対応する（10.2）。
public enum ConfirmDecisionWire: String, Equatable, Sendable, Codable {
    case complete, discard, resume
}

// コマンドのパラメータ。action ごとに使うフィールドが違うため、すべて任意にしている。
// 足りない・型が違う場合の判定は `TimerAction(from:presets:)` が行う。
public struct CommandParams: Equatable, Sendable, Codable {
    public var sessionType: SessionType?
    public var decision: ConfirmDecisionWire?
    public var stableId: String?
    public var presetId: String?
    public var preset: Preset?
    public var orderedIds: [String]?
    public var settings: AppSettings?

    public init(
        sessionType: SessionType? = nil, decision: ConfirmDecisionWire? = nil,
        stableId: String? = nil, presetId: String? = nil, preset: Preset? = nil,
        orderedIds: [String]? = nil, settings: AppSettings? = nil
    ) {
        self.sessionType = sessionType
        self.decision = decision
        self.stableId = stableId
        self.presetId = presetId
        self.preset = preset
        self.orderedIds = orderedIds
        self.settings = settings
    }
}

public struct CommandPayload: Equatable, Sendable, Codable {
    // REQ-PRT-003: 同一 ID の再送は無視（冪等に処理）する。
    public var clientRequestId: String
    public var action: CommandAction
    public var params: CommandParams?

    public init(clientRequestId: String = UUID().uuidString, action: CommandAction, params: CommandParams? = nil) {
        self.clientRequestId = clientRequestId
        self.action = action
        self.params = params
    }
}

public struct HelloPayload: Equatable, Sendable, Codable {
    public var protocolVersion: Int
    public var deviceToken: String?
    public var pairingCode: String?
    public var deviceName: String

    public init(protocolVersion: Int = PomodoroProtocol.version,
                deviceToken: String? = nil, pairingCode: String? = nil, deviceName: String) {
        self.protocolVersion = protocolVersion
        self.deviceToken = deviceToken
        self.pairingCode = pairingCode
        self.deviceName = deviceName
    }
}

public struct WelcomePayload: Equatable, Sendable, Codable {
    public var protocolVersion: Int
    public var deviceToken: String
    public var serverName: String

    public init(protocolVersion: Int = PomodoroProtocol.version, deviceToken: String, serverName: String) {
        self.protocolVersion = protocolVersion
        self.deviceToken = deviceToken
        self.serverName = serverName
    }
}

// REQ-COM-007: NTP 方式の4点。t1 は要求時、t2/t3 は応答側が入れる。
public struct TimeSyncPayload: Equatable, Sendable, Codable {
    public var t1: Date
    public var t2: Date?
    public var t3: Date?

    public init(t1: Date, t2: Date? = nil, t3: Date? = nil) {
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
    }
}

public struct ProtocolErrorPayload: Equatable, Sendable, Codable {
    public var code: ProtocolErrorCode
    public var message: String
    public var relatedRequestId: String?

    public init(code: ProtocolErrorCode, message: String, relatedRequestId: String? = nil) {
        self.code = code
        self.message = message
        self.relatedRequestId = relatedRequestId
    }
}

public struct AuthFailedPayload: Equatable, Sendable, Codable {
    public var code: AuthFailureCode
    public var message: String

    public init(code: AuthFailureCode, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Client → Server

public enum ClientMessage: Equatable, Sendable {
    case hello(HelloPayload)
    case timeSyncPing(TimeSyncPayload)
    case heartbeat
    case command(CommandPayload)
    case requestSnapshot

    var typeName: String {
        switch self {
        case .hello: return "hello"
        case .timeSyncPing: return "timeSyncPing"
        case .heartbeat: return "heartbeat"
        case .command: return "command"
        case .requestSnapshot: return "requestSnapshot"
        }
    }
}

// MARK: - Server → Client

public enum ServerMessage: Equatable, Sendable {
    case welcome(WelcomePayload)
    case authFailed(AuthFailedPayload)
    case timeSyncPong(TimeSyncPayload)
    case stateSnapshot(StateSnapshot)
    case taskList(TaskListPayload)
    case sessionEvent(SessionEventPayload)
    case error(ProtocolErrorPayload)

    var typeName: String {
        switch self {
        case .welcome: return "welcome"
        case .authFailed: return "authFailed"
        case .timeSyncPong: return "timeSyncPong"
        case .stateSnapshot: return "stateSnapshot"
        case .taskList: return "taskList"
        case .sessionEvent: return "sessionEvent"
        case .error: return "error"
        }
    }
}

// MARK: - 封筒

// 受け取った1件のメッセージ。ヘッダは REQ-PRT-002 で必須。
public struct Envelope<Body: Sendable & Equatable>: Equatable, Sendable {
    public var header: MessageHeader
    public var body: Body

    public init(header: MessageHeader = MessageHeader(), body: Body) {
        self.header = header
        self.body = body
    }
}

public enum MessageCoder {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private struct TypeProbe: Decodable {
        let type: String
        let messageId: String
        let sentAt: Date
    }

    // REQ-PRT-005: **未知のメッセージ種別は無視する。** throw ではなく nil を返す。
    // 例外にすると、将来のバージョンがメッセージを1つ足しただけで接続が落ちる。
    public static func decodeClient(_ data: Data) throws -> Envelope<ClientMessage>? {
        let probe = try decoder.decode(TypeProbe.self, from: data)
        let header = MessageHeader(messageId: probe.messageId, sentAt: probe.sentAt)
        let body: ClientMessage
        switch probe.type {
        case "hello": body = .hello(try payload(HelloPayload.self, data))
        case "timeSyncPing": body = .timeSyncPing(try payload(TimeSyncPayload.self, data))
        case "heartbeat": body = .heartbeat
        case "command": body = .command(try payload(CommandPayload.self, data))
        case "requestSnapshot": body = .requestSnapshot
        default: return nil
        }
        return Envelope(header: header, body: body)
    }

    public static func decodeServer(_ data: Data) throws -> Envelope<ServerMessage>? {
        let probe = try decoder.decode(TypeProbe.self, from: data)
        let header = MessageHeader(messageId: probe.messageId, sentAt: probe.sentAt)
        let body: ServerMessage
        switch probe.type {
        case "welcome": body = .welcome(try payload(WelcomePayload.self, data))
        case "authFailed": body = .authFailed(try payload(AuthFailedPayload.self, data))
        case "timeSyncPong": body = .timeSyncPong(try payload(TimeSyncPayload.self, data))
        case "stateSnapshot": body = .stateSnapshot(try payload(StateSnapshot.self, data))
        case "taskList": body = .taskList(try payload(TaskListPayload.self, data))
        case "sessionEvent": body = .sessionEvent(try payload(SessionEventPayload.self, data))
        case "error": body = .error(try payload(ProtocolErrorPayload.self, data))
        default: return nil
        }
        return Envelope(header: header, body: body)
    }

    // ペイロードはトップレベルに平置きする。`{"type":..,"messageId":..,"sentAt":..,<payload>}`
    private static func payload<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }

    public static func encode(_ envelope: Envelope<ClientMessage>) throws -> Data {
        try encode(type: envelope.body.typeName, header: envelope.header, payload: {
            switch envelope.body {
            case let .hello(p): return try encoder.encode(p)
            case let .timeSyncPing(p): return try encoder.encode(p)
            case let .command(p): return try encoder.encode(p)
            case .heartbeat, .requestSnapshot: return nil
            }
        })
    }

    public static func encode(_ envelope: Envelope<ServerMessage>) throws -> Data {
        try encode(type: envelope.body.typeName, header: envelope.header, payload: {
            switch envelope.body {
            case let .welcome(p): return try encoder.encode(p)
            case let .authFailed(p): return try encoder.encode(p)
            case let .timeSyncPong(p): return try encoder.encode(p)
            case let .stateSnapshot(p): return try encoder.encode(p)
            case let .taskList(p): return try encoder.encode(p)
            case let .sessionEvent(p): return try encoder.encode(p)
            case let .error(p): return try encoder.encode(p)
            }
        })
    }

    // ヘッダとペイロードを1つの JSON オブジェクトへ合流させる。
    private static func encode(
        type: String, header: MessageHeader, payload: () throws -> Data?
    ) throws -> Data {
        var object: [String: Any] = [
            "type": type,
            "messageId": header.messageId,
            "sentAt": ISO8601DateFormatter().string(from: header.sentAt),
        ]
        if let payloadData = try payload(),
           let fields = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            object.merge(fields) { current, _ in current }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
