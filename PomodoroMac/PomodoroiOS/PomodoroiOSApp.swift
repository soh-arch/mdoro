import SwiftUI
import PomodoroCore

@main
struct PomodoroiOSApp: App {
    @State private var model = ClientModel()

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environment(model)
                .task { model.start() }
        }
    }
}
