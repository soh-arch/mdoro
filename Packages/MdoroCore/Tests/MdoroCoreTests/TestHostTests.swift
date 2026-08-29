import Testing
import Foundation
@testable import MdoroCore

// POL-047: the suite runs *inside* MdoroMac.app and MdoroiOS.app — `@testable import` needs
// `BUNDLE_LOADER = $(TEST_HOST)`, so there is no version of this where the host is absent.
// An app that starts normally there delivers notifications, takes the window to the front,
// advertises on the LAN and watches the reader's own `Task.md`. The product owner saw all of
// it; every contributor would too.
//
// The guard that stops it is one line in a file `swift test` cannot link, which is exactly
// the kind of line that gets deleted in a refactor and noticed by nobody. So this reads the
// two entry points as text, the way `ColorLiteralTests` reads the views. The app targets
// carry the other half — they assert that the detection actually fires — but they do not run
// in CI, and this does.

private let entryPoints = [
    "PomodoroMac/PomodoroMac/MdoroMacApp.swift",
    "PomodoroMac/PomodoroiOS/MdoroiOSApp.swift",
]

private let guardClause = "guard !TestHost.isRunning else { return }"

@Suite("Tests do not start the app (POL-047)")
struct TestHostTests {

    @Test func bothEntryPointsRefuseToStartUnderTest() throws {
        for path in entryPoints {
            let text = withoutComments(try source(path))
            #expect(
                text.contains(guardClause),
                "POL-047: \(path) no longer carries `\(guardClause)` — running the suite will start the app for real"
            )
        }
    }

    // A guard placed after the call it is meant to prevent is not a guard. `model.start()` is
    // where everything that reaches outside the process begins, on both platforms.
    @Test func theGuardComesBeforeAnythingStarts() throws {
        for path in entryPoints {
            let text = withoutComments(try source(path))
            let guardAt = text.range(of: guardClause)
            let startAt = text.range(of: "model.start()")
            #expect(startAt != nil, "\(path) no longer calls model.start(); this test is watching the wrong call")
            guard let guardAt, let startAt else { continue }
            #expect(
                guardAt.lowerBound < startAt.lowerBound,
                "POL-047: \(path) starts the app before it checks whether this is a test run"
            )
        }
    }

    // XCTest sets the variable in the host process. Nothing else does, and an app run by a
    // person never has it — which is the whole reason the check is safe to leave in.
    @Test func theVariableXCTestSetsIsWhatDecides() {
        #expect(TestHost.isRunning(in: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(TestHost.isRunning(in: [:]) == false)
        #expect(TestHost.isRunning(in: ["HOME": "/Users/someone"]) == false)
    }
}
