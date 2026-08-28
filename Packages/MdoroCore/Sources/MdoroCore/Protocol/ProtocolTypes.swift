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
public enum ProtocolErrorCode: String, Equatable, Sendable, Codable, CaseIterable {
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

// REQ-ERR-016 / 10.2 / Decision 0035: the sender does not choose the words on the receiver's
// screen. `error.message` is diagnostic, so the side that has a screen keeps its own sentence
// per code and reads nothing else off the wire.
//
// The switch is exhaustive on purpose. A `default` would let a code added to 10.2 arrive with
// nothing to say, which is the silence REQ-ERR-016 was extended to close;
// `everyRefusalTheMacCanSendHasSomethingToSay` walks `allCases` and would still pass.
// No digits: a number on this screen reads as a code, and Decision 0035 allows exactly one
// screen to show one — the diagnostic log's own write failure, which is not this.
public extension ProtocolErrorCode {
    var displayMessage: String {
        switch self {
        case .invalidStateForAction:
            "Your Mac did not accept that. The timer is not in a state where it applies."
        case .extendWindowClosed:
            "Too late to extend. The window closes one minute after the session ends."
        case .presetLimitReached:
            "Your Mac already holds the maximum number of presets. Remove one there first."
        case .presetNameDuplicate:
            "Another preset already uses that name."
        case .presetNameInvalid:
            "A preset name has to be between one and thirty characters."
        case .cannotDeleteActivePreset:
            "The preset in use cannot be removed. Switch to another one first."
        case .cannotDeleteLastPreset:
            "The last preset cannot be removed."
        case .presetNotFound:
            "That preset is no longer on your Mac."
        case .settingOutOfRange:
            "That value is outside the range your Mac accepts."
        case .invalidFilePath:
            "Your Mac cannot use that folder for the session log. Choose another one there."
        case .invalidPresetOrder:
            "The new order did not match the presets your Mac holds. Nothing changed."
        case .taskFileUnavailable:
            "Your Mac cannot read the task file. Check it in Settings on your Mac."
        case .taskNotFound:
            "That task is no longer in the list. Reload the tasks and pick it again."
        case .logWriteFailed:
            "Your Mac could not write the session log. Check the log folder in Settings on your Mac."
        case .protocolVersionMismatch:
            "This iPhone and your Mac are running different versions of Mdoro. Update both."
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
