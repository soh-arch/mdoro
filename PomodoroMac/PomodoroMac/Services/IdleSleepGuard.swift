import Foundation

// REQ-PER-006: RUNNING の間は Mac の**アイドルスリープ**を抑止する。
// ディスプレイのスリープは抑止しない。画面が暗くなること自体は集中の妨げにならない。
//
// 蓋を閉じる・メニューからのスリープ・電源設定によるスリープは抑止できない。
// それらは REQ-PER-003 の復帰処理（`TimerEngine.restore`）が扱う。抑止は best effort でよい。
final class IdleSleepGuard {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func begin(reason: String = "ポモドーロのセッションが進行中") {
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
