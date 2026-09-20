import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// Decision 0042 / `docs/CONTEXT.md` §2: **a launch that never reached the log folder did not sweep
// it**, so it neither adds to the run of failed sweeps nor clears one.
//
// The counting is `LogSweepFailureRunTests` under `swift test`, and that the launch counts, saves and
// tells is `LogSweepWiringTests`. What neither reaches is this: the judgement that an unreachable
// folder is **not** an answer either way. Counting it would report the folder twice over — the write
// that follows this reports it already — and clearing it would let a folder that comes and goes wipe
// out the launches that did fail, so the one file that can never be removed would never reach three.
//
// A sweep that ran and failed is not here: it takes a folder this process really holds and a file in
// it that really refuses to be removed, which is the reader's own folder and their own permissions.
//
// **Never touch what belongs to the user.** The state store is in memory, the diagnostic log points
// at a temporary directory, the notification sink records instead of delivering, and `start()` is
// never called — it raises a listener and a Bonjour registration, and the reader's own Mdoro is
// running.
@MainActor
private final class Harness {
    let store: InMemoryStateStore
    let notifications = RecordedNotifications()
    let model: AppModel
    private let directory: URL

    // **"A folder has been chosen", not "it works".** Nothing resolves this, so the sweep gets no
    // further than asking for access — which is the launch this file is about.
    static let unreachableFolder = Data("not a bookmark".utf8)

    init(logFolder: Data?, sweepFailures: LogTemporaryFile.FailureRun) {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MdoroSweepRun-\(UUID().uuidString)", isDirectory: true)
        let preset = Preset.standard()
        let settings = AppSettings()
        store = InMemoryStateStore(initial: PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            logSweepFailures: sweepFailures,
            savedAt: Date()
        ))
        model = AppModel(
            store: store,
            diagnostics: DiagnosticLog(directory: directory),
            bookmarks: VaultBookmarks(taskFile: nil, logFolder: logFolder),
            notifications: notifications,
            idleSleep: RecordedSleepGuard(),
            // Decision 0040: the Keychain is the reader's too. Nothing here pairs anything.
            deviceTokens: TokensKeptNowhere()
        )
    }

    // What a restart would read back. `AppModel` keeps the run to itself, and the state file is
    // where the next launch finds it, so this is the side that matters.
    var savedRun: LogTemporaryFile.FailureRun? { (try? store.load())?.logSweepFailures }

    var toldAboutTheSweep: Bool { notifications.calls.contains(.logSweepFailure) }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("A launch whose sweep never ran (Decision 0042)")
@MainActor
struct ASweepThatNeverRanTests {

    // Two launches have already failed. This one could not get to the folder at all, so it is not
    // the third — and it does not take the two away either.
    @Test func aFolderThatCannotBeReachedLeavesTheRunWhereItIs() {
        let harness = Harness(
            logFolder: Harness.unreachableFolder,
            sweepFailures: LogTemporaryFile.FailureRun(launches: 2)
        )
        defer { harness.cleanUp() }

        harness.model.removeLeftoverLogTemporaryFiles()

        #expect(harness.savedRun == LogTemporaryFile.FailureRun(launches: 2),
                "Decision 0042: a folder out of reach is neither a failed sweep nor a clean one")
        #expect(!harness.toldAboutTheSweep,
                "Decision 0042: the write that follows reports a folder gone away; this must not report it too")
    }

    // REQ-LOG-002 / Decision 0033: with nowhere chosen there is no folder of the reader's to tidy,
    // and nothing to say about one. The run stays as it was left.
    @Test func aFolderNobodyHasChosenIsNotASweepEither() {
        let harness = Harness(
            logFolder: nil,
            sweepFailures: LogTemporaryFile.FailureRun(launches: 2)
        )
        defer { harness.cleanUp() }

        harness.model.removeLeftoverLogTemporaryFiles()

        #expect(harness.savedRun == LogTemporaryFile.FailureRun(launches: 2))
        #expect(!harness.toldAboutTheSweep)
    }

    // The run a launch inherits is the one the last launch left, not zero. **This is the whole of
    // why it is in the state file**, and a restore that quietly dropped it would leave every test
    // above passing while the notification could never arrive.
    @Test func theRunIsWhereTheLastLaunchLeftIt() {
        let harness = Harness(
            logFolder: nil,
            sweepFailures: LogTemporaryFile.FailureRun(launches: 2, didNotify: false)
        )
        defer { harness.cleanUp() }

        // `AppModel.init` saves once, so what is in the store is what this launch is holding.
        #expect(harness.savedRun?.launches == 2, "REQ-PER-001: the run from the last launches is read back")
    }
}
