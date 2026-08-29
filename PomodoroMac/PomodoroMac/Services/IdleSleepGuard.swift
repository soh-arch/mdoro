import Foundation

// REQ-PER-006: **idle sleep** is held off only while RUNNING. Display sleep is not held off.
// The paths that cannot be held off — closing the lid, for one — are handled by the restore of
// REQ-PER-003, so best effort is enough.
final class IdleSleepGuard {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func begin(reason: String = "A session is running") {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: reason
        )
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    deinit { end() }
}
