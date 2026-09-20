import Foundation

// REQ-TIM: chapter 4 / 10.3 TimerContext
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

    // REQ-LOG-023: the task name in the log is the snapshot taken when the session began.
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

    // REQ-TIM-012: right after launch, and right after a reset, WORK is what is offered.
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

    // REQ-TIM-025: the loop shown in the UI is ((loopCount − 1) mod interval) + 1, or 0 when loopCount is 0.
    public func displayLoop(longBreakInterval: Int) -> Int {
        guard loopCount > 0, longBreakInterval > 0 else { return 0 }
        return ((loopCount - 1) % longBreakInterval) + 1
    }
}

// REQ-TIM-033 / 4.1: the least that is needed to ask, and only while PENDING_DECISION holds
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

// REQ-COL-003: the appearance. One of system, light, dark.
public enum AppearancePreference: String, Equatable, Sendable, Codable, CaseIterable {
    case system, light, dark
}

// REQ-UIX-032: how much the menu bar shows.
public enum MenuBarDisplayMode: String, Equatable, Sendable, Codable, CaseIterable {
    case timeAndType, timeAndTask, timeOnly, iconOnly
}

// REQ-CFG: 9.3 the settings that belong to the app, not to a preset.
// The active preset's identifier is `PresetContext.activePresetId` and nowhere else, so it is not held here.
public struct AppSettings: Equatable, Sendable, Codable {
    public var appearance: AppearancePreference
    public var focusViewDimmed: Bool
    // 9.3 / REQ-COM-003 / Decision 0040: **the name the iPhone sees, and the only name this Mac
    // puts on the LAN.** The Bonjour service name, `welcome.serverName` and the name on the
    // iPhone's lock screen are all this value. It carries no identity — that is the TXT `id`
    // (`ServerID`) — so two Macs sharing a name is untidy rather than broken. The default is
    // `Mdoro` and not the Mac's own name, which usually contains a person's.
    public var displayName: String
    public var logicalDayStartHour: Int
    public var idleResetHours: Int
    // REQ-PLT-003: what actually grants access is a security-scoped bookmark. Only the path to show is kept here.
    public var taskFilePath: String?
    // REQ-LOG-001 / Decision 0015: the destination is held as a folder and a file name, apart.
    public var logFolderPath: String?
    public var logFileName: String
    public var showCompletedTasks: Bool
    public var logTaskAsLink: Bool
    public var logDailySummary: Bool
    public var enterFocusViewOnRotate: Bool
    public var menuBarDisplayMode: MenuBarDisplayMode
    // REQ-UIX-033: off by default. While this is nil, no hot key is registered (Decision 0016).
    public var pauseResumeHotKey: HotKeyBinding?
    // The hot key that brings the main window forward. Unset by default (Decision 0016).
    public var showWindowHotKey: HotKeyBinding?
    // REQ-UIX-033 / Decision 0029: **nothing is bound to abort or reset.** A destructive action does
    // not belong on a path that cannot stop to ask.
    public var startNextHotKey: HotKeyBinding?
    public var skipHotKey: HotKeyBinding?
    // Decision 0016
    public var launchAtLogin: Bool

    public init(
        appearance: AppearancePreference = .system,
        focusViewDimmed: Bool = false,
        displayName: String = AppSettings.defaultDisplayName,
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
        self.displayName = displayName
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
    // REQ-LOG-001: the default name.
    public static let defaultLogFileName = "MdoroLog.md"
    // 9.3 / Decision 0040: the app's own name, so nothing of the reader's goes out until they
    // put it there themselves.
    public static let defaultDisplayName = AppInfo.name

    // The value 9.3 calls `logFilePath`, assembled from the folder and the file name.
    public var logFilePath: String? {
        guard let logFolderPath else { return nil }
        return (logFolderPath as NSString).appendingPathComponent(logFileName)
    }

    // 9.3: one character or more. Whitespace alone is not a name — it would advertise a Mac
    // nothing on the iPhone's screen could tell from an empty row.
    public static func isValidDisplayName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Whether it holds up as a file name. A value containing a path separator is refused.
    public static func isValidLogFileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.hasPrefix(".")
    }

    // REQ-PER-002: a missing field falls back to its default, so an older saved file still reads when a setting is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        appearance = try c.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? d.appearance
        focusViewDimmed = try c.decodeIfPresent(Bool.self, forKey: .focusViewDimmed) ?? d.focusViewDimmed
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
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

    // REQ-UIX-033 / REQ-UIX-037 / 9.3: the range 9.3 sets for all four shortcuts is "contains at
    // least one modifier", and it applies to an assignment that is there. **Unset is within range**
    // — all four are off by default (Decision 0016), so a rule refusing `nil` would have the app
    // turn down its own untouched settings.
    private static func isValidHotKey(_ binding: HotKeyBinding?) -> Bool {
        binding?.hasModifier ?? true
    }

    // REQ-CFG-018 / 9.3: the settings 9.3 puts a range on. **The cases are here; the words for
    // them belong to each platform's `Format`**, the way `ConnectionStatus` and its wording are
    // split (Decision 0022 — this package has no String Catalog to reach).
    //
    // The eight are exactly the rows of 9.3 that state a range. The others (`appearance`, the two
    // paths, the booleans, `menuBarDisplayMode`) have none to be outside of: an enumeration either
    // decodes or does not, and a path is whatever the reader chose in a panel.
    public enum RangedField: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
        case logicalDayStartHour
        case idleResetHours
        case logFileName
        case displayName
        case pauseResumeHotKey
        case showWindowHotKey
        case startNextHotKey
        case skipHotKey
    }

    // REQ-CFG-018 / 9.3: which of the ranged settings is outside its range.
    //
    // **`isWithinValidRanges()` is this list being empty, and not a second copy of the rules.**
    // The rules were written once, inside that method, and only the two paths where the reader
    // changes a setting ever asked them — a value already in the saved file went straight through
    // (`StateStore.loadForStartup`). Putting the reading side right meant knowing *which* field
    // did not hold up, and a separate answer for that would be a second place to add a rule to.
    // So the list is the rule and the Bool is derived from it.
    public func fieldsOutsideValidRanges() -> [RangedField] {
        var outside: [RangedField] = []
        if !(0...12).contains(logicalDayStartHour) { outside.append(.logicalDayStartHour) }
        if !(1...48).contains(idleResetHours) { outside.append(.idleResetHours) }
        if !AppSettings.isValidLogFileName(logFileName) { outside.append(.logFileName) }
        if !AppSettings.isValidDisplayName(displayName) { outside.append(.displayName) }
        // REQ-UIX-033 / REQ-UIX-037: all four, so none is left applied and silent. Asking
        // `hasModifier` only at registration time let a bare key be saved and shown while
        // doing nothing (`HotKeyCenter`).
        if !AppSettings.isValidHotKey(pauseResumeHotKey) { outside.append(.pauseResumeHotKey) }
        if !AppSettings.isValidHotKey(showWindowHotKey) { outside.append(.showWindowHotKey) }
        if !AppSettings.isValidHotKey(startNextHotKey) { outside.append(.startNextHotKey) }
        if !AppSettings.isValidHotKey(skipHotKey) { outside.append(.skipHotKey) }
        return outside
    }

    // REQ-CFG-018 / 9.3: an out-of-range value is not applied.
    public func isWithinValidRanges() -> Bool { fieldsOutsideValidRanges().isEmpty }

    // REQ-CFG-018 / REQ-PER-002 / 9.3: the same settings with whatever is outside 9.3's ranges put
    // back to its default, and a list of what that was.
    //
    // **Field by field, and not the whole record.** A record is refused as a whole where the reader
    // is making the change — they still have the old one, and `didSet` hands it back — but at
    // restore there is nothing to hand back to. Taking the whole record then would throw away the
    // task file, the log folder and the appearance, none of which 9.3 gives a range at all, to
    // answer for one number; and every one of those is a thing the reader chose through a file
    // picker and would have to find again. The minimum that makes the record usable is reset, and
    // the rest is left exactly as it was saved.
    //
    // Each rule in `fieldsOutsideValidRanges()` reads one field and nothing else, and
    // `AppSettings.default` is within range, so what comes back always is too —
    // `SettingsAsReadTests` asks that of the repair rather than leaving it to be believed.
    public func resettingFieldsOutsideValidRanges() -> SettingsAsRead {
        let outside = fieldsOutsideValidRanges()
        guard !outside.isEmpty else { return SettingsAsRead(settings: self, reset: []) }
        let fallback = AppSettings.default
        var repaired = self
        // **Exhaustive on purpose.** A case added to `RangedField` without a line here does not
        // compile, so a rule can never be checked at launch and then left un-repaired.
        for field in outside {
            switch field {
            case .logicalDayStartHour: repaired.logicalDayStartHour = fallback.logicalDayStartHour
            case .idleResetHours: repaired.idleResetHours = fallback.idleResetHours
            case .logFileName: repaired.logFileName = fallback.logFileName
            case .displayName: repaired.displayName = fallback.displayName
            case .pauseResumeHotKey: repaired.pauseResumeHotKey = fallback.pauseResumeHotKey
            case .showWindowHotKey: repaired.showWindowHotKey = fallback.showWindowHotKey
            case .startNextHotKey: repaired.startNextHotKey = fallback.startNextHotKey
            case .skipHotKey: repaired.skipHotKey = fallback.skipHotKey
            }
        }
        return SettingsAsRead(settings: repaired, reset: outside)
    }
}

// REQ-CFG-018 / REQ-PER-002: what a saved settings record is read as.
//
// **The two halves travel together because the second is the only record that the first was
// changed.** Nothing keeps the value that did not hold up: the launch that repairs it saves over
// the file it came from (`AppModel.init`), so if `reset` is dropped on the way to the screen there
// is nowhere left to learn that a setting moved. REQ-LOG-001 is why that matters most for
// `logFileName` — it is half of where the next session is written.
public struct SettingsAsRead: Equatable, Sendable {
    public var settings: AppSettings
    // Empty for a record that held up. Never holds a value, only which setting it was
    // (Decision 0018: a file name is the reader's own).
    public var reset: [AppSettings.RangedField]

    public init(settings: AppSettings, reset: [AppSettings.RangedField]) {
        self.settings = settings
        self.reset = reset
    }
}

// REQ-TIM-023: the logical day is bounded by logicalDayStartHour.
public enum LogicalDay {
    public static func date(for instant: Date, dayStartHour: Int, calendar: Calendar = .current) -> Date {
        let shifted = instant.addingTimeInterval(TimeInterval(-dayStartHour * 3600))
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return calendar.date(from: components) ?? shifted
    }
}
