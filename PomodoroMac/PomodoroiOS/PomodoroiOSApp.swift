import SwiftUI
import UserNotifications
import PomodoroCore

@main
struct PomodoroiOSApp: App {
    @State private var model = ClientModel()
    @State private var delegate = NotificationDelegate()

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
