import Foundation

// `xcodebuild test` launches MdoroMac.app and MdoroiOS.app for real. The host cannot be
// dropped: both test targets use `@testable import`, which needs `BUNDLE_LOADER =
// $(TEST_HOST)` to link. So the app runs, and an app that starts normally reaches outside
// its own process — it delivers notifications, pulls its window in front of whatever the
// reader was doing, advertises Bonjour on the LAN, and watches their `Task.md`.
//
// The product owner watched that happen on their own machine. Once this is public it happens
// on every contributor's machine and network, every time they run the suite.
//
// So the two entry points ask here before starting anything, and they ask in one place —
// two copies of this condition would drift, and the one that drifted would be the one nobody
// runs. Tests that need a started model build one themselves.
public enum TestHost {

    /// True when this process was launched as the host application for a test bundle.
    public static var isRunning: Bool { isRunning(in: ProcessInfo.processInfo.environment) }

    // XCTest sets this in the host process before the bundle is loaded, whether the tests
    // inside it are written with XCTest or with Testing. Nothing else in the app writes it.
    static func isRunning(in environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
