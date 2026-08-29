import Testing
import Foundation
@testable import MdoroCore

// POL-047: the suite runs *inside* MdoroMac.app and MdoroiOS.app — these targets `@testable
// import` the app module, and linking against an app's own symbols is what needs
// `BUNDLE_LOADER = $(TEST_HOST)` (`docs/PLATFORM.md`), so there is no version of this where
// the host is absent.
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

    // A guard placed after the call it is meant to prevent is not a guard.
    //
    // Ordering against `model.start()` alone was too weak to match this test's own name: it
    // would have accepted the guard sitting *below* `UNUserNotificationCenter.current()
    // .delegate = …`, which is the suite taking over notification presentation for the app.
    // Every line in the block is something the suite must not do, so the guard has to be the
    // first statement — nothing is allowed in front of it.
    @Test func theGuardComesBeforeAnythingStarts() throws {
        for path in entryPoints {
            let text = withoutComments(try source(path))
            let block = try #require(text.range(of: ".task {"), "\(path) has no .task to guard")
            let firstStatement = text[block.upperBound...]
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            #expect(
                firstStatement == guardClause,
                "POL-047: \(path) does `\(firstStatement ?? "nothing")` before asking whether this is a test run"
            )
            // What is being watched has not disappeared. **A check that swings at nothing cannot
            // be told apart from a check that passes.**
            #expect(text.contains("model.start()"), "\(path) no longer calls model.start()")
        }
    }

    // The Mac's model is built while the App value is, which is earlier than any view and so
    // earlier than the guard above. `AppModel.init` restores the saved state and runs the
    // effects that come with it (REQ-PER-003(d) / 004): an append to the reader's session log
    // and a cancellation of their pending notifications, from a suite that had not started
    // the app at all. So the store it is handed under test has to hold nothing.
    @Test func theMacsModelIsBuiltWithNothingToRestore() throws {
        let app = withoutComments(try source("PomodoroMac/PomodoroMac/MdoroMacApp.swift"))
        let construction = try #require(app.range(of: "var model ="))
        let statement = app[construction.upperBound...].prefix(200)
        #expect(statement.contains("TestHost.isRunning"), "POL-047: the model is built the same way under test")
        #expect(
            statement.contains("InMemoryStateStore"),
            "POL-047: a test run restores the reader's saved session and acts on it"
        )
    }

    // The guards above stop the app from *starting*. They do not stop a model from being
    // built holding the real thing, and two were: `DiagnosticLogTests` asked one for a
    // notification, which went to `UNUserNotificationCenter` under the app's own bundle
    // identifier and arrived on the product owner's screen mid-session — and the host app's
    // own model, which substituted its store and its bookmarks but not this.
    //
    // The default is the real centre, and it has to be: that is the app. **`AppModel()` with
    // no arguments is the app running for a person** and is the only form exempt here.
    // Anything built with arguments is built for a test — by the suite, or by the host app
    // *for* the suite — and has to name a destination that is not the reader's.
    //
    // Both directories, because the host app's construction sat in neither the seam nor this
    // check and was the only one in the repository to get past both.
    @Test func noModelBuiltForATestCanReachTheNotificationCentre() throws {
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) could not be read; it moved, or its name changed")
            for (name, text) in files {
                for construction in text.components(separatedBy: "AppModel(").dropFirst() {
                    // `AppModel()` — the production one. Nothing substituted, nothing to check.
                    guard !construction.hasPrefix(")") else { continue }
                    #expect(
                        construction.prefix(400).contains("notifications:"),
                        "POL-047: \(name) builds an AppModel that delivers to the reader's notification centre"
                    )
                }
            }
        }
    }

    // POL-053: the same hole, one dependency along. REQ-PER-006 tells the OS to keep the machine
    // awake for as long as a session is RUNNING, and `ProcessInfo.beginActivity` raises a system
    // assertion — it does not stop at the process, and no bundle identifier separates the suite's
    // from the app's. Every test that started a session was holding the machine of whoever ran it
    // awake, including the host app's own model, which had substituted three things and not this.
    //
    // Read exactly as the check above: `AppModel()` with no arguments is the app running for a
    // person; anything built with arguments is built for a test and has to say where this goes.
    @Test func noModelBuiltForATestCanHoldTheMacAwake() throws {
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) could not be read; it moved, or its name changed")
            for (name, text) in files {
                for construction in text.components(separatedBy: "AppModel(").dropFirst() {
                    guard !construction.hasPrefix(")") else { continue }
                    #expect(
                        construction.prefix(400).contains("idleSleep:"),
                        "POL-053: \(name) builds an AppModel that holds the reader's Mac awake"
                    )
                }
            }
        }
    }

    // POL-047 / REQ-UIX-030: a scene is placed before any view of it appears, so `.task`
    // cannot reach one. The window opens itself at launch and the menu bar mark is inserted
    // with it — Mdoro taking the screen, and the menu bar, of whoever runs the suite.
    @Test func neitherSceneShowsItselfDuringATestRun() throws {
        let app = withoutComments(try source("PomodoroMac/PomodoroMac/MdoroMacApp.swift"))
        #expect(
            app.contains("defaultLaunchBehavior(TestHost.isRunning ? .suppressed : .presented)"),
            "POL-047: the main window opens itself during the suite"
        )
        // Look as far as the parenthesis of `MenuBarExtra(`. `showsMenuBarExtra` comes before it.
        let extra = try #require(app.range(of: "MenuBarExtra("), "REQ-UIX-030: the menu bar mark is gone")
        #expect(
            app[extra.upperBound...].prefix(20).contains("isInserted:"),
            "POL-047: the menu bar mark is inserted during the suite"
        )
        #expect(
            app.contains("showsMenuBarExtra = !TestHost.isRunning"),
            "POL-047: whether the mark is inserted no longer depends on the test run"
        )
    }

    // POL-111: **the launcher puts these in the host process, not XCTest** — Xcode and
    // `xcodebuild` write them and XCTestCore reads them (`docs/PLATFORM.md`). Nothing else
    // writes either, and an app run by a person has neither, which is the whole reason the
    // check is safe to leave in.
    //
    // The detection is read here through the environment it is given, not through
    // `TestHost.isRunning`: `swift test` has no host app and no launcher writing either
    // variable, so **`isRunning` answering false in this suite is correct.** Where it has to
    // answer true is the app targets, and that is what their `TestHostDetectionTests` are for.
    @Test func theVariableTheLauncherWritesIsWhatDecides() {
        #expect(TestHost.isRunning(in: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(TestHost.isRunning(in: [:]) == false)
        #expect(TestHost.isRunning(in: ["HOME": "/Users/someone"]) == false)
    }

    // POL-111: **and the other one, which is the one XCTestCore tries first.**
    // `loadTestConfiguration` reads the encoded value before it reads the file path, so a
    // launcher that took that route would leave a check on the file path alone answering false
    // — the guard would stand open and nothing would say so. The name reads like a symbol
    // because the constant holds its own name as its value; it is not a typo.
    @Test func theRouteTriedFirstIsWatchedAsWell() {
        #expect(TestHost.isRunning(in: ["XCTestConfigurationEncodedValueEnvironmentKey": "YnBsaXN0"]))
    }
}
