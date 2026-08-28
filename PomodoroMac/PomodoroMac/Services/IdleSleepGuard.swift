import Foundation

// REQ-PER-006: RUNNING の間だけ**アイドルスリープ**を抑止する。ディスプレイのスリープは抑止しない。
// 蓋を閉じるなど抑止できない経路は REQ-PER-003 の復帰処理が扱うので、best effort でよい。
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
