import SwiftUI
import UserNotifications
import MdoroCore

@main
struct MdoroMacApp: App {
    static let mainWindowId = "main"

    // REQ-PER-003(d) / 004: `AppModel.init` restores what was saved and runs the effects that
    // come with it, which can append to the reader's session log and cancel the notifications
    // they have pending. That happens while the App value is being built — before any view
    // exists, so before the guard in `.task` below could stop it. A store holding nothing has
    // nothing to restore, and empty bookmarks reach no folder of theirs. See `TestHost`.
    @State private var model = TestHost.isRunning
        ? AppModel(store: InMemoryStateStore(), bookmarks: VaultBookmarks())
        : AppModel()
    @State private var notificationDelegate = NotificationDelegate()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Mdoro", id: Self.mainWindowId) {
            MainWindowView()
                .environment(model)
                .task {
                    // The suite runs inside this app, so starting up here would advertise on
                    // the LAN, watch the reader's Task.md, take the notification delegate and
                    // pull this window in front of them. See `TestHost`.
                    guard !TestHost.isRunning else { return }
                    // ウィンドウを開く手段は Scene 側にしかない。
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
// **macOS はアプリが最前面のあいだ、この委譲が無いと通知を出さない。**
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
