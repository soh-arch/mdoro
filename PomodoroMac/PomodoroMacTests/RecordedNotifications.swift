import Foundation
import MdoroCore
@testable import MdoroMac

// Where the notification centre would be.
//
// This target's tests run inside MdoroMac.app, under the app's own bundle identifier, so a
// request handed to `UNUserNotificationCenter` is delivered to the person sitting at the
// machine — and `cancelAll` throws away what the real app had scheduled. Without this stand-in
// the product owner gets notifications mid-session from a test run, two at a time, once per case
// in `everySoundIsWrittenTheSameWay` — which is how it was found.
//
// What those tests read is the diagnostic log, not the notification, so nothing is lost by
// stopping here. The calls are kept rather than dropped: a test that wants to know a boundary
// produced exactly one notification can ask, without the OS being involved.
@MainActor
final class RecordedNotifications: SessionNotifying {

    enum Call: Equatable {
        case sessionFinished(SessionType)
        case preNotificationsRescheduled(SessionType)
        case preNotificationsCancelled
        case allCancelled
        case logWriteFailure
        case soundTest(NotificationSound)
    }

    private(set) var calls: [Call] = []

    var delivered: [Call] {
        calls.filter {
            switch $0 {
            case .sessionFinished, .logWriteFailure, .soundTest: return true
            case .preNotificationsRescheduled, .preNotificationsCancelled, .allCancelled: return false
            }
        }
    }

    func requestAuthorization() async -> NotificationScheduler.AuthorizationOutcome { .granted }

    func currentPermission() async -> NotificationPermission {
        NotificationPermission(isAuthorized: true, alertsEnabled: true, soundEnabled: true, status: "authorized")
    }

    func notifySessionFinished(type: SessionType, nextType: SessionType, taskName: String?, preset: Preset) {
        calls.append(.sessionFinished(type))
    }

    func reschedulePreNotifications(
        preset: Preset, sessionType: SessionType,
        sessionStartedAt: Date?, sessionEndAt: Date?, now: Date
    ) {
        calls.append(.preNotificationsRescheduled(sessionType))
    }

    func cancelPreNotifications() { calls.append(.preNotificationsCancelled) }
    func cancelAll() { calls.append(.allCancelled) }
    func notifyLogWriteFailure() { calls.append(.logWriteFailure) }
    func deliverSoundTest(preset: Preset) { calls.append(.soundTest(preset.notificationSound)) }
}
