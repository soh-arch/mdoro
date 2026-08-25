import Foundation

// REQ-TIM: 4.5 操作の定義 / 4.6 状態遷移マトリクスの操作一覧
public enum TimerAction: Equatable, Sendable {
    case startWork(presetId: String, taskSnapshot: String?)
    case startBreak(type: SessionType, presetId: String)
    case pause
    case resume
    case skip
    case abort
    case extend
    case resetLoopCount
    case confirmRestoredSession(ConfirmDecision)
    case selectTask(snapshot: String?)
    case clearTaskSelection
    case reloadTasks
    case updateSettings(AppSettings)
    case selectPreset(id: String)
    case updatePreset(Preset)
    case createPreset(Preset)
    case duplicatePreset(id: String)
    case deletePreset(id: String)
    case reorderPresets(order: [String])
    case restoreDefaultPreset

    // REQ-TIM-030: 状態遷移マトリクス上の行を識別するための分類。
    var matrixRow: MatrixRow {
        switch self {
        case .startWork, .startBreak: return .startSession
        case .pause: return .pause
        case .resume: return .resume
        case .skip: return .skip
        case .abort: return .abort
        case .extend: return .extend
        case .resetLoopCount: return .resetLoopCount
        case .confirmRestoredSession: return .confirmRestoredSession
        case .selectTask, .clearTaskSelection: return .taskSelection
        case .reloadTasks: return .reloadTasks
        case .updateSettings: return .updateSettings
        case .selectPreset, .updatePreset: return .presetEdit
        case .createPreset, .duplicatePreset, .deletePreset, .reorderPresets, .restoreDefaultPreset:
            return .presetManagement
        }
    }
}

public enum ConfirmDecision: Equatable, Sendable {
    case continueSession
    case complete
    case discard
}

enum MatrixRow {
    case startSession
    case pause
    case resume
    case skip
    case abort
    case extend
    case resetLoopCount
    case confirmRestoredSession
    case taskSelection
    case reloadTasks
    case updateSettings
    case presetEdit
    case presetManagement
}
