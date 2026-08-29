import SwiftUI
import UserNotifications
import MdoroCore

@main
struct MdoroMacApp: App {
    static let mainWindowId = "main"

    // REQ-PER-003(d) / 004: `AppModel.init` restores what was saved and runs the effects that
    // come with it, which can append to the reader's session log and cancel the notifications
    // they have pending. That happens while the App value is being built — before any view
    // exists, so before the guard in `.task` below could stop it.
    //
    // **三つとも差し替える。** A store holding nothing has nothing to restore, empty bookmarks
    // reach no folder of theirs, and the notification centre is keyed by bundle identifier —
    // `cancelAll` on the real one would discard what the real Mdoro had scheduled. See
    // `TestHost`.
    @State private var model = TestHost.isRunning
        ? AppModel(
            store: InMemoryStateStore(),
            bookmarks: VaultBookmarks(),
            notifications: SilentNotifications()
        )
        : AppModel()
    @State private var notificationDelegate = NotificationDelegate()
    // POL-047 / REQ-UIX-030: **メニューバーの印は Scene であって、`.task` の後ろにいない。**
    // A scene is placed before any view of it appears, so the guard below cannot reach it. The
    // suite would put Mdoro's mark in a contributor's menu bar for the length of the run.
    @State private var showsMenuBarExtra = !TestHost.isRunning
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
        // POL-047: the window opens itself at launch, which under test means Mdoro taking the
        // screen from whoever is running the suite. The scene has to stay — the test bundle is
        // loaded into this app — so what is suppressed is its appearing.
        .defaultLaunchBehavior(TestHost.isRunning ? .suppressed : .presented)

        // REQ-UIX-030: メニューバーに常駐し、既定では残り時間とセッション種別を常時表示する。
        MenuBarExtra(isInserted: $showsMenuBarExtra) {
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
