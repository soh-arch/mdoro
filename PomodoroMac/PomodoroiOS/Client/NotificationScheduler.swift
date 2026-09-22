import Foundation
import UserNotifications
import MdoroCore

// REQ-NTF-002: the notifications on the iPhone side **must not depend on the WebSocket.**
// The clause rests on the app being suspended, not on the socket: schedule ahead on an
// absolute-time trigger. Facts: docs/PLATFORM.md.
@MainActor
final class NotificationScheduler {

    private let center = UNUserNotificationCenter.current()
    private var scheduledIds: [String] = []
    // A fingerprint gathering REQ-NTF-003's (a) and (b) into one. Do not rebuild for the same content.
    private var lastSignature: String?

    private static let endPrefix = "session-end."
    private static let prePrefix = "pre-notification."

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // REQ-NTF-003: when either the fire time or the content changes, cancel and rebuild.
    // REQ-NTF-009: a session started while disconnected is built here too, the moment a connection is made.
    func reschedule(for snapshot: StateSnapshot, clockOffset: TimeInterval) {
        let timer = snapshot.timer
        let preset = snapshot.presets.activePreset ?? Preset.standard()

        // REQ-PER-008: while in PENDING_DECISION, cancel every one, including those whose fire time has passed.
        guard timer.runState != .pendingDecision else {
            cancelAll()
            return
        }

        // A session that is not running needs no notification
        guard timer.runState == .running,
              let serverEndAt = timer.sessionEndAt,
              let serverStartedAt = timer.sessionStartedAt else {
            cancelAll()
            return
        }

        // REQ-COM-009: the server's time is corrected to this device's clock before scheduling.
        let endAt = serverEndAt.addingTimeInterval(-clockOffset)
        let startedAt = serverStartedAt.addingTimeInterval(-clockOffset)

        let signature = Self.signature(
            endAt: endAt, timer: timer, preset: preset,
            taskName: snapshot.task.selectedTaskSnapshot
        )
        guard signature != lastSignature else { return }

        cancelAll()
        lastSignature = signature

        scheduleEnd(at: endAt, timer: timer, preset: preset,
                    taskName: snapshot.task.selectedTaskSnapshot)
        schedulePreNotifications(preset: preset, sessionType: timer.sessionType,
                                 startedAt: startedAt, endAt: endAt)
    }

    // REQ-NTF-004: carries the type of the session that ended, the name of the selected task, and the
    // type of the session to do next.
    private func scheduleEnd(at endAt: Date, timer: TimerContext, preset: Preset, taskName: String?) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(Self.label(timer.sessionType)) has ended")
        var body = String(localized: "Next: \(Self.label(timer.nextSessionType))")
        if timer.sessionType == .work, let taskName, !taskName.isEmpty {
            body = "\(taskName)\n\(body)"
        }
        content.body = body
        apply(preset: preset, to: content)

        add(content, at: endAt, identifier: Self.endPrefix + UUID().uuidString)
    }

    // REQ-NTF-007 / 020–023: the pre-notifications. Deciding the fire times belongs to MdoroCore.
    private func schedulePreNotifications(preset: Preset, sessionType: SessionType, startedAt: Date, endAt: Date) {
        guard sessionType == .work, !preset.preNotifications.isEmpty else { return }

        let fireDates = PreNotificationSchedule.fireDates(
            for: preset.preNotifications,
            sessionStartedAt: startedAt, sessionEndAt: endAt, now: Date()
        )
        for fireDate in fireDates {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Ending soon")
            let remaining = max(1, Int((endAt.timeIntervalSince(fireDate) / 60).rounded()))
            content.body = String(localized: "About \(remaining) min left")
            apply(preset: preset, to: content)
            add(content, at: fireDate, identifier: Self.prePrefix + UUID().uuidString)
        }
    }

    private func add(_ content: UNNotificationContent, at fireDate: Date, identifier: String) {
        // REQ-PRT-001 / REQ-COM-014: **which fields are matched, and the zone they are read in, is
        // `NotificationFireTime`'s answer, not this file's.** The Mac side asks the same function
        // (`PomodoroMac/Services/NotificationScheduler.swift`); REQ-COM-014's explicit zone was on
        // this side alone until the two were brought together.
        let components = NotificationFireTime.dateComponents(for: fireDate)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        scheduledIds.append(identifier)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelAll() {
        guard !scheduledIds.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: scheduledIds)
        scheduledIds.removeAll()
        lastSignature = nil
    }

    // REQ-NTF-005: sent as Time Sensitive, and the user can turn that off in the settings.
    // REQ-NTF-006: the sound. ⚠ **On the iPhone that is the OS default or nothing** — the preset
    // may name chime, bell or wood, and `sound(for:)` below collapses all three (Decision 0020).
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
    private func apply(preset: Preset, to content: UNMutableNotificationContent) {
        content.sound = Self.sound(for: preset.notificationSound)
        content.interruptionLevel = preset.timeSensitiveNotifications ? .timeSensitive : .active
    }

    // REQ-NTF-006 / Decision 0020: **the iPhone has the OS's default sound and nothing else.**
    // iOS has no `/System/Library/Sounds`, so 0017's table is for macOS alone. Only silence is shared.
    private static func sound(for sound: NotificationSound) -> UNNotificationSound? {
        sound.isSilent ? nil : .default
    }

    private static func label(_ type: SessionType) -> String {
        switch type {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }
}


private extension NotificationScheduler {
    // REQ-NTF-003: both the fire time (a) and the content (b) are gathered into one fingerprint.
    // Switching preset brings on a reschedule through (b).
    static func signature(endAt: Date, timer: TimerContext, preset: Preset, taskName: String?) -> String {
        let triggers = preset.preNotifications.map { trigger -> String in
            switch trigger {
            case let .beforeEnd(seconds): return "b\(seconds)"
            case let .atElapsedPercent(percent): return "p\(percent)"
            }
        }.joined(separator: ",")
        return [
            String(endAt.timeIntervalSince1970),
            timer.sessionType.rawValue,
            timer.nextSessionType.rawValue,
            taskName ?? "",
            preset.notificationSound.rawValue,
            String(preset.timeSensitiveNotifications),
            triggers,
        ].joined(separator: "|")
    }
}
