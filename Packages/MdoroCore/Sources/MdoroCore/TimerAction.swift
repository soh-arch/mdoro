import Foundation

// REQ-TIM: 4.5 the actions / 4.6 the action rows of the state transition matrix
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

    // REQ-ERR-010 / Decision 0018: the name the diagnostic log carries. **The arguments come from
    // the user, so they stay out.**
    public var diagnosticName: String {
        switch self {
        case .startWork: return "startWork"
        case .startBreak: return "startBreak"
        case .pause: return "pause"
        case .resume: return "resume"
        case .skip: return "skip"
        case .abort: return "abort"
        case .extend: return "extend"
        case .resetLoopCount: return "resetLoopCount"
        case .confirmRestoredSession: return "confirmRestoredSession"
        case .selectTask: return "selectTask"
        case .clearTaskSelection: return "clearTaskSelection"
        case .reloadTasks: return "reloadTasks"
        case .updateSettings: return "updateSettings"
        case .selectPreset: return "selectPreset"
        case .updatePreset: return "updatePreset"
        case .createPreset: return "createPreset"
        case .duplicatePreset: return "duplicatePreset"
        case .deletePreset: return "deletePreset"
        case .reorderPresets: return "reorderPresets"
        case .restoreDefaultPreset: return "restoreDefaultPreset"
        }
    }

    // REQ-TIM-030: the row this action takes in the state transition matrix.
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
