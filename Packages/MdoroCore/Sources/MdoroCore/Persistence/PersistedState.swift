import Foundation

// REQ-PER-001: everything that is persisted. **Anything left out shows up only at restore.**
public struct PersistedState: Equatable, Sendable, Codable {
    // The version that keeps a future schema change from silently breaking an older file.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var timer: TimerContext
    public var presets: PresetContext
    public var settings: AppSettings
    // REQ-PER-001: the selection held in TaskContext. The task list itself is not saved — Task.md is its source.
    public var selectedTaskId: String?
    public var selectedTaskSnapshot: String?
    // REQ-LOG-005 / REQ-ERR-004: log entries not yet written. They survive a restart.
    public var pendingLogEntries: [LogEntry]
    public var savedAt: Date

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        timer: TimerContext,
        presets: PresetContext,
        settings: AppSettings = .default,
        selectedTaskId: String? = nil,
        selectedTaskSnapshot: String? = nil,
        pendingLogEntries: [LogEntry] = [],
        savedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.timer = timer
        self.presets = presets
        self.settings = settings
        self.selectedTaskId = selectedTaskId
        self.selectedTaskSnapshot = selectedTaskSnapshot
        self.pendingLogEntries = pendingLogEntries
        self.savedAt = savedAt
    }

    // Keeps an older saved file readable when a field is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        timer = try c.decode(TimerContext.self, forKey: .timer)
        presets = try c.decode(PresetContext.self, forKey: .presets)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .default
        selectedTaskId = try c.decodeIfPresent(String.self, forKey: .selectedTaskId)
        selectedTaskSnapshot = try c.decodeIfPresent(String.self, forKey: .selectedTaskSnapshot)
        pendingLogEntries = try c.decodeIfPresent([LogEntry].self, forKey: .pendingLogEntries) ?? []
        savedAt = try c.decode(Date.self, forKey: .savedAt)
    }

    // REQ-PRS-010 / REQ-TIM-012: the initial values when nothing has been saved.
    public static func initial(now: Date, settings: AppSettings = .default) -> PersistedState {
        let presets = PresetContext.initial()
        return PersistedState(
            timer: .idle(now: now, settings: settings),
            presets: presets,
            settings: settings,
            savedAt: now
        )
    }
}
