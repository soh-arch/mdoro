import Foundation
import UserNotifications
import PomodoroCore

// REQ-NTF-001 / 004 / 005 / 007 / 020〜023: Mac 側の通知。
//
// Mac はアプリが動き続けている前提に立てるため、終了通知は状態遷移を検知して即時に出す。
// 予告通知だけは発火時刻が未来なので事前スケジュールする。
// （iPhone 側は WebSocket に依存できないため、終了通知も事前スケジュールする。REQ-NTF-002 / 工程7）
@MainActor
final class NotificationScheduler {

    private let center = UNUserNotificationCenter.current()
    private var scheduledPreNotificationIds: [String] = []

    private static let preNotificationPrefix = "pre-notification."

    // **`try?` で捨てない。** ここを握り潰していたため、
    // 「許可を求めることすらできていない」状態が誰にも見えなかった（2026-08-27）。
    // 署名のないビルドでは、この呼び出し自体が失敗して notDetermined のまま止まる。
    func requestAuthorization() async -> String? {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? nil : "通知が許可されませんでした。"
        } catch {
            return "通知の許可を求められませんでした: \(String(describing: error))"
        }
    }

    // 鳴らないときに「アプリが壊れている」と思わせない。
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
        content.title = "\(Self.label(for: type)) が終了しました"

        var body = "次は \(Self.label(for: nextType))"
        if type == .work, let taskName, !taskName.isEmpty {
            body = "\(taskName)\n\(body)"
        }
        content.body = body
        apply(sound: preset.notificationSound, timeSensitive: preset.timeSensitiveNotifications, to: content)

        deliverNow(content, identifier: "session-finished.\(UUID().uuidString)")
    }

    // REQ-NTF-007 / 020〜023: 予告通知。発火時刻の決定は PomodoroCore が行う。
    // ここは「決まった時刻に鳴らす」だけを受け持つ。
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
            content.title = "まもなく終了します"
            let remaining = Int((sessionEndAt.timeIntervalSince(fireDate) / 60).rounded())
            content.body = "残り約 \(max(1, remaining)) 分"
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
        content.title = "実績ログを書き込めません"
        content.body = "設定で出力先を確認してください。タイマーは動き続けています。"
        content.sound = .default
        deliverNow(content, identifier: "log-write-failed")
    }

    // REQ-NTF-006 / Decision 0019: 試聴は**本番と同じ経路**で行う。
    // 音源を直接鳴らすと、通知が届かない状態を試聴が隠してしまう。
    func deliverSoundTest(preset: Preset) {
        let content = UNMutableNotificationContent()
        content.title = "通知のテスト"
        content.body = "区切りのときは、この通知が届きます。"
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
        case .work: return "Focus"
        case .shortBreak: return "短い休憩"
        case .longBreak: return "長い休憩"
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
        if !isAuthorized { return "macOS の「通知」設定でこのアプリの通知が許可されていません（\(status)）。" }
        if !alertsEnabled { return "macOS の「通知」設定でバナーが切られています。" }
        if !soundEnabled { return "macOS の「通知」設定で通知音が切られています。アプリ側でどの音を選んでも鳴りません。" }
        return nil
    }
}
