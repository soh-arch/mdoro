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
            // ※2: sessionType が WORK の場合のみ、※3: 猶予内かつ未確定の場合のみ。
            // RunState のみでは判定しきれない条件は TimerEngine.reduce 側の追加ガードで扱う。
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
