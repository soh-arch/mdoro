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

// 10.2: `resume` on the wire is the engine's `continueSession` inside.
public enum ConfirmDecisionWire: String, Equatable, Sendable, Codable {
    case complete, discard, resume
}

// Each action uses different fields, so all of them are optional. `CommandTranslation` decides
// what is missing and what is spare.
public struct CommandParams: Equatable, Sendable, Codable {
    public var sessionType: SessionType?
    public var decision: ConfirmDecisionWire?
    public var stableId: String?
    public var presetId: String?
    public var preset: Preset?
    public var orderedIds: [String]?
    public var settings: AppSettings?
    // REQ-CFG-018 / REQ-PRT-005: the fields whose value has no case here — an `appearance`, a
    // `menuBarDisplayMode` or a `notificationSound` a later version added. **The value is left
    // out rather than stood in for**, and the command is refused with `settingOutOfRange`
    // (`CommandTranslation`).
    //
    // It is read apart from the rest of the command because the refusal is owed to a
    // `clientRequestId` that sits in the same object: taking the whole command down leaves the
    // iPhone waiting on an answer REQ-CFG-018 requires.
    public var unreadableValues: Set<CommandTranslation.Parameter>

    public init(
        sessionType: SessionType? = nil, decision: ConfirmDecisionWire? = nil,
        stableId: String? = nil, presetId: String? = nil, preset: Preset? = nil,
        orderedIds: [String]? = nil, settings: AppSettings? = nil,
        unreadableValues: Set<CommandTranslation.Parameter> = []
    ) {
        self.sessionType = sessionType
        self.decision = decision
        self.stableId = stableId
        self.presetId = presetId
        self.preset = preset
        self.orderedIds = orderedIds
        self.settings = settings
        self.unreadableValues = unreadableValues
    }

    // 10.2: the fields a `command` carries. `unreadableValues` is not one of them — it is what
    // this end made of what arrived, so it is neither read from the wire nor written to it.
    private enum CodingKeys: String, CodingKey {
        case sessionType, decision, stableId, presetId, preset, orderedIds, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionType = try c.decodeIfPresent(SessionType.self, forKey: .sessionType)
        decision = try c.decodeIfPresent(ConfirmDecisionWire.self, forKey: .decision)
        stableId = try c.decodeIfPresent(String.self, forKey: .stableId)
        presetId = try c.decodeIfPresent(String.self, forKey: .presetId)
        orderedIds = try c.decodeIfPresent([String].self, forKey: .orderedIds)
        var unreadable: Set<CommandTranslation.Parameter> = []
        preset = try Self.value(Preset.self, forKey: .preset, as: .preset,
                                from: c, unreadable: &unreadable)
        settings = try Self.value(AppSettings.self, forKey: .settings, as: .settings,
                                  from: c, unreadable: &unreadable)
        unreadableValues = unreadable
    }

    // REQ-PRT-005: **a value with no case here is answered for; a message that does not hold
    // together is not.**
    //
    // What is caught is a `DecodingError.dataCorrupted` raised while reading this field — which,
    // for the types on the other side of it, means one thing: a raw value none of an enum's cases
    // matches (`"appearance":"sepia"`, `"notificationSound":"gamelan"`, a pre-notification's
    // `type`). REQ-CFG-018 names the answer that value is owed.
    //
    // Everything else says the message itself does not hold together — a number where an object
    // belongs, a field the value cannot do without (`typeMismatch`, `keyNotFound`) — and stays
    // what it was: discarded and counted (REQ-ERR-009).
    //
    // **A number the field's type cannot hold falls on that second side, despite how it reads
    // from the outside.** `4.5` for an hour or `-1` for a `UInt16` fails in the JSON parser
    // before any type here is asked for a value, and what it throws is not a `DecodingError`, so
    // it passes this catch untouched; `JSONDecoder` only wraps it as `dataCorrupted` at the top.
    // The test suite pins that, because the wrapper makes the two look alike from a stack trace.
    private static func value<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        as parameter: CommandTranslation.Parameter,
        from container: KeyedDecodingContainer<CodingKeys>,
        unreadable: inout Set<CommandTranslation.Parameter>
    ) throws -> T? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch let error as DecodingError {
            guard case .dataCorrupted = error else { throw error }
            unreadable.insert(parameter)
            return nil
        }
    }
}

public struct CommandPayload: Equatable, Sendable, Codable {
    // REQ-PRT-003: a resend with the same id is ignored — handled idempotently.
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

// REQ-COM-007: the four points of the NTP method. t1 is set on the request, t2 and t3 by the responder.
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

// 10.2 / Decision 0034 / 0035: `message` is diagnostic. The receiver's wording comes from
// `code`, so the sender does not choose it.
//
// The code settles the message, so there is no second argument — the same reason
// `AppModel.reject` takes the failure itself rather than a code and a sentence. Three call
// sites wrote prose into `error.message` while there was a parameter for it; the two here
// did the same, into a field no screen ever read. Decoding still takes what arrived.
public struct AuthFailedPayload: Equatable, Sendable, Codable {
    public var code: AuthFailureCode
    public var message: String

    public init(code: AuthFailureCode) {
        self.code = code
        self.message = code.diagnosticSummary
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

// MARK: - Envelope

// One message as received. The header is required by REQ-PRT-002.
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

    // REQ-PRT-005: **an unknown message type is ignored.** Throwing instead would drop the
    // connection the moment a future version adds a single message.
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

    // The payload sits flat at the top level: `{"type":..,"messageId":..,"sentAt":..,<payload>}`.
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

    // Merge the header and the payload into one JSON object.
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
