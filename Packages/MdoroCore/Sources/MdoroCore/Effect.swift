import Foundation

// REQ-LOG-018: writing the log belongs to the caller. The engine returns only what is to be
// committed, as an Effect.
public enum Effect: Equatable, Sendable {
    case commitLog(LogEntry)
    // REQ-PER-008: nothing is rescheduled.
    case cancelScheduledNotifications
    // REQ-PER-009: the Live Activity ends the moment the state becomes PENDING_DECISION (8.3).
    case endLiveActivity
}

public enum LogOutcome: String, Equatable, Sendable, Codable {
    case completed
    case skipped
    case aborted
}

// REQ-LOG-010 / 011 / 012 / 016 / 017 / 023: everything one log line needs.
public struct LogEntry: Equatable, Sendable, Codable {
    public let sessionType: SessionType
    public let startedAt: Date
    public let endedAt: Date
    public let elapsedSeconds: Int
    public let outcome: LogOutcome
    public let presetName: String
    public let presetEditedDuringSession: Bool
    public let taskSnapshot: String?
    public let extendedSeconds: Int
    public let loopCountAfterCompletion: Int?
    public let longBreakInterval: Int
    public let logicalDate: Date

    public init(
        sessionType: SessionType,
        startedAt: Date,
        endedAt: Date,
        elapsedSeconds: Int,
        outcome: LogOutcome,
        presetName: String,
        presetEditedDuringSession: Bool,
        taskSnapshot: String?,
        extendedSeconds: Int,
        loopCountAfterCompletion: Int?,
        longBreakInterval: Int,
        logicalDate: Date
    ) {
        self.sessionType = sessionType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
        self.outcome = outcome
        self.presetName = presetName
        self.presetEditedDuringSession = presetEditedDuringSession
        self.taskSnapshot = taskSnapshot
        self.extendedSeconds = extendedSeconds
        self.loopCountAfterCompletion = loopCountAfterCompletion
        self.longBreakInterval = longBreakInterval
        self.logicalDate = logicalDate
    }
}

// REQ-TIM-030 and others: an action that was not accepted, or a domain constraint that was broken.
// CaseIterable so the tests can walk every case rather than a list someone has to remember
// to extend (REQ-ERR-010 / Decision 0034).
public enum TimerError: Error, Equatable, Sendable, CaseIterable {
    case invalidStateForAction
    case extendWindowClosed
    case settingOutOfRange
    case presetNotFound
    case presetLimitReached
    case presetNameConflict
    case cannotDeleteLastPreset
    case cannotDeleteActivePreset
    // REQ-TSK-036: selectTask arrived with a stableId that is not in the current list.
    case taskNotFound
}

// REQ-ERR-010 / Decision 0034: a refused action is our own failure, so it carries a domain
// and a code like any other. Without this the diagnostic log's `why` field had a third
// spelling — a bare case name — and a reader could tell where the failure came from.
extension TimerError: DiagnosableError {

    public var errorCode: ErrorCode {
        switch self {
        case .invalidStateForAction: ErrorCode(own: 40)
        case .extendWindowClosed: ErrorCode(own: 41)
        case .settingOutOfRange: ErrorCode(own: 42)
        case .presetNotFound: ErrorCode(own: 43)
        case .presetLimitReached: ErrorCode(own: 44)
        case .presetNameConflict: ErrorCode(own: 45)
        case .cannotDeleteLastPreset: ErrorCode(own: 46)
        case .cannotDeleteActivePreset: ErrorCode(own: 47)
        case .taskNotFound: ErrorCode(own: 48)
        }
    }

    // No case carries a payload, so the case name is its own description and cannot
    // drift away from a hand-written copy.
    public var diagnosticSummary: String { errorCode.summary(String(describing: self)) }
}

// REQ-LOG-018: even when an action is refused, the effects the preceding tick() committed are returned.
public struct TimerFailure: Error, Equatable, Sendable {
    public let error: TimerError
    public let effects: [Effect]

    public init(error: TimerError, effects: [Effect] = []) {
        self.error = error
        self.effects = effects
    }
}
