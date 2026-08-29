import Foundation

// REQ-TIM: 4.1 state model — session type
public enum SessionType: String, Equatable, Sendable, Codable, CaseIterable {
    case work = "WORK"
    case shortBreak = "SHORT_BREAK"
    case longBreak = "LONG_BREAK"
}

// REQ-TIM: 4.1 state model — run state
public enum RunState: String, Equatable, Sendable, Codable {
    case idle = "IDLE"
    case running = "RUNNING"
    case paused = "PAUSED"
    case finished = "FINISHED"
    case pendingDecision = "PENDING_DECISION"
}
