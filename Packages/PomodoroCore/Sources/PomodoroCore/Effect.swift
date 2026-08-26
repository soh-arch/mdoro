import Foundation

// REQ-LOG-018: ログの書き込みは呼び出し側の責務。エンジンは「確定すべき内容」だけを Effect として返す。
public enum Effect: Equatable, Sendable {
    case commitLog(LogEntry)
    // REQ-PER-008: PENDING_DECISION の間はスケジュール済みのローカル通知をすべて取り消す。
    // 既に発火時刻を過ぎているため、再スケジュールは行わない。
    case cancelScheduledNotifications
    // REQ-PER-009: PENDING_DECISION へ遷移した時点で Live Activity を終了させる (8.3)。
    case endLiveActivity
}

public enum LogOutcome: String, Equatable, Sendable {
    case completed
    case skipped
    case aborted
}

// REQ-LOG-010 / 011 / 012 / 016 / 017 / 023: ログ1行に必要な情報。
public struct LogEntry: Equatable, Sendable {
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

// REQ-TIM-030 他: 受理されなかった操作やドメイン制約違反を表す。
public enum TimerError: Error, Equatable, Sendable {
    case invalidStateForAction
    case extendWindowClosed
    case settingOutOfRange
    case presetNotFound
    case presetLimitReached
    case presetNameConflict
    case cannotDeleteLastPreset
    case cannotDeleteActivePreset
}

// REQ-LOG-018: reduce が操作を拒否した場合でも、直前の tick() が確定させた commitLog を
// 呼び出し側が失わずに受け取れるようにする。
public struct TimerFailure: Error, Equatable, Sendable {
    public let error: TimerError
    public let effects: [Effect]

    public init(error: TimerError, effects: [Effect] = []) {
        self.error = error
        self.effects = effects
    }
}
