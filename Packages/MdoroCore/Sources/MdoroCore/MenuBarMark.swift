import Foundation

// REQ-UIX-030 / 035 / REQ-COL-022 / Decision 0031: the mark shown in the menu bar.
// REQ-UIX-035 asks for the state in the mark's shape so nothing rides on colour alone —
// colour is available; that is not the reason. Facts: docs/PLATFORM.md.
// The fruit is read as a vessel: idle is a full one, running is its water level, paused is empty.
//
// **Three images, no more.** Tying the level to elapsed time would leave full indistinguishable
// from idle, and empty from paused.
// The image names must match the imageset names `Tools/make_icon.swift` writes out.
// **A missing asset name is not an error; nothing is drawn.** `MenuBarMarkTests` checks they exist.
public enum MenuBarMark: Equatable, Sendable, CaseIterable {
    case idle
    case running
    case paused

    public var assetName: String {
        switch self {
        case .idle: return "MenuBarIdle"
        case .running: return "MenuBarRunning"
        case .paused: return "MenuBarPaused"
        }
    }

    // FINISHED rides on idle, PENDING_DECISION on paused. **Neither has an image of its own.**
    public static func mark(for runState: RunState) -> MenuBarMark {
        switch runState {
        case .idle, .finished: return .idle
        case .running: return .running
        case .paused, .pendingDecision: return .paused
        }
    }
}
