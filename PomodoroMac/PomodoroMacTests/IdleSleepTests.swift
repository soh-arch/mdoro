import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-PER-006 holds idle sleep off for as long as a session is RUNNING, and
// `ProcessInfo.beginActivity` is not a thing the app keeps to itself — it raises a system
// assertion that keeps the whole machine awake until the token is released.
//
// This target runs inside MdoroMac.app and drives real sessions through `AppModel`, so without a
// stand-in every test that reaches RUNNING holds the machine of whoever ran the suite awake. It
// is the same shape as the notification centre, with the power settings in its place: the app
// doing exactly what it should, at a moment when nobody asked it to.
//
// The rule itself is checked here all the same. Only the destination of the ask belongs to the
// stand-in.

@MainActor
private func modelHolding(_ idleSleep: RecordedSleepGuard) -> AppModel {
    let preset = Preset.standard()
    let settings = AppSettings()
    let saved = PersistedState(
        timer: .idle(now: Date(), settings: settings),
        presets: PresetContext(presets: [preset], activePresetId: preset.id),
        settings: settings,
        savedAt: Date()
    )
    // Nothing here reaches outside the process: the state is in memory, the bookmarks are empty,
    // the notifications stop at `RecordedNotifications`, and the diagnostic log is never opened,
    // so it creates no directory and writes no file.
    return AppModel(
        store: InMemoryStateStore(initial: saved),
        diagnostics: DiagnosticLog(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("MdoroIdleSleepTests-\(UUID().uuidString)", isDirectory: true)
        ),
        bookmarks: VaultBookmarks(),
        notifications: RecordedNotifications(),
        idleSleep: idleSleep,
        // Decision 0040: the Keychain is the reader's too. Nothing here pairs anything.
        deviceTokens: TokensKeptNowhere()
    )
}

@Suite("A test run leaves the Mac's sleep alone (POL-053 / REQ-PER-006)")
@MainActor
struct IdleSleepTests {

    // The ask is made — that is REQ-PER-006 — and it stops at an object with no way to reach
    // `ProcessInfo`.
    @Test func aRunningSessionAsksAndTheAskGoesNoFurther() {
        let idleSleep = RecordedSleepGuard()
        let model = modelHolding(idleSleep)

        model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "task"))

        #expect(model.timer.runState == .running, "the session never started, so nothing below was tested")
        #expect(idleSleep.calls == [.began], "REQ-PER-006: nothing asked to hold idle sleep off while RUNNING")
    }

    // REQ-PER-006: only while RUNNING. Pausing releases it, resuming takes it again.
    @Test func leavingRunningReleasesTheHold() {
        let idleSleep = RecordedSleepGuard()
        let model = modelHolding(idleSleep)

        model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "task"))
        model.send(.pause)
        #expect(model.timer.runState == .paused)
        #expect(idleSleep.calls == [.began, .ended], "REQ-PER-006: idle sleep is still held off while PAUSED")

        model.send(.resume)
        model.send(.abort)
        #expect(model.timer.runState != .running)
        #expect(idleSleep.isActive == false, "REQ-PER-006: the hold outlived the session")
    }

    // `stop()` is the quit path, and it is the one that has to release the assertion even from a
    // state the loop above never reaches.
    @Test func stoppingTheAppReleasesTheHold() {
        let idleSleep = RecordedSleepGuard()
        let model = modelHolding(idleSleep)

        model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "task"))
        #expect(idleSleep.isActive)
        model.stop()
        #expect(idleSleep.isActive == false, "REQ-PER-006: quitting left the machine awake")
    }

    // What the host app hands its own model when it is hosting this run. **Nothing it is asked
    // for reaches the power settings**, whatever `AppModel` decides to ask for later.
    @Test func theStandInHoldsNothingAtAll() {
        let leftAlone = SleepLeftAlone()
        leftAlone.begin()
        #expect(leftAlone.isActive == false, "POL-053: the stand-in is holding a sleep assertion")
        leftAlone.end()
        #expect(leftAlone.isActive == false)
    }
}
