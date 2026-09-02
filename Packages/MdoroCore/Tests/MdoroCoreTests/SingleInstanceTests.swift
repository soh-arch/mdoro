import Foundation
import Testing
@testable import MdoroCore

// REQ-COM-003: one Mac, one process, one identity on the air.
struct SingleInstanceTests {

    // The predicate is three conditions joined by "and"; each case below fails a different
    // one, so a mutation that drops or flips any single condition is caught.

    @Test func aLiveProcessWithTheSameBundleIdIsAnotherInstance() {
        #expect(SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: "com.sohta.MdoroMac",
            processIdentifier: 41,
            isTerminated: false,
            ownBundleIdentifier: "com.sohta.MdoroMac",
            ownProcessIdentifier: 42
        ))
    }

    @Test func thisProcessIsNotAnotherInstance() {
        #expect(!SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: "com.sohta.MdoroMac",
            processIdentifier: 42,
            isTerminated: false,
            ownBundleIdentifier: "com.sohta.MdoroMac",
            ownProcessIdentifier: 42
        ))
    }

    @Test func aTerminatedProcessIsNotAnotherInstance() {
        #expect(!SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: "com.sohta.MdoroMac",
            processIdentifier: 41,
            isTerminated: true,
            ownBundleIdentifier: "com.sohta.MdoroMac",
            ownProcessIdentifier: 42
        ))
    }

    @Test func aDifferentBundleIdIsNotAnotherInstance() {
        #expect(!SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: "com.sohta.MdoroiOS",
            processIdentifier: 41,
            isTerminated: false,
            ownBundleIdentifier: "com.sohta.MdoroMac",
            ownProcessIdentifier: 42
        ))
    }

    // When the app cannot tell who it is, it must not exit on a guess.
    @Test func aNilBundleIdOnEitherSideAnswersFalse() {
        #expect(!SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: nil,
            processIdentifier: 41,
            isTerminated: false,
            ownBundleIdentifier: "com.sohta.MdoroMac",
            ownProcessIdentifier: 42
        ))
        #expect(!SingleInstance.isAnotherLiveInstance(
            bundleIdentifier: "com.sohta.MdoroMac",
            processIdentifier: 41,
            isTerminated: false,
            ownBundleIdentifier: nil,
            ownProcessIdentifier: 42
        ))
    }
}

// The exit itself cannot run under test — a process that exits takes the suite with it —
// so the shape of the entry point is what gets checked: the same route the palette and
// menu-bar rules take (`RepositorySources`).
struct SingleInstanceWiringTests {

    private func appSource() throws -> String {
        withoutComments(try source("PomodoroMac/PomodoroMac/MdoroMacApp.swift"))
    }

    // The yielding instance must decide before `AppModel` exists: `AppModel.init` reads and
    // writes state.json and cancels scheduled notifications, and those belong to the
    // instance that stays.
    @Test func theCheckComesBeforeTheModelIsBuilt() throws {
        let text = try appSource()
        let check = try #require(text.range(of: "SingleInstance.existingInstance()"))
        let model = try #require(text.range(of: "AppModel("))
        #expect(check.lowerBound < model.lowerBound)
        #expect(text.contains("exit(0)"))
    }

    // The suite runs inside MdoroMac.app on a machine where the real Mdoro may be running;
    // without this bypass, running the tests would find "another instance" and exit the host.
    @Test func theCheckIsBypassedUnderTest() throws {
        let text = try appSource()
        let line = try #require(
            text.split(separator: "\n").first { $0.contains("SingleInstance.existingInstance()") }
        )
        #expect(line.contains("!TestHost.isRunning"))
    }

    // `LSMultipleInstancesProhibited` looks like the obvious first layer and was tried:
    // LaunchServices enforces it on the test host too — the suite runs inside MdoroMac.app,
    // which shares the bundle identifier with the installed copy — so `xcodebuild test`
    // died at launch on the machine where Mdoro was running (observed 2026-09-02). The key
    // must stay out; the init check is the whole mechanism.
    @Test func infoPlistDoesNotProhibitMultipleInstances() throws {
        let url = repositoryRoot.appendingPathComponent("PomodoroMac/PomodoroMac/Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil
        )
        let dictionary = try #require(plist as? [String: Any])
        #expect(dictionary["LSMultipleInstancesProhibited"] == nil)
    }
}
