import Foundation

// REQ-TIM-030 / 4.6: the state transition matrix decides acceptance only. Side effects are
// TimerEngine's alone.
public enum StateTransitionMatrix {
    public static func canAccept(_ action: TimerAction, in runState: RunState) -> Bool {
        acceptedStates(for: action.matrixRow).contains(runState)
    }

    private static func acceptedStates(for row: MatrixRow) -> Set<RunState> {
        switch row {
        case .startSession:
            return [.idle, .finished]
        case .pause:
            return [.running]
        case .resume:
            return [.paused]
        case .skip:
            return [.running, .paused]
        case .abort:
            return [.running, .paused, .finished]
        case .extend:
            // WORK only, and within the window isWithinExtensionWindow defines: both guarded in TimerEngine.reduce.
            return [.running, .paused, .finished]
        case .resetLoopCount:
            return [.idle, .running, .paused, .finished]
        case .confirmRestoredSession:
            return [.pendingDecision]
        case .taskSelection, .reloadTasks, .updateSettings, .presetEdit, .presetManagement:
            return [.idle, .running, .paused, .finished, .pendingDecision]
        }
    }
}
