import Foundation

// REQ-PRT-004: the protocol version is exchanged in hello / welcome, and an incompatible one is refused.
//
// **2 since Decision 0040.** Nothing in 10.2 changed shape, so a version 1 iPhone would decode
// every message and go on failing quietly: the TXT record it reads carries an `id` it knows
// nothing about, and the token it holds is filed under a Bonjour name this Mac no longer keys
// anything by. What is left of a half-working pair is a Mac that answers and a phone that never
// authenticates, with nothing on either screen. The version says so instead.
public enum PomodoroProtocol {
    public static let version = 2

    public static func isCompatible(_ other: Int) -> Bool { other == version }
}

// REQ-PRT-002: every message carries type / messageId / sentAt. None of them is optional.
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

// The payload of 10.2 stateSnapshot.
// REQ-COM-007 to 009: clockOffsetMs / roundTripMs are **not carried**. The client measures those itself.
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
    // Only for decisionRequired.
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

// 10.2 error.code. Converted from TimerError before sending.
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
//
// `Error` and `CaseIterable` for the same two reasons the other refusals have them: a refused
// connection is one of ours and is written like any other (Decision 0034), and a test walks
// every case rather than a list someone has to remember to extend.
public enum AuthFailureCode: String, Error, Equatable, Sendable, Codable, CaseIterable {
    case invalidPairingCode
    case pairingModeNotActive
    case pairingAttemptsExceeded
    case unknownDeviceToken
    // REQ-SEC-004: a connection already open is not a reason to refuse — it is the reason to
    // ask. A refusal resting on that question is the user declining or nobody answering in
    // time, and both of those are this. Asking settles nothing else about the hello: what is
    // wrong with the hello is refused as that, before the question or when the answer lands.
    case connectionRejectedByUser
}

// REQ-ERR-010 / Decision 0034 / 0035: a refusal goes out as a code, never as prose.
// `authFailed.message` is diagnostic, like `error.message` beside it — the iPhone reads
// `code` and keeps its own wording — so a sentence written here reaches no screen at all,
// in a shape nothing else in the app uses.
//
// 60–69 belong to this enum. Read the table in `ErrorCode.swift` before taking a number.
// Decision 0034: the numbers are allocated, not counted off. A gap in them stays a gap —
// closing it up would move a meaning onto a number an issue already names.
extension AuthFailureCode: DiagnosableError {

    public var errorCode: ErrorCode {
        switch self {
        case .invalidPairingCode: ErrorCode(own: 60)
        case .pairingModeNotActive: ErrorCode(own: 61)
        case .pairingAttemptsExceeded: ErrorCode(own: 62)
        case .unknownDeviceToken: ErrorCode(own: 63)
        case .connectionRejectedByUser: ErrorCode(own: 65)
        }
    }

    // No case carries a payload, so the case name describes itself and cannot drift away
    // from a hand-written copy.
    public var diagnosticSummary: String { errorCode.summary(rawValue) }
}

// REQ-PRT-004 / 10.2: a refusal of a connection that `authFailed.code` has no word for.
//
// 10.2 files the version mismatch under `error.code`, not under `authFailed.code` — the five
// `authFailed` codes are all about what the hello carried as credentials, and a version is not
// one. Refused as `unknownDeviceToken`, the mismatch reached the iPhone as "this device is no
// longer registered", which the iPhone answers by deleting the device token it holds: updating
// one side alone did not merely mislead, it lost the pairing over a version number.
//
// **An enum with one case, not a struct.** A second reason cannot be added without the
// exhaustive switches below asking for a number and a wire code, which is the same guard
// `TimerError`, `CommandTranslation.Parameter` and `AuthFailureCode` carry.
//
// **And the wire code is not a parameter.** REQ-PRT-005 leaves an `error.code` the other end has
// never heard of looking like a corrupt message, and `protocolVersionMismatch` is the one value
// already in every version's catalogue. A `ProtocolErrorCode` chosen by the caller would read as
// an invitation to refuse an old device with a code that very age keeps it from decoding.
public enum ProtocolRefusal: String, Error, Equatable, Sendable, CaseIterable {
    case protocolVersionMismatch
}

// REQ-ERR-010 / Decision 0034: written into the diagnostic log like every other failure of ours.
//
// 70–79 belong to this enum. Read the table in `ErrorCode.swift` before taking a number, and
// leave any gap where it is — a number in an issue means one thing for good.
extension ProtocolRefusal: DiagnosableError {

    public var errorCode: ErrorCode {
        switch self {
        case .protocolVersionMismatch: ErrorCode(own: 70)
        }
    }

    // No case carries a payload, so the case name describes itself — the same reason
    // `AuthFailureCode` writes itself this way.
    public var diagnosticSummary: String { errorCode.summary(rawValue) }

    // 10.2: which `error.code` carries the refusal out over the wire.
    public var protocolErrorCode: ProtocolErrorCode {
        switch self {
        case .protocolVersionMismatch: .protocolVersionMismatch
        }
    }
}
