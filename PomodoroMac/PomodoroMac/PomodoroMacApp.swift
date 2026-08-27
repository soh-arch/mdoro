import SwiftUI
import UserNotifications
import PomodoroCore

@main
struct PomodoroMacApp: App {
    static let mainWindowId = "main"

    @State private var model = AppModel()
    @State private var notificationDelegate = NotificationDelegate()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Pomodoro", id: Self.mainWindowId) {
            MainWindowView()
                .environment(model)
                .task {
                    // ウィンドウを開く手段は Scene 側にしかないので、ここで渡す。
                    model.onShowWindowRequested = {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        openWindow(id: Self.mainWindowId)
                    }
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    model.start()
                }
        }
        .defaultSize(width: 480, height: 620)

        // REQ-UIX-030: メニューバーに常駐し、既定では残り時間とセッション種別を常時表示する。
        MenuBarExtra {
            MenuBarMenuContent(model: model)
        } label: {
            MenuBarLabelView(model: model)
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}


// REQ-NTF-001: アプリを前面に出したままでも区切りは知らせる。
//
// **macOS はアプリが最前面のあいだ、この委譲が無いと通知を出さない。** バナーも音も出ない。
// iPhone 側には最初から置いていたが Mac 側に無く、
// 「Focus が終わっても Mac だけ鳴らない」の原因になっていた（2026-08-27、実機で報告）。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
