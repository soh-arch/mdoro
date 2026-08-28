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

    // REQ-LOG-023: ログのタスク名はセッション開始時点のスナップショット。
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

// REQ-COL-003: 外観。system / light / dark の3択。
public enum AppearancePreference: String, Equatable, Sendable, Codable, CaseIterable {
    case system, light, dark
}

// REQ-UIX-032: メニューバーの表示密度。
public enum MenuBarDisplayMode: String, Equatable, Sendable, Codable, CaseIterable {
    case timeAndType, timeAndTask, timeOnly, iconOnly
}

// REQ-CFG: 9.3 アプリ全体に属する項目（プリセット非依存）。
// 有効なプリセットの識別子は `PresetContext.activePresetId` が唯一の正であり、ここには持たない。
public struct AppSettings: Equatable, Sendable, Codable {
    public var appearance: AppearancePreference
    public var focusViewDimmed: Bool
    public var logicalDayStartHour: Int
    public var idleResetHours: Int
    // REQ-PLT-003: 実体はセキュリティスコープ付きブックマーク。ここには表示用のパスだけを置く。
    public var taskFilePath: String?
    // REQ-LOG-001 / Decision 0015: 出力先はフォルダとファイル名に分けて持つ。
    public var logFolderPath: String?
    public var logFileName: String
    public var showCompletedTasks: Bool
    public var logTaskAsLink: Bool
    public var logDailySummary: Bool
    public var enterFocusViewOnRotate: Bool
    public var menuBarDisplayMode: MenuBarDisplayMode
    // REQ-UIX-033: 既定は無効。nil のあいだはホットキーを登録しない (Decision 0016)。
    public var pauseResumeHotKey: HotKeyBinding?
    // メインウィンドウを前面に出すホットキー。既定は未設定 (Decision 0016)。
    public var showWindowHotKey: HotKeyBinding?
    // REQ-UIX-033 / Decision 0029: **中断とリセットには割り当てない。** 確認をはさめない経路に破壊的操作を置かない。
    public var startNextHotKey: HotKeyBinding?
    public var skipHotKey: HotKeyBinding?
    // Decision 0016
    public var launchAtLogin: Bool

    public init(
        appearance: AppearancePreference = .system,
        focusViewDimmed: Bool = false,
        logicalDayStartHour: Int = 4,
        idleResetHours: Int = 12,
        taskFilePath: String? = nil,
        logFolderPath: String? = nil,
        logFileName: String = AppSettings.defaultLogFileName,
        showCompletedTasks: Bool = false,
        logTaskAsLink: Bool = false,
        logDailySummary: Bool = false,
        enterFocusViewOnRotate: Bool = true,
        menuBarDisplayMode: MenuBarDisplayMode = .timeAndType,
        pauseResumeHotKey: HotKeyBinding? = nil,
        showWindowHotKey: HotKeyBinding? = nil,
        startNextHotKey: HotKeyBinding? = nil,
        skipHotKey: HotKeyBinding? = nil,
        launchAtLogin: Bool = false
    ) {
        self.appearance = appearance
        self.focusViewDimmed = focusViewDimmed
        self.logicalDayStartHour = logicalDayStartHour
        self.idleResetHours = idleResetHours
        self.taskFilePath = taskFilePath
        self.logFolderPath = logFolderPath
        self.logFileName = logFileName
        self.showCompletedTasks = showCompletedTasks
        self.logTaskAsLink = logTaskAsLink
        self.logDailySummary = logDailySummary
        self.enterFocusViewOnRotate = enterFocusViewOnRotate
        self.menuBarDisplayMode = menuBarDisplayMode
        self.pauseResumeHotKey = pauseResumeHotKey
        self.showWindowHotKey = showWindowHotKey
        self.startNextHotKey = startNextHotKey
        self.skipHotKey = skipHotKey
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppSettings()
    // REQ-LOG-001: 既定名。
    public static let defaultLogFileName = "MdoroLog.md"

    // 9.3 の `logFilePath` に相当する値。フォルダとファイル名から組み立てる。
    public var logFilePath: String? {
        guard let logFolderPath else { return nil }
        return (logFolderPath as NSString).appendingPathComponent(logFileName)
    }

    // ファイル名として成立しているか。パス区切りを含む値は受け付けない。
    public static func isValidLogFileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.hasPrefix(".")
    }

    // REQ-PER-002: 欠けている項目は既定値で補う。設定を増やしても古い保存ファイルを読めるようにする。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        appearance = try c.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? d.appearance
        focusViewDimmed = try c.decodeIfPresent(Bool.self, forKey: .focusViewDimmed) ?? d.focusViewDimmed
        logicalDayStartHour = try c.decodeIfPresent(Int.self, forKey: .logicalDayStartHour) ?? d.logicalDayStartHour
        idleResetHours = try c.decodeIfPresent(Int.self, forKey: .idleResetHours) ?? d.idleResetHours
        taskFilePath = try c.decodeIfPresent(String.self, forKey: .taskFilePath)
        logFolderPath = try c.decodeIfPresent(String.self, forKey: .logFolderPath)
        logFileName = try c.decodeIfPresent(String.self, forKey: .logFileName) ?? d.logFileName
        showCompletedTasks = try c.decodeIfPresent(Bool.self, forKey: .showCompletedTasks) ?? d.showCompletedTasks
        logTaskAsLink = try c.decodeIfPresent(Bool.self, forKey: .logTaskAsLink) ?? d.logTaskAsLink
        logDailySummary = try c.decodeIfPresent(Bool.self, forKey: .logDailySummary) ?? d.logDailySummary
        enterFocusViewOnRotate = try c.decodeIfPresent(Bool.self, forKey: .enterFocusViewOnRotate) ?? d.enterFocusViewOnRotate
        menuBarDisplayMode = try c.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? d.menuBarDisplayMode
        pauseResumeHotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .pauseResumeHotKey)
        showWindowHotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .showWindowHotKey)
        startNextHotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .startNextHotKey)
        skipHotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .skipHotKey)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    // REQ-CFG-018 / 9.3: 範囲外の値は適用しない。
    public func isWithinValidRanges() -> Bool {
        (0...12).contains(logicalDayStartHour)
            && (1...48).contains(idleResetHours)
            && AppSettings.isValidLogFileName(logFileName)
    }
}

// REQ-TIM-023: 論理日は logicalDayStartHour を境界として定義する。
public enum LogicalDay {
    public static func date(for instant: Date, dayStartHour: Int, calendar: Calendar = .current) -> Date {
        let shifted = instant.addingTimeInterval(TimeInterval(-dayStartHour * 3600))
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return calendar.date(from: components) ?? shifted
    }
}
