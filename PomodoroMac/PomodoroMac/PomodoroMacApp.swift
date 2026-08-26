import SwiftUI
import PomodoroCore

@main
struct PomodoroMacApp: App {
    static let mainWindowId = "main"

    @State private var model = AppModel()

    var body: some Scene {
        Window("Pomodoro", id: Self.mainWindowId) {
            MainWindowView()
                .environment(model)
                .task { model.start() }
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
