import Foundation

// `xcodebuild test` launches MdoroMac.app and MdoroiOS.app for real. The host cannot be
// dropped: both test targets `@testable import` the app module, and a bundle that links
// against an app's own symbols needs `BUNDLE_LOADER = $(TEST_HOST)` to resolve them.
// (`@testable` by itself asks only for `ENABLE_TESTABILITY`; a bundle that needs no app
// symbols can be hosted by the `xctest` tool instead — `docs/PLATFORM.md`.) So the app runs,
// and an app that starts normally reaches outside its own process — it delivers
// notifications, pulls its window in front of whatever the reader was doing, advertises
// Bonjour on the LAN, and watches their `Task.md`.
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

    // **The launcher writes these, not XCTest.** Xcode and `xcodebuild` put them into
    // the host process's environment before the bundle is loaded; XCTestCore is the side that
    // reads them. Neither name appears anywhere in Apple's documentation, so neither is a
    // promise (`docs/PLATFORM.md`).
    //
    // Both are read because the file path is the *second* thing XCTestCore looks at — the
    // encoded value is tried first. A launcher that moved to that route would leave a check on
    // the file path alone answering false, and the guard would open without saying a word.
    static func isRunning(in environment: [String: String]) -> Bool {
        launchKeys.contains { environment[$0] != nil }
    }

    // The second one reads like a symbol name because it is one: the constant
    // `XCTestConfigurationEncodedValueEnvironmentKey` holds its own name as its value. It is
    // not a mistake to tidy up.
    private static let launchKeys = [
        "XCTestConfigurationFilePath",
        "XCTestConfigurationEncodedValueEnvironmentKey",
    ]
}
