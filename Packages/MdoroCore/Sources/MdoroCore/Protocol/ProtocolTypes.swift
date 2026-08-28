import Foundation

// REQ-PRT-004: プロトコルバージョンを hello / welcome で交換し、非互換なら接続を拒否する。
public enum PomodoroProtocol {
    public static let version = 1

    public static func isCompatible(_ other: Int) -> Bool { other == version }
}

// REQ-PRT-002: すべてのメッセージは type / messageId / sentAt を必須で持つ。
public struct MessageHeader: Equatable, Sendable, Codable {
    public var messageId: String
    public var sentAt: Date

    public init(messageId: String = UUID().uuidString, sentAt: Date = Date()) {
        self.messageId = messageId
        self.sentAt = sentAt
    }
}

// REQ-COM-005 / 10.3 ConnectionState
public struct ConnectionState: Equatable, Sendable, Codable {
    public var isConnected: Bool
    public var lastHeartbeatAt: Date?
    public var peerDeviceName: String?

    public init(isConnected: Bool = false, lastHeartbeatAt: Date? = nil, peerDeviceName: String? = nil) {
        self.isConnected = isConnected
        self.lastHeartbeatAt = lastHeartbeatAt
        self.peerDeviceName = peerDeviceName
    }
}

// 10.2 stateSnapshot のペイロード。
// REQ-COM-007〜009: clockOffsetMs / roundTripMs は**含めない**。クライアントが自分で測る値である。
public struct StateSnapshot: Equatable, Sendable, Codable {
    public var timer: TimerContext
    public var task: TaskContext
    public var settings: AppSettings
    public var presets: PresetContext
    public var connection: ConnectionState

    public init(
        timer: TimerContext,
        task: TaskContext,
        settings: AppSettings,
        presets: PresetContext,
        connection: ConnectionState
    ) {
        self.timer = timer
        self.task = task
        self.settings = settings
        self.presets = presets
        self.connection = connection
    }
}

// 10.2 taskList
public struct TaskListPayload: Equatable, Sendable, Codable {
    public var sections: [TaskListSection]
    public var parsedAt: Date
    public var sourcePath: String?
    public var itemCount: Int
    // REQ-TSK-037 / REQ-ERR-003
    public var isTruncated: Bool
    public var parseError: String?

    public init(
        sections: [TaskListSection], parsedAt: Date, sourcePath: String?,
        itemCount: Int, isTruncated: Bool, parseError: String? = nil
    ) {
        self.sections = sections
        self.parsedAt = parsedAt
        self.sourcePath = sourcePath
        self.itemCount = itemCount
        self.isTruncated = isTruncated
        self.parseError = parseError
    }
}

public struct TaskListSection: Equatable, Sendable, Codable {
    public var name: String
    public var items: [TaskItem]

    public init(name: String, items: [TaskItem]) {
        self.name = name
        self.items = items
    }
}

// 10.2 sessionEvent
public enum SessionEventKind: String, Equatable, Sendable, Codable, CaseIterable {
    case started, paused, resumed, extended
    case reachedEnd
    case completionRevoked
    case committed
    case skipped, aborted
    case loopCountReset
    case decisionRequired
    case decisionResolved
}

public struct SessionEventPayload: Equatable, Sendable, Codable {
    public var event: SessionEventKind
    public var sessionType: SessionType
    public var loopCount: Int
    public var nextSessionType: SessionType
    // decisionRequired のときのみ。
    public var reason: PendingDecision.Reason?

    public init(
        event: SessionEventKind, sessionType: SessionType, loopCount: Int,
        nextSessionType: SessionType, reason: PendingDecision.Reason? = nil
    ) {
        self.event = event
        self.sessionType = sessionType
        self.loopCount = loopCount
        self.nextSessionType = nextSessionType
        self.reason = reason
    }
}

// 10.2 error.code。TimerError から変換して送る。
public enum ProtocolErrorCode: String, Equatable, Sendable, Codable {
    case invalidStateForAction
    case extendWindowClosed
    case presetLimitReached
    case presetNameDuplicate
    case presetNameInvalid
    case cannotDeleteActivePreset
    case cannotDeleteLastPreset
    case presetNotFound
    case settingOutOfRange
    case invalidFilePath
    case invalidPresetOrder
    case taskFileUnavailable
    case taskNotFound
    case logWriteFailed
    case protocolVersionMismatch

    public init(_ error: TimerError) {
        switch error {
        case .invalidStateForAction: self = .invalidStateForAction
        case .extendWindowClosed: self = .extendWindowClosed
        case .settingOutOfRange: self = .settingOutOfRange
        case .presetNotFound: self = .presetNotFound
        case .presetLimitReached: self = .presetLimitReached
        case .presetNameConflict: self = .presetNameDuplicate
        case .cannotDeleteLastPreset: self = .cannotDeleteLastPreset
        case .cannotDeleteActivePreset: self = .cannotDeleteActivePreset
        case .taskNotFound: self = .taskNotFound
        }
    }
}

// 10.2 authFailed.code
public enum AuthFailureCode: String, Equatable, Sendable, Codable {
    case invalidPairingCode
    case pairingModeNotActive
    case pairingAttemptsExceeded
    case unknownDeviceToken
    case anotherClientConnected
    case connectionRejectedByUser
}
