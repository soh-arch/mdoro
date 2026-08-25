import Foundation

// REQ-TIM: 4章 / 10.3 TimerContext
public struct TimerContext: Equatable, Sendable, Codable {
    public var sessionType: SessionType
    public var runState: RunState
    public var sessionStartedAt: Date?
    public var sessionEndAt: Date?
    public var remainingSeconds: Int?
    public var pausedAt: Date?
    public var accumulatedPausedSeconds: Int
    public var finishedAt: Date?
    public var plannedDurationSeconds: Int
    public var extendedSeconds: Int
    public var loopCount: Int
    public var nextSessionType: SessionType
    public var logicalDate: Date
    public var committedAt: Date?
    public var lastSessionEndedAt: Date?
    public var sessionPresetId: String?
    public var sessionPresetName: String?
    public var presetEditedDuringSession: Bool
    public var pendingDecision: PendingDecision?
    public var lastUpdatedAt: Date

    // REQ-LOG-023: ログのタスク名はセッション開始時点のスナップショットを用いる。
    // 仕様書 10.3 の TimerContext 表には現れないが、TaskContext 全体（第6章）は今回のスコープ外のため、
    // ログ確定に必要な最小限のスナップショットのみをここに保持する。
    public var sessionTaskSnapshot: String?

    public init(
        sessionType: SessionType,
        runState: RunState,
        sessionStartedAt: Date?,
        sessionEndAt: Date?,
        remainingSeconds: Int?,
        pausedAt: Date?,
        accumulatedPausedSeconds: Int,
        finishedAt: Date?,
        plannedDurationSeconds: Int,
        extendedSeconds: Int,
        loopCount: Int,
        nextSessionType: SessionType,
        logicalDate: Date,
        committedAt: Date?,
        lastSessionEndedAt: Date?,
        sessionPresetId: String?,
        sessionPresetName: String?,
        presetEditedDuringSession: Bool,
        pendingDecision: PendingDecision?,
        lastUpdatedAt: Date,
        sessionTaskSnapshot: String? = nil
    ) {
        self.sessionType = sessionType
        self.runState = runState
        self.sessionStartedAt = sessionStartedAt
        self.sessionEndAt = sessionEndAt
        self.remainingSeconds = remainingSeconds
        self.pausedAt = pausedAt
        self.accumulatedPausedSeconds = accumulatedPausedSeconds
        self.finishedAt = finishedAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.extendedSeconds = extendedSeconds
        self.loopCount = loopCount
        self.nextSessionType = nextSessionType
        self.logicalDate = logicalDate
        self.committedAt = committedAt
        self.lastSessionEndedAt = lastSessionEndedAt
        self.sessionPresetId = sessionPresetId
        self.sessionPresetName = sessionPresetName
        self.presetEditedDuringSession = presetEditedDuringSession
        self.pendingDecision = pendingDecision
        self.lastUpdatedAt = lastUpdatedAt
        self.sessionTaskSnapshot = sessionTaskSnapshot
    }

    // REQ-TIM-012: 起動直後・リセット直後は WORK を提案する。
    public static func idle(now: Date, settings: AppSettings = .default) -> TimerContext {
        TimerContext(
            sessionType: .work,
            runState: .idle,
            sessionStartedAt: nil,
            sessionEndAt: nil,
            remainingSeconds: nil,
            pausedAt: nil,
            accumulatedPausedSeconds: 0,
            finishedAt: nil,
            plannedDurationSeconds: 0,
            extendedSeconds: 0,
            loopCount: 0,
            nextSessionType: .work,
            logicalDate: LogicalDay.date(for: now, dayStartHour: settings.logicalDayStartHour),
            committedAt: nil,
            lastSessionEndedAt: nil,
            sessionPresetId: nil,
            sessionPresetName: nil,
            presetEditedDuringSession: false,
            pendingDecision: nil,
            lastUpdatedAt: now
        )
    }

    // REQ-TIM-025: UI 上の周回表示は ((loopCount − 1) mod interval) + 1。loopCount が 0 なら 0。
    public func displayLoop(longBreakInterval: Int) -> Int {
        guard loopCount > 0, longBreakInterval > 0 else { return 0 }
        return ((loopCount - 1) % longBreakInterval) + 1
    }
}

// REQ-TIM-033 / 4.1: PENDING_DECISION 時のみ有効な確認用の最小情報
public struct PendingDecision: Equatable, Sendable, Codable {
    public enum Reason: String, Equatable, Sendable, Codable {
        case restoredAfterEnd
        case pausedTooLong
    }

    public var reason: Reason
    public var endedAt: Date
    public var elapsedSeconds: Int

    public init(reason: Reason, endedAt: Date, elapsedSeconds: Int) {
        self.reason = reason
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
    }
}

// REQ-CFG: 9.3 アプリ全体に属する項目のうち、タイマー計算に必要なもののみ抜粋。
public struct AppSettings: Equatable, Sendable, Codable {
    public var logicalDayStartHour: Int
    public var idleResetHours: Int

    public init(logicalDayStartHour: Int = 4, idleResetHours: Int = 12) {
        self.logicalDayStartHour = logicalDayStartHour
        self.idleResetHours = idleResetHours
    }

    public static let `default` = AppSettings()
}

// REQ-TIM-023: 論理日は logicalDayStartHour を境界として定義する。
public enum LogicalDay {
    public static func date(for instant: Date, dayStartHour: Int, calendar: Calendar = .current) -> Date {
        let shifted = instant.addingTimeInterval(TimeInterval(-dayStartHour * 3600))
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return calendar.date(from: components) ?? shifted
    }
}
