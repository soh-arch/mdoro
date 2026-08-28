import Foundation

// REQ-PER-001: 永続化する対象一式。**保存漏れは復元時にしか表面化しない。**
public struct PersistedState: Equatable, Sendable, Codable {
    // 将来スキーマを変えたときに、古い形式を黙って壊さないための版数。
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var timer: TimerContext
    public var presets: PresetContext
    public var settings: AppSettings
    // REQ-PER-001: TaskContext の選択情報。タスク一覧そのものは Task.md が正本なので保存しない。
    public var selectedTaskId: String?
    public var selectedTaskSnapshot: String?
    // REQ-LOG-005 / REQ-ERR-004: 書き込めていないログ。再起動しても失わない。
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

    // 項目を増やしても古い保存ファイルが読めるようにする。
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

    // REQ-PRS-010 / REQ-TIM-012: 保存が何も無い状態からの初期値。
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
