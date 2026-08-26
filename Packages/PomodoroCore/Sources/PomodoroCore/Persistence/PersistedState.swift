import Foundation

// REQ-PER-001: 状態が変化するたびに永続化する対象一式。
// 「何を保存するか」をここに集約しておかないと、保存漏れが復元時にしか表面化しない。
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
    public var savedAt: Date

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        timer: TimerContext,
        presets: PresetContext,
        settings: AppSettings = .default,
        selectedTaskId: String? = nil,
        selectedTaskSnapshot: String? = nil,
        savedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.timer = timer
        self.presets = presets
        self.settings = settings
        self.selectedTaskId = selectedTaskId
        self.selectedTaskSnapshot = selectedTaskSnapshot
        self.savedAt = savedAt
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
