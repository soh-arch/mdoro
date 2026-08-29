import SwiftUI
import UserNotifications
import MdoroCore

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
                    // The suite runs inside this app, so starting up here would browse for
                    // Bonjour services, schedule notifications and open a Live Activity on
                    // the reader's own phone. See `TestHost`.
                    guard !TestHost.isRunning else { return }
                    // REQ-NTF-011: when launched from a notification, do not show anything as settled
                    // until a sync has happened.
                    delegate.onNotificationOpened = { model.markAwaitingSync() }
                    UNUserNotificationCenter.current().delegate = delegate
                    model.start()
                }
                // REQ-UIX-020: whether a Live Activity can be started turns on whether the app is in the foreground.
                .onChange(of: scenePhase) { _, phase in
                    model.setForeground(phase == .active)
                }
        }
    }
}

// Where a notification tap lands.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onNotificationOpened: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { onNotificationOpened?() }
    }

    // Even while the app is in front, the end of a session is announced.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
