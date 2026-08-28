import Foundation

// REQ-TIM-030 / 4.6: 状態遷移マトリクスは「受理可否」のみを定める。副作用は TimerEngine に一本化する。
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
            // WORK 限定・猶予内という条件は TimerEngine.reduce のガードが見る。
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
