import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-CFG-018 / REQ-PER-002 / 9.3: what `AppModel` does with a settings record whose saved values
// are outside the ranges 9.3 sets.
//
// The ruling (2026-09-19) is: **check on the way in, put what does not hold up back to its default,
// and say so on screen.** The saying is the half that cannot be left out — the launch saves the
// repaired record over the file it read, so nothing anywhere keeps the value the reader chose, and
// one of the eight settings is half of the path the session log is written to (REQ-LOG-001).
//
// `MdoroCore` holds the rule and the repair (`SettingsAsReadTests` under `swift test`). What it
// cannot reach is this: that `AppModel` runs on the repaired record, that it carries the list to
// the screen, and that the diagnostic log gets the field keys and **not** what was in them
// (Decision 0018).
//
// **Never touch what belongs to the user.** The state store is in memory, the diagnostic log points
// at a temporary directory, the notification sink and the sleep guard are recorded rather than
// raised, and `start()` is never called — it raises a listener and a Bonjour registration, and the
// reader's own Mdoro is running.

private struct LoggedLine {
    let level: String
    let code: String
    let fields: [String: String]

    init?(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, !line.hasPrefix("#") else { return nil }
        level = parts[1]
        code = parts[2]
        fields = parts.dropFirst(3).reduce(into: [:]) { result, part in
            guard let separator = part.firstIndex(of: "=") else { return }
            result[String(part[part.startIndex..<separator])] = String(part[part.index(after: separator)...])
        }
    }
}

// A file name no version of this app would write, and distinctive enough to find anywhere in the
// log if it leaked. It fails 9.3 twice over — a leading dot and a path separator.
private let theReadersOwnBadFileName = ".Vault/UnmistakableProjectName.md"

@MainActor
private final class Harness {
    let store: InMemoryStateStore
    let notifications = RecordedNotifications()
    let model: AppModel
    private let directory: URL

    init(saved settings: AppSettings) {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MdoroSettingsReset-\(UUID().uuidString)", isDirectory: true)
        let preset = Preset.standard()
        store = InMemoryStateStore(initial: PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            savedAt: Date()
        ))
        let diagnostics = DiagnosticLog(directory: directory)
        model = AppModel(
            store: store,
            diagnostics: diagnostics,
            bookmarks: VaultBookmarks(taskFile: nil, logFolder: nil),
            notifications: notifications,
            idleSleep: RecordedSleepGuard(),
            // Decision 0040: the Keychain is the reader's too. Nothing here pairs anything.
            deviceTokens: TokensKeptNowhere()
        )
        // What `start()` does before anything else, with the settings this launch is actually
        // holding. The rest of `start()` is deliberately skipped.
        diagnostics.open(preset: preset, settings: model.settings)
    }

    // What a restart would read back. `init` saves, so this is the record the file now holds.
    var savedSettings: AppSettings? { (try? store.load())?.settings }

    var logText: String {
        (try? String(
            contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
            encoding: .utf8
        )) ?? ""
    }

    func lines(_ code: String) -> [LoggedLine] {
        logText.split(separator: "\n").compactMap { LoggedLine(String($0)) }.filter { $0.code == code }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("A saved setting read back outside its range (REQ-CFG-018 / 9.3)")
@MainActor
struct ASettingReadBackOutOfRangeTests {

    // The symptom the ruling was written about. `didSet` refuses a change the reader makes, and
    // property observers do not run during `init`, so this record used to go straight into
    // `settings` — and `logFilePath` would have handed a path with a directory in it to every write.
    @Test func theLaunchRunsOnTheRepairedRecordAndNotOnWhatTheFileHeld() {
        let harness = Harness(saved: AppSettings(
            logFolderPath: "/Users/someone/Vault/Logs",
            logFileName: theReadersOwnBadFileName
        ))
        defer { harness.cleanUp() }

        #expect(harness.model.settings.isWithinValidRanges(), "REQ-CFG-018: the launch is running out of range")
        #expect(harness.model.settings.logFileName == AppSettings.defaultLogFileName)
        #expect(harness.model.settingsResetAtLaunch == [.logFileName])
        // The half the reader picked through a panel is untouched. **Per field, not per record.**
        #expect(harness.model.settings.logFolderPath == "/Users/someone/Vault/Logs")
    }

    // More than one at a time, which is what a version with different ranges would leave behind.
    @Test func everyFieldThatDidNotHoldUpIsNamed() {
        let harness = Harness(saved: AppSettings(
            displayName: " ",
            logicalDayStartHour: 23,
            idleResetHours: 0,
            skipHotKey: HotKeyBinding(keyCode: 35, modifierFlags: 0, displayName: "P")
        ))
        defer { harness.cleanUp() }

        #expect(Set(harness.model.settingsResetAtLaunch)
                == [.displayName, .logicalDayStartHour, .idleResetHours, .skipHotKey])
        #expect(harness.model.settings.isWithinValidRanges())
    }

    // A record that holds up says nothing, or the band stands at every launch for nothing.
    @Test func aRecordThatHeldUpIsNotReported() {
        let harness = Harness(saved: AppSettings(
            logFolderPath: "/Users/someone/Vault/Logs",
            logFileName: "Sessions.md"
        ))
        defer { harness.cleanUp() }

        #expect(harness.model.settingsResetAtLaunch.isEmpty)
        #expect(harness.model.settings.logFileName == "Sessions.md", "a name that holds up is left alone")
    }

    // **Shown once at launch, and only the reader clears it** — the shape REQ-ERR-017 uses for a
    // failed restore. Nothing else may take it away: it has already happened, so there is no
    // condition for it to stop being true of.
    @Test func onlyTheReaderClearsTheNotice() {
        let harness = Harness(saved: AppSettings(logFileName: ""))
        defer { harness.cleanUp() }

        #expect(!harness.model.settingsResetAtLaunch.isEmpty)
        harness.model.acknowledgeSettingsResetAtLaunch()
        #expect(harness.model.settingsResetAtLaunch.isEmpty)
    }

    // **Why the notice is the only record.** `init` saves, so the repaired record lands on the file
    // and the value the reader chose is gone from it. If the list never reached the screen, there
    // would be nowhere left at all to learn that the log had moved.
    @Test func theRepairedRecordIsWhatTheFileNowHolds() {
        let harness = Harness(saved: AppSettings(logFileName: theReadersOwnBadFileName))
        defer { harness.cleanUp() }

        let saved = harness.savedSettings
        #expect(saved?.logFileName == AppSettings.defaultLogFileName)
        #expect(saved?.isWithinValidRanges() == true)
        #expect(saved?.logFileName != theReadersOwnBadFileName,
                "the value is gone from the file, so the screen is the only place it is reported")
    }

    // REQ-ERR-010 / Decision 0018: **which setting, and never what was in it.** A value the reader
    // had saved is their own file name or the name they gave this Mac, and this log is written to be
    // pasted into a public issue.
    @Test func theDiagnosticLogGetsTheFieldKeysAndNotTheValues() throws {
        let harness = Harness(saved: AppSettings(
            displayName: "  ",
            logFileName: theReadersOwnBadFileName
        ))
        defer { harness.cleanUp() }

        harness.model.writeStartupDiagnostics()

        let written = harness.lines("settings.reset")
        #expect(written.count == 1, "REQ-CFG-018: a record put back to its defaults with no line about it")
        let line = try #require(written.first)
        #expect(line.level == "WARN", "a value the reader chose is gone; that is not an info")
        #expect(line.fields["count"] == "2")
        let fields = try #require(line.fields["fields"])
        #expect(fields.contains("logFileName"))
        #expect(fields.contains("displayName"))

        // Decision 0018: the whole file, not just this line. The header is written from the same
        // settings, and it is the other place a file name could have got in.
        #expect(!harness.logText.contains("UnmistakableProjectName"),
                "Decision 0018: the reader's own file name reached the diagnostic log")
        #expect(!harness.logText.contains(".Vault"))
    }

    // The other direction. Without this, a line written at every launch would pass the test above.
    @Test func aRecordThatHeldUpWritesNoSuchLine() {
        let harness = Harness(saved: AppSettings(logFileName: "Sessions.md"))
        defer { harness.cleanUp() }

        harness.model.writeStartupDiagnostics()

        #expect(harness.lines("settings.reset").isEmpty)
    }
}
