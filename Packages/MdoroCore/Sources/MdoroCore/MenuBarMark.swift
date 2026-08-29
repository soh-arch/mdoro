import Foundation

// REQ-UIX-030 / 035 / REQ-COL-022 / Decision 0031: メニューバーに出す印。
// REQ-UIX-035 asks for the state in the mark's shape so nothing rides on colour alone —
// colour is available; that is not the reason. Facts: docs/PLATFORM.md.
// 実を器に見立て、待機は満ちた実、進行中は水位、一時停止は空の器。
//
// **3枚しか持たない。** 水位を経過に連動させると、満水が待機と、空が一時停止と見分けられなくなる。
// 画像名は `Tools/make_icon.swift` が書き出す imageset 名と一致していること。
// **存在しないアセット名は、エラーにならず何も描かれない。** `MenuBarMarkTests` が実在を検証する。
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

    // FINISHED は待機、PENDING_DECISION は一時停止に相乗りさせる。**どちらも専用の絵を持たない。**
    public static func mark(for runState: RunState) -> MenuBarMark {
        switch runState {
        case .idle, .finished: return .idle
        case .running: return .running
        case .paused, .pendingDecision: return .paused
        }
    }
}
