import Foundation

// POL-053: everything `AppModel` asks of the power-management API, so a test can stand where
// the OS does.
//
// This is a boundary the reader's Mac is on the other side of. `ProcessInfo.beginActivity`
// does not stay inside the process: it raises a system assertion that keeps the whole machine
// from going to sleep, and it holds until the token is released. The suite runs inside
// MdoroMac.app (`TestHost`) and drives real sessions through `AppModel`, so every test that
// reached RUNNING was holding a contributor's Mac awake — the same shape as POL-047, where the
// notifications a test asked for arrived on the product owner's screen.
//
// **The same seam as `SessionNotifying`, deliberately.** One pattern to learn: a protocol, a
// real implementation that is the default, and an inert one chosen where the model is built.
// The app carries no branch saying "unless this is a test".
@MainActor
protocol IdleSleepGuarding {
    var isActive: Bool { get }
    func begin()
    func end()
}

// REQ-PER-006: **idle sleep** is held off only while RUNNING. Display sleep is not held off.
// The paths that cannot be held off — closing the lid, for one — are handled by the restore of
// REQ-PER-003, so best effort is enough.
final class IdleSleepGuard: IdleSleepGuarding {
    private var activity: NSObjectProtocol?

    // What `pmset -g assertions` shows beside the app while the assertion is up.
    private static let reason = "A session is running"

    var isActive: Bool { activity != nil }

    func begin() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: Self.reason
        )
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    // The same release, written out rather than called: `end()` belongs to the MainActor and a
    // deinit does not. **An assertion is not dropped when its owner is** — it is held by the OS
    // until the token is handed back, and by this point nothing else can hand it back.
    deinit {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
    }
}

// POL-053: where the power-management API would be, when this process is hosting a test bundle.
//
// The app builds its model before any view exists, so the guard in `.task` is too late to stop
// what that model holds — the same reason `SilentNotifications` exists. Unlike the notification
// centre, nothing here is keyed by bundle identifier: an assertion the suite raises holds the
// machine awake for whoever else is using it, and outlives nothing but the process.
@MainActor
final class SleepLeftAlone: IdleSleepGuarding {
    // Nothing is ever held, so nothing is ever active.
    var isActive: Bool { false }
    func begin() {}
    func end() {}
}
