import Testing
import Foundation
@testable import MdoroCore

// The suite runs *inside* MdoroMac.app and MdoroiOS.app — these targets `@testable import` the
// app module, and linking against an app's own symbols is what needs
// `BUNDLE_LOADER = $(TEST_HOST)` (`docs/PLATFORM.md`), so there is no version of this where
// the host is absent.
// An app that starts normally there delivers notifications, takes the window to the front,
// advertises on the LAN and watches the reader's own `Task.md`. The product owner saw all of
// it on their own machine; every contributor would too.
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

@Suite("Tests do not start the app")
struct TestHostTests {

    @Test func bothEntryPointsRefuseToStartUnderTest() throws {
        for path in entryPoints {
            let text = withoutComments(try source(path))
            #expect(
                text.contains(guardClause),
                "\(path) no longer carries `\(guardClause)` — running the suite will start the app for real"
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
                "\(path) does `\(firstStatement ?? "nothing")` before asking whether this is a test run"
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
        // REQ-COM-003: the model is built inside `init`, not as a declaration default — the
        // single-instance check must run before the model exists, and a declaration's default
        // value runs before an init body ever does.
        let marker = "_model = State(initialValue:"
        let construction = try #require(app.range(of: marker))
        // To the bracket that closes `State(`, not a count of characters. The marker does not end in
        // a bracket and still leaves one open, which is why `callArguments` counts the marker's own
        // rather than looking at its last character.
        let statement = try callArguments(openedBy: app[construction.upperBound...], marker)
        let decidedByTheTestRun = statement.contains("TestHost.isRunning")
        #expect(decidedByTheTestRun, "the model is built the same way under test")
        let restoresNothing = statement.contains("InMemoryStateStore")
        #expect(restoresNothing, "a test run restores the reader's saved session and acts on it")
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
        // **`AppModel(` cannot be looked up through `afterEachAnchor` here.** Most of these files
        // do not build one at all, and that is the ordinary case rather than a renamed anchor — so
        // the absence is refused per directory instead of file by file. Renamed in one directory,
        // every loop over its files runs over nothing and every check in it passes, which is what
        // that directory's own count is watching for.
        //
        // **A total across both would not be.** The host app's construction is the only one in
        // `PomodoroMac/PomodoroMac` — the one this check was written for, having sat in neither the
        // seam nor here — and the nine in `PomodoroMacTests` keep a sum above zero after it goes.
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) could not be read; it moved, or its name changed")
            var constructionsRead = 0
            for (name, text) in files {
                for construction in text.components(separatedBy: "AppModel(").dropFirst() {
                    // `AppModel()` — the production one. Nothing substituted, nothing to check.
                    guard !construction.hasPrefix(")") else { continue }
                    // To the bracket that closes the call. A count of characters was spent by the
                    // prose written inside these constructions — and three of them are longer than
                    // the 400 this used to read (440, 414, 414), so the window was already short of
                    // the thing it was watching, and one more argument would have ended it.
                    let arguments = try callArguments(openedBy: construction, "AppModel(")
                    constructionsRead += 1
                    let saysWhereNotificationsGo = arguments.contains("notifications:")
                    #expect(
                        saysWhereNotificationsGo,
                        "\(name) builds an AppModel that delivers to the reader's notification centre"
                    )
                }
            }
            #expect(
                constructionsRead > 0,
                "no `AppModel(` is built with arguments under \(directory), so this read nothing there"
            )
        }
    }

    // REQ-PER-006: the same hole, one dependency along. The requirement tells the OS to keep the
    // machine awake for as long as a session is RUNNING, and `ProcessInfo.beginActivity` raises a
    // system assertion — it does not stop at the process, and no bundle identifier separates the
    // suite's from the app's. Left unsubstituted, every test that starts a session holds the
    // machine of whoever ran it awake, the host app's own model included.
    //
    // Read exactly as the check above: `AppModel()` with no arguments is the app running for a
    // person; anything built with arguments is built for a test and has to say where this goes.
    @Test func noModelBuiltForATestCanHoldTheMacAwake() throws {
        // **`AppModel(` cannot be looked up through `afterEachAnchor` here.** Most of these files
        // do not build one at all, and that is the ordinary case rather than a renamed anchor — so
        // the absence is refused per directory instead of file by file. Renamed in one directory,
        // every loop over its files runs over nothing and every check in it passes, which is what
        // that directory's own count is watching for.
        //
        // **A total across both would not be.** The host app's construction is the only one in
        // `PomodoroMac/PomodoroMac` — the one this check was written for, having sat in neither the
        // seam nor here — and the nine in `PomodoroMacTests` keep a sum above zero after it goes.
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) could not be read; it moved, or its name changed")
            var constructionsRead = 0
            for (name, text) in files {
                for construction in text.components(separatedBy: "AppModel(").dropFirst() {
                    guard !construction.hasPrefix(")") else { continue }
                    let arguments = try callArguments(openedBy: construction, "AppModel(")
                    constructionsRead += 1
                    let saysWhereTheAssertionGoes = arguments.contains("idleSleep:")
                    #expect(
                        saysWhereTheAssertionGoes,
                        "\(name) builds an AppModel that holds the reader's Mac awake"
                    )
                }
            }
            #expect(
                constructionsRead > 0,
                "no `AppModel(` is built with arguments under \(directory), so this read nothing there"
            )
        }
    }

    // Decision 0040: the same hole, one dependency further along. The tokens live in the Keychain
    // rather than in a plist, and the Keychain is not inside this process either: the suite runs
    // under the app's own bundle identifier, so an item a test writes lands in the reader's own
    // login keychain and is still there when the run ends.
    //
    // Read exactly as the two checks above: `AppModel()` with no arguments is the app running for
    // a person; anything built with arguments is built for a test and has to say where this goes.
    @Test func noModelBuiltForATestCanWriteToTheReadersKeychain() throws {
        // **`AppModel(` cannot be looked up through `afterEachAnchor` here.** Most of these files
        // do not build one at all, and that is the ordinary case rather than a renamed anchor — so
        // the absence is refused per directory instead of file by file. Renamed in one directory,
        // every loop over its files runs over nothing and every check in it passes, which is what
        // that directory's own count is watching for.
        //
        // **A total across both would not be.** The host app's construction is the only one in
        // `PomodoroMac/PomodoroMac` — the one this check was written for, having sat in neither the
        // seam nor here — and the nine in `PomodoroMacTests` keep a sum above zero after it goes.
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) could not be read; it moved, or its name changed")
            var constructionsRead = 0
            for (name, text) in files {
                for construction in text.components(separatedBy: "AppModel(").dropFirst() {
                    guard !construction.hasPrefix(")") else { continue }
                    // This argument is the last one, so the whole construction has to fit inside
                    // the window — which is what ending at the bracket gives, rather than the
                    // guessed-at 700 characters that used to stand in for it.
                    let arguments = try callArguments(openedBy: construction, "AppModel(")
                    constructionsRead += 1
                    let saysWhereTheTokensGo = arguments.contains("deviceTokens:")
                    #expect(
                        saysWhereTheTokensGo,
                        "Decision 0040: \(name) builds an AppModel that writes into the reader's Keychain"
                    )
                }
            }
            #expect(
                constructionsRead > 0,
                "no `AppModel(` is built with arguments under \(directory), so this read nothing there"
            )
        }
    }

    // REQ-UIX-030: a scene is placed before any view of it appears, so `.task`
    // cannot reach one. The window opens itself at launch and the menu bar mark is inserted
    // with it — Mdoro taking the screen, and the menu bar, of whoever runs the suite.
    @Test func neitherSceneShowsItselfDuringATestRun() throws {
        let app = withoutComments(try source("PomodoroMac/PomodoroMac/MdoroMacApp.swift"))
        #expect(
            app.contains("defaultLaunchBehavior(TestHost.isRunning ? .suppressed : .presented)"),
            "the main window opens itself during the suite"
        )
        // Look as far as the parenthesis of `MenuBarExtra(` — which is what this now does, rather
        // than the 20 characters that used to stand in for it. The bound is still a bound: the two
        // trailing closures are outside it, and the argument list is 30 characters, so 20 was not
        // reading the whole of what it was pointed at either.
        //
        // 20 left `isInserted:` nine characters from the edge, so a title argument written in front
        // of it — `MenuBarExtra("Mdoro", isInserted: $showsMenuBarExtra)`, which keeps the
        // requirement — would have turned this red for nothing. **That the argument is there is the
        // claim; that it comes first is not.**
        let extra = try #require(app.range(of: "MenuBarExtra("), "REQ-UIX-030: the menu bar mark is gone")
        let arguments = try callArguments(openedBy: app[extra.upperBound...], "MenuBarExtra(")
        let insertionIsConditional = arguments.contains("isInserted:")
        #expect(insertionIsConditional, "the menu bar mark is inserted during the suite")
        #expect(
            app.contains("_showsMenuBarExtra = State(initialValue: !TestHost.isRunning)"),
            "whether the mark is inserted no longer depends on the test run"
        )
    }

    // **The launcher puts these in the host process, not XCTest** — Xcode and
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

    // **And the other one, which is the one XCTestCore tries first.**
    // `loadTestConfiguration` reads the encoded value before it reads the file path, so a
    // launcher that took that route would leave a check on the file path alone answering false
    // — the guard would stand open and nothing would say so. The name reads like a symbol
    // because the constant holds its own name as its value; it is not a typo.
    @Test func theRouteTriedFirstIsWatchedAsWell() {
        #expect(TestHost.isRunning(in: ["XCTestConfigurationEncodedValueEnvironmentKey": "YnBsaXN0"]))
    }
}
