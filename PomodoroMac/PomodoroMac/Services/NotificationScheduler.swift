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

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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

    // OPEN-001: どの音を鳴らすかは未決。ここは「無音を選べる」ことだけを先に満たしておく。
    // 音源が決まるまで、無音以外はすべてシステム既定音を鳴らす。
    private static func sound(for sound: NotificationSound) -> UNNotificationSound? {
        sound == .silent ? nil : .default
    }

    static func label(for type: SessionType) -> String {
        switch type {
        case .work: return "Focus"
        case .shortBreak: return "短い休憩"
        case .longBreak: return "長い休憩"
        }
    }
}
