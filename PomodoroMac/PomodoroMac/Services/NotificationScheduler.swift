import Foundation
import UserNotifications
import MdoroCore

// REQ-NTF-001 / 004 / 005 / 007 / 020〜023: Mac 側の通知。
//
// Mac はアプリが動き続けている前提に立てるので、終了通知は状態遷移を検知して即時に出す。
// 予告通知だけは発火時刻が未来なので事前スケジュールする。
@MainActor
final class NotificationScheduler {

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

    // **`try?` で捨てない。** 署名のないビルドではこの呼び出し自体が失敗し、
    // 握り潰すと「許可を求めることすらできていない」状態が見えなくなる。
    func requestAuthorization() async -> AuthorizationOutcome {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .granted : .notAllowed
        } catch {
            return .failed(ErrorCode(error))
        }
    }

    // **macOS 側でバナーや音が切られていることは、こちらからしか見えない。**
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

    // REQ-NTF-004: 終了したセッション種別・選択中タスク名・次に行うべきセッション種別を含める。
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

    // REQ-NTF-007 / 020〜023: 発火時刻の決定は MdoroCore。ここは決まった時刻に鳴らすだけ。
    func reschedulePreNotifications(
        preset: Preset,
        sessionType: SessionType,
        sessionStartedAt: Date?,
        sessionEndAt: Date?,
        now: Date
    ) {
        cancelPreNotifications()

        // REQ-NTF-007: 予告は WORK のみ。
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

            // 絶対時刻で撃つ。相対秒だとスリープ復帰でずれる（3原則の3つ目）。
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "\(Self.preNotificationPrefix)\(index).\(UUID().uuidString)"
            scheduledPreNotificationIds.append(identifier)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    // REQ-NTF-003 / REQ-PER-008: スケジュール済みの予告をすべて取り消す。
    func cancelPreNotifications() {
        guard !scheduledPreNotificationIds.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: scheduledPreNotificationIds)
        scheduledPreNotificationIds.removeAll()
    }

    // REQ-PER-008: PENDING_DECISION に入ったら、発火時刻を過ぎた通知を含めてすべて取り消す。
    func cancelAll() {
        cancelPreNotifications()
        center.removeAllPendingNotificationRequests()
    }

    // REQ-LOG-005 / REQ-ERR-004: ログの書き込みに3回失敗したことを伝える。
    func notifyLogWriteFailure() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "The session log cannot be written")
        content.body = String(localized: "Check the destination in Settings. The timer keeps running.")
        content.sound = .default
        deliverNow(content, identifier: "log-write-failed")
    }

    // REQ-NTF-006 / Decision 0019: 試聴は**本番と同じ経路**で行う。
    // 音源を直接鳴らすと、通知が届かない状態を試聴が隠してしまう。
    func deliverSoundTest(preset: Preset) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification test")
        content.body = String(localized: "This is what you get at each boundary.")
        apply(sound: preset.notificationSound, timeSensitive: preset.timeSensitiveNotifications, to: content)
        deliverNow(content, identifier: "sound-test.\(UUID().uuidString)")
    }

    // MARK: -

    private func deliverNow(_ content: UNNotificationContent, identifier: String) {
        // trigger: nil は即時配信。
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    // REQ-NTF-005: Time Sensitive として送出し、ユーザーが設定で無効化できること。
    // REQ-NTF-006: 通知音を選べ、無音も選べること。
    private func apply(sound: NotificationSound, timeSensitive: Bool, to content: UNMutableNotificationContent) {
        content.sound = Self.sound(for: sound)
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
    }

    // REQ-NTF-006 / Decision 0017: 音源は macOS のシステムサウンドを流用する。
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


// REQ-NTF-001 / 006: OS 側で通知がどう扱われているか。
struct NotificationPermission: Equatable, Sendable {
    var isAuthorized: Bool
    var alertsEnabled: Bool
    var soundEnabled: Bool
    var status: String

    // 音が鳴らない理由を、鳴らない側で説明できるようにする。
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
