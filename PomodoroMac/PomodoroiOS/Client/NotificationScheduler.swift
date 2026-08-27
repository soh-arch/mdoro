import Foundation
import UserNotifications
import MdoroCore

// REQ-NTF-002: iPhone 側の通知は **WebSocket 経由のメッセージに依存してはならない。**
// `sessionEndAt` に対する絶対時刻トリガーのローカル通知として**事前にスケジュール**する。
//
// ロック中・バックグラウンドでは WebSocket が OS に止められるため、これ以外に手段がない
// （`docs/CONTEXT.md` §3 の確定事項）。
@MainActor
final class NotificationScheduler {

    private let center = UNUserNotificationCenter.current()
    private var scheduledIds: [String] = []
    // 同じ内容で何度も組み直さないための指紋。REQ-NTF-003 の (a)(b) を1つにまとめたもの。
    private var lastSignature: String?

    private static let endPrefix = "session-end."
    private static let prePrefix = "pre-notification."

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // REQ-NTF-003: 発火時刻または通知内容が変わったら、取り消して組み直す。
    // REQ-NTF-009: 未接続のまま開始されたセッションも、接続した時点でここが呼ばれて組まれる。
    func reschedule(for snapshot: StateSnapshot, clockOffset: TimeInterval) {
        let timer = snapshot.timer
        let preset = snapshot.presets.activePreset ?? Preset.standard()

        // REQ-PER-008: PENDING_DECISION の間は、発火時刻を過ぎた通知も含めてすべて取り消す。
        guard timer.runState != .pendingDecision else {
            cancelAll()
            return
        }

        // 走っていないセッションに通知は要らない。
        guard timer.runState == .running,
              let serverEndAt = timer.sessionEndAt,
              let serverStartedAt = timer.sessionStartedAt else {
            cancelAll()
            return
        }

        // REQ-COM-009: サーバー時刻を自端末の時計へ直してからスケジュールする。
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

    // REQ-NTF-004: 終了したセッション種別・選択中タスク名・次に行うべきセッション種別を含める。
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

    // REQ-NTF-007 / 020〜023: 予告通知。発火時刻の決定は MdoroCore が行う。
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
        // REQ-COM-014: **`DateComponents.timeZone` を明示的に設定する。**
        // 設定しないと、タイムゾーン変更やサマータイム移行で発火時刻がずれる。
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        components.timeZone = TimeZone.current

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

    // REQ-NTF-005 / 006
    private func apply(preset: Preset, to content: UNMutableNotificationContent) {
        content.sound = Self.sound(for: preset.notificationSound)
        content.interruptionLevel = preset.timeSensitiveNotifications ? .timeSensitive : .active
    }

    // REQ-NTF-006 / Decision 0020: **iPhone は OS の既定音のみ。**
    // iOS に `/System/Library/Sounds` は無く（実機ランタイムで確認）、
    // `UNNotificationSound(named:)` はアプリバンドルと Library/Sounds しか見ないため、
    // 0017 の対応表（Glass / Submarine / Pop）は macOS 専用である。
    // 鳴らす／鳴らさないの判断だけは共通なので、無音はここでも効く。
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
    // REQ-NTF-003: 発火時刻 (a) と通知内容 (b) の両方を1つの指紋にまとめる。
    // プリセット切替は (b) を通じて再スケジュールを引き起こす。
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
