import Foundation
@testable import MdoroMac

// POL-053: where the power-management API would be.
//
// `ProcessInfo.beginActivity` does not stay inside the process. It raises a system assertion
// that keeps the machine from going to sleep, and this target's tests drive real sessions
// through `AppModel` — every one that reached RUNNING was holding the machine of whoever ran
// the suite awake, for as long as the run lasted.
//
// The calls are kept rather than dropped, the same way `RecordedNotifications` keeps them: what
// `AppModel` does at RUNNING and at every other state is a rule of its own (REQ-PER-006), and a
// test that wants to know it was followed can ask here without the OS being involved.
@MainActor
final class RecordedSleepGuard: IdleSleepGuarding {

    enum Call: Equatable {
        case began
        case ended
    }

    private(set) var calls: [Call] = []

    // What a real guard would be holding by now. `begin` while already active is not a second
    // assertion, so the same collapsing the real one does is done here.
    private(set) var isActive = false

    func begin() {
        guard !isActive else { return }
        isActive = true
        calls.append(.began)
    }

    func end() {
        guard isActive else { return }
        isActive = false
        calls.append(.ended)
    }
}
