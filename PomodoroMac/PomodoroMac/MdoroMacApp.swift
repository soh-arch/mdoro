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
    // **All five are replaced.** A store holding nothing has nothing to restore, empty bookmarks
    // reach no folder of theirs, the notification centre is keyed by bundle identifier —
    // `cancelAll` on the real one would discard what the real Mdoro had scheduled — holding
    // off idle sleep (POL-053) reaches past this process to the machine itself, and an item put
    // in the Keychain (Decision 0040) is written into the reader's own login keychain and stays
    // there after the run. See `TestHost`.
    //
    // The values are assigned in `init` rather than at the declarations: a default value is
    // evaluated before an init body runs, and the single-instance check below has to come
    // before `AppModel.init` touches state.json or the notification centre.
    @State private var model: AppModel
    @State private var notificationDelegate: NotificationDelegate
    // POL-047 / REQ-UIX-030: **the mark in the menu bar is a Scene, and does not sit behind `.task`.**
    // A scene is placed before any view of it appears, so the guard below cannot reach it. The
    // suite would put Mdoro's mark in a contributor's menu bar for the length of the run.
    @State private var showsMenuBarExtra: Bool
    @Environment(\.openWindow) private var openWindow

    init() {
        // REQ-COM-003: a second instance would put the same identity on the air
        // twice, so it brings the existing process forward and exits instead of starting.
        // The exit happens before `AppModel` is built — the yielding instance must not read
        // or write state.json, and must not cancel the notifications the running one
        // scheduled. Under test the check is bypassed entirely: the suite runs inside this
        // app on a machine where the real Mdoro may well be running (see `TestHost`).
        if !TestHost.isRunning, let earlier = SingleInstance.existingInstance() {
            // Whether activation is granted is the other instance's business; either way
            // this process has no reason to stay.
            _ = earlier.activate(from: .current, options: [.activateAllWindows])
            exit(0)
        }
        _model = State(initialValue: TestHost.isRunning
            ? AppModel(
                store: InMemoryStateStore(),
                bookmarks: VaultBookmarks(),
                notifications: SilentNotifications(),
                idleSleep: SleepLeftAlone(),
                deviceTokens: TokensKeptNowhere()
            )
            : AppModel())
        _notificationDelegate = State(initialValue: NotificationDelegate())
        _showsMenuBarExtra = State(initialValue: !TestHost.isRunning)
    }

    var body: some Scene {
        Window("Mdoro", id: Self.mainWindowId) {
            MainWindowView()
                .environment(model)
                // POL-114: **this is a view's lifecycle, not the app's.** `.task` runs again every time
                // this view appears, so closing the main window and reopening it ran the app's whole
                // startup a second time — the reader ended up with several Bonjour registrations for one
                // Mac, and the iPhone kept meeting the one that was not in pairing mode.
                //
                // It stays here because of the two things this block does that only a view can:
                // `openWindow` comes out of the Environment, and the POL-047 guard has to sit in front of
                // everything the suite must not do. **What was moved instead is the decision about
                // repeating** — `AppModel.start()` now answers for being called more than once, which is
                // the guarantee an app-lifecycle hook would have given.
                .task {
                    // The suite runs inside this app, so starting up here would advertise on
                    // the LAN, watch the reader's Task.md, take the notification delegate and
                    // pull this window in front of them. See `TestHost`.
                    guard !TestHost.isRunning else { return }
                    // The only means of opening a window is on the Scene side.
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

        // REQ-UIX-030: it lives in the menu bar, and by default shows the remaining time and the session
        // type at all times.
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


// REQ-NTF-001: a boundary is announced even with the app left in front.
// **While the app is frontmost, macOS raises no notification without this delegate.**
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
