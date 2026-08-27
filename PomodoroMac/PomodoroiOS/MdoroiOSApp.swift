import SwiftUI
import UserNotifications
import PomodoroCore

@main
struct MdoroiOSApp: App {
    @State private var model = ClientModel()
    @State private var delegate = NotificationDelegate()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environment(model)
                .task {
                    // REQ-NTF-011: 通知から起動したときは、同期が取れるまで断定的に表示しない。
                    delegate.onNotificationOpened = { model.markAwaitingSync() }
                    UNUserNotificationCenter.current().delegate = delegate
                    model.start()
                }
                // REQ-UIX-020: フォアグラウンドかどうかで Live Activity の開始可否が変わる。
                .onChange(of: scenePhase) { _, phase in
                    model.setForeground(phase == .active)
                }
        }
    }
}

// 通知タップの受け口。前面にいるあいだも通知を出す。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onNotificationOpened: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { onNotificationOpened?() }
    }

    // アプリを開いたままでも区切りは知らせる。黙ると通知の意味がない。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
