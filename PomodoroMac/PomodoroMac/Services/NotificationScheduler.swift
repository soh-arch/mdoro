import Foundation
import UserNotifications
import MdoroCore

// Everything `AppModel` can ask of the notification centre, so a test can stand where the centre
// does.
//
// This is the boundary the reader's Mac is on the other side of. `UNUserNotificationCenter`
// belongs to the OS, not to the app: a request handed to it is delivered to the person using
// the machine, and `removeAllPendingNotificationRequests` throws away notifications the real
// app scheduled. The suite runs inside MdoroMac.app (`TestHost`) and shares its bundle
// identifier, so there is no separate centre for it to talk to — the product owner was
// getting notifications mid-session from a test run.
//
// A seam rather than a check inside `deliverNow`: the app should not carry a branch that
// says "unless this is a test", and the cancellations reach the same centre as the
// deliveries, so one place has to cover both. `AppModel` already takes `diagnostics` and
// `bookmarks` this way, for the same reason and with the same default.
@MainActor
protocol SessionNotifying {
    func requestAuthorization() async -> NotificationScheduler.AuthorizationOutcome
    func currentPermission() async -> NotificationPermission
    func notifySessionFinished(type: SessionType, nextType: SessionType, taskName: String?, preset: Preset)
    func reschedulePreNotifications(
        preset: Preset, sessionType: SessionType,
        sessionStartedAt: Date?, sessionEndAt: Date?, now: Date
    )
    func cancelPreNotifications()
    func cancelAll()
    func notifyLogWriteFailure()
    func notifyLogSweepFailure()
    func deliverSoundTest(preset: Preset)
}

// The destination when this process is hosting a test bundle.
//
// The app builds its model before any view exists, so the guards in `.task` are too late to
// stop what that model holds. `store` and `bookmarks` were already substituted there; this is
// the third of the three, and the one whose absence would be worst — the notification centre
// is keyed by bundle identifier, so `cancelAll` reaching it would throw away notifications the
// **real** Mdoro had scheduled for the reader.
//
// Nothing calls these today: `start()` is guarded, and an empty store returns no effects to
// apply. That is the point. **Two of those three facts are about code that is free to
// change**, and the day a restore effect appears the call lands here instead of on the
// reader's machine.
@MainActor
final class SilentNotifications: SessionNotifying {
    func requestAuthorization() async -> NotificationScheduler.AuthorizationOutcome { .granted }

    func currentPermission() async -> NotificationPermission {
        NotificationPermission(isAuthorized: true, alertsEnabled: true, soundEnabled: true, status: "authorized")
    }

    func notifySessionFinished(type: SessionType, nextType: SessionType, taskName: String?, preset: Preset) {}
    func reschedulePreNotifications(
        preset: Preset, sessionType: SessionType,
        sessionStartedAt: Date?, sessionEndAt: Date?, now: Date
    ) {}
    func cancelPreNotifications() {}
    func cancelAll() {}
    func notifyLogWriteFailure() {}
    func notifyLogSweepFailure() {}
    func deliverSoundTest(preset: Preset) {}
}

// REQ-NTF-001 / 004 / 005 / 007 / 020–023: the notifications on the Mac side.
//
// On the Mac it is safe to assume the app keeps running, so the finish notification is raised the
// moment the state transition is detected. Only the pre-notifications have a fire time in the
// future, so they alone are scheduled ahead.
@MainActor
final class NotificationScheduler: SessionNotifying {

    private let center = UNUserNotificationCenter.current()
    private var scheduledPreNotificationIds: [String] = []

    private static let preNotificationPrefix = "pre-notification."

    // REQ-ERR-010 / Decision 0034: the caller needs both answers separately — a fixed
    // sentence for the screen and a domain with a code for the diagnostic log. Returning
    // one string forced the OS's own words into both.
    enum AuthorizationOutcome: Sendable {
        case granted
        case notAllowed
        case failed(ErrorCode)
    }

    // **Not thrown away with `try?`.** In a build without a signature this call itself fails, and
    // swallowing it hides the state where permission has not even been asked for.
    func requestAuthorization() async -> AuthorizationOutcome {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .granted : .notAllowed
        } catch {
            return .failed(ErrorCode(error))
        }
    }

    // **That banners or sound have been turned off on the macOS side is visible only from here.**
    func currentPermission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        return NotificationPermission(
            isAuthorized: settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional,
            alertsEnabled: settings.alertSetting != .disabled,
            soundEnabled: settings.soundSetting != .disabled,
            status: Self.name(for: settings.authorizationStatus)
        )
    }

    private static func name(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    // REQ-NTF-004: it carries the type of the session that ended, the name of the selected task, and
    // the type of the session to do next.
    func notifySessionFinished(
        type: SessionType,
        nextType: SessionType,
        taskName: String?,
        preset: Preset
    ) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(Self.label(for: type)) has ended")

        var body = String(localized: "Next: \(Self.label(for: nextType))")
        if type == .work, let taskName, !taskName.isEmpty {
            body = "\(taskName)\n\(body)"
        }
        content.body = body
        apply(sound: preset.notificationSound, timeSensitive: preset.timeSensitiveNotifications, to: content)

        deliverNow(content, identifier: "session-finished.\(UUID().uuidString)")
    }

    // REQ-NTF-007 / 020–023: deciding the fire times belongs to MdoroCore. This only sounds at the
    // times that were settled on.
    func reschedulePreNotifications(
        preset: Preset,
        sessionType: SessionType,
        sessionStartedAt: Date?,
        sessionEndAt: Date?,
        now: Date
    ) {
        cancelPreNotifications()

        // REQ-NTF-007: pre-notifications are for WORK only.
        guard sessionType == .work,
              let sessionStartedAt, let sessionEndAt,
              !preset.preNotifications.isEmpty else { return }

        let fireDates = PreNotificationSchedule.fireDates(
            for: preset.preNotifications,
            sessionStartedAt: sessionStartedAt,
            sessionEndAt: sessionEndAt,
            now: now
        )

        for (index, fireDate) in fireDates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Ending soon")
            let remaining = Int((sessionEndAt.timeIntervalSince(fireDate) / 60).rounded())
            content.body = String(localized: "About \(max(1, remaining)) min left")
            apply(sound: preset.notificationSound, timeSensitive: preset.timeSensitiveNotifications, to: content)

            let trigger = Self.calendarTrigger(for: fireDate)
            let identifier = "\(Self.preNotificationPrefix)\(index).\(UUID().uuidString)"
            scheduledPreNotificationIds.append(identifier)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    // REQ-PRT-001 / REQ-COM-014: **which fields are matched, and the zone they are read in, is
    // `NotificationFireTime`'s answer, not this file's.** The iPhone side asks the same function
    // (`PomodoroiOS/Client/NotificationScheduler.swift`), so the two cannot drift apart again — which
    // they had, the explicit zone having been on that side alone for close to a year.
    //
    // Fired at an absolute time. In relative seconds it drifts across a wake from sleep (the third
    // principle).
    //
    // A function of its own because the caller hands the trigger straight to
    // `UNUserNotificationCenter`, which this app's test suite must not reach (see the note on
    // `SessionNotifying` above). `UNCalendarNotificationTrigger.dateComponents` reads back, so the
    // check can stand on the trigger itself rather than on a copy of the arithmetic.
    static func calendarTrigger(for fireDate: Date, calendar: Calendar = .current) -> UNCalendarNotificationTrigger {
        let components = NotificationFireTime.dateComponents(for: fireDate, calendar: calendar)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    // REQ-NTF-003 / REQ-PER-008: cancel every pre-notification that has been scheduled.
    func cancelPreNotifications() {
        guard !scheduledPreNotificationIds.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: scheduledPreNotificationIds)
        scheduledPreNotificationIds.removeAll()
    }

    // REQ-PER-008: on entering PENDING_DECISION, cancel everything, including notifications whose fire
    // time has already passed.
    func cancelAll() {
        cancelPreNotifications()
        center.removeAllPendingNotificationRequests()
    }

    // REQ-LOG-005 / REQ-ERR-004: tell the user that writing the log has failed — three in a row,
    // or three of the last ten attempts (Decision 0039).
    func notifyLogWriteFailure() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "The session log cannot be written")
        content.body = String(localized: "Check the destination in Settings. The timer keeps running.")
        content.sound = .default
        deliverNow(content, identifier: "log-write-failed")
    }

    // Decision 0042 / `docs/CONTEXT.md` §2: tell the user that the temporary files this app left in
    // their folder are still there.
    //
    // **The same arrival as a failed write** — a notification, and nothing on the status line. That
    // is what `docs/CONTEXT.md` §2 asks for ("the screen or a notification"), and it is the one the
    // status line would be wrong for: `logWriteFailed` says the session log is not being written,
    // and here it is being written perfectly well. Decision 0042 keeps the tidying from looking like
    // a broken log, and a banner saying otherwise would undo that.
    //
    // **What it can say ends at "there are files that cannot be cleared."** `Sweep` counts them and
    // does not keep their names (`LogTemporaryFile`), so anything more precise would be invented.
    // The reader is pointed at the folder and the shape of the name, which they can act on.
    func notifyLogSweepFailure() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Temporary files are left in your log folder")
        // On one line, because `StringCatalogTests` reads the catalogue for exactly this shape:
        // `String(localized: "…")`. Broken across lines it is not checked, and a key that was never
        // added to the catalogue comes back as itself — which, in English, looks entirely right.
        content.body = String(localized: "Mdoro could not remove the temporary files it left there. They end in .tmp and are safe to delete. Writing the session log is unaffected.")
        content.sound = .default
        deliverNow(content, identifier: "log-sweep-failed")
    }

    // REQ-NTF-006 / Decision 0019: the preview goes **down the same path production uses**.
    // Play the sound file directly and the preview hides the state where no notification arrives.
    func deliverSoundTest(preset: Preset) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification test")
        content.body = String(localized: "This is what you get at each boundary.")
        apply(sound: preset.notificationSound, timeSensitive: preset.timeSensitiveNotifications, to: content)
        deliverNow(content, identifier: "sound-test.\(UUID().uuidString)")
    }

    // MARK: -

    private func deliverNow(_ content: UNNotificationContent, identifier: String) {
        // trigger: nil means deliver immediately.
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    // REQ-NTF-005: sent as Time Sensitive, and the user must be able to turn that off in the settings.
    //
    // ⚠ **Setting the level asks for a Focus to be broken; it does not make it happen.**
    // `.timeSensitive` is gated by the "Time Sensitive Notifications" capability, and **this
    // signature does not have it** — there is no entitlements file in this project. It is not
    // available to add either, on a free Apple Account: it takes a paid membership
    // (`docs/PLATFORM.md` / `docs/platform/0016`). **What the system does with the level when the
    // entitlement is absent is not documented by Apple** — whether it is demoted or passed through
    // is unknown, and the assignment itself cannot fail. Beyond that, the user has two gates of
    // their own (notification settings and the Focus itself), which this clause does not bind.
    // **So a preset with this on does not mean a notification arrives during a Focus.**
    //
    // REQ-NTF-006: the notification sound must be choosable, and silence must be one of the choices.
    private func apply(sound: NotificationSound, timeSensitive: Bool, to content: UNMutableNotificationContent) {
        content.sound = Self.sound(for: sound)
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
    }

    // REQ-NTF-006 / Decision 0017: the sounds are borrowed from the macOS system sounds.
    private static func sound(for sound: NotificationSound) -> UNNotificationSound? {
        if sound.isSilent { return nil }
        guard let fileName = sound.systemSoundFileName else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    static func label(for type: SessionType) -> String {
        switch type {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }
}


// REQ-NTF-001 / 006: how the OS side is treating notifications.
struct NotificationPermission: Equatable, Sendable {
    var isAuthorized: Bool
    var alertsEnabled: Bool
    var soundEnabled: Bool
    var status: String

    // So the reason nothing sounds can be explained by the side where it does not sound.
    var problem: String? {
        if !isAuthorized {
            return String(localized: "Notifications for this app are turned off in macOS Settings (\(status)).")
        }
        if !alertsEnabled {
            return String(localized: "Banners are turned off for this app in macOS Settings.")
        }
        if !soundEnabled {
            return String(localized: "Sound is turned off for this app in macOS Settings. No choice made here will play.")
        }
        return nil
    }
}
