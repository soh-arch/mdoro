import Testing
import Foundation
@testable import MdoroCore

// REQ-CFG-018 / REQ-PER-002 / 9.3: **the ranges 9.3 puts on a setting hold for a value read back
// from the file, not only for one the reader has just typed.**
//
// Before this, `isWithinValidRanges()` was asked on exactly two paths, and both of them were
// "the reader changed a setting" (`AppModel.onSettingsChanged` and the `updateSettings` command).
// The launch read asked nothing: `saved?.settings` went straight into the property. So a record
// written by an older version, or edited by hand in Application Support, was used exactly as it
// stood — and one of those values is half of the path the session log is written to
// (REQ-LOG-001 / `AppSettings.logFilePath`).
//
// **What these keep**: that the rule and the Bool cannot disagree, that every field the rule names
// can really be produced, that the repair leaves a record within range, that it touches nothing
// else, and that a file holding each kind of bad value is read as repaired. **What they cannot
// keep**: that the reader is told — that is `AppModel` and the two screens, and
// `ASettingReadBackOutOfRangeTests` in the Mac target.

private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroSettingsAsRead-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func discard(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// A binding with no modifier at all. 9.3 puts the same range on all four shortcuts.
private let bareKey = HotKeyBinding(keyCode: 35, modifierFlags: 0, displayName: "P")
private let realShortcut = HotKeyBinding(keyCode: 35, modifierFlags: 1 << 20, displayName: "⌘P")

// One saved record per field, each outside its range in that field **and in no other**.
//
// ⚠ **The dictionary is checked against `RangedField.allCases` below, not trusted.** A case added
// to the enum with no rule behind it would otherwise show up here as a field nobody ever builds a
// value for, and every test in this file would go on passing.
private let outOfRangeByField: [AppSettings.RangedField: AppSettings] = [
    // 9.3: 0–12.
    .logicalDayStartHour: AppSettings(logicalDayStartHour: 23),
    // 9.3: 1–48. Zero is the one an older version could most easily have written.
    .idleResetHours: AppSettings(idleResetHours: 0),
    // 9.3: one character or more, no path separator. A leading dot hides the file from the reader.
    .logFileName: AppSettings(logFileName: ".MdoroLog.md"),
    // 9.3: one character or more. Whitespace alone advertises a row nothing can read.
    .displayName: AppSettings(displayName: "   "),
    .pauseResumeHotKey: AppSettings(pauseResumeHotKey: bareKey),
    .showWindowHotKey: AppSettings(showWindowHotKey: bareKey),
    .startNextHotKey: AppSettings(startNextHotKey: bareKey),
    .skipHotKey: AppSettings(skipHotKey: bareKey),
]

@Suite("Settings read back from the file (REQ-CFG-018 / 9.3)")
struct SettingsAsReadTests {

    // MARK: - The rule and the Bool are one rule

    // **The Bool used to be the rule.** Splitting it into a list is what let the reading side name
    // the field it had to put back, and the risk of the split is the two drifting apart — a range
    // tightened in one and not the other. `isWithinValidRanges()` is written as this list being
    // empty, and this asks that of every record in the file.
    @Test func theBoolIsTheListBeingEmptyAndNotASecondCopyOfTheRules() {
        var records: [AppSettings] = [.default, AppSettings()]
        records.append(contentsOf: outOfRangeByField.values)
        // Several at once, and the boundaries of the two numeric ranges from both sides.
        records.append(AppSettings(logicalDayStartHour: 13, idleResetHours: 49, logFileName: ""))
        for hour in [-1, 0, 12, 13] { records.append(AppSettings(logicalDayStartHour: hour)) }
        for hours in [0, 1, 48, 49] { records.append(AppSettings(idleResetHours: hours)) }

        for record in records {
            #expect(
                record.isWithinValidRanges() == record.fieldsOutsideValidRanges().isEmpty,
                "REQ-CFG-018: the range answer and the field list disagree"
            )
        }
    }

    // 9.3's two numeric ranges are inclusive at both ends, and the field list is what says so now.
    @Test func theNumericRangesAreInclusiveAtBothEnds() {
        #expect(AppSettings(logicalDayStartHour: 0).fieldsOutsideValidRanges().isEmpty, "9.3: 0–12")
        #expect(AppSettings(logicalDayStartHour: 12).fieldsOutsideValidRanges().isEmpty, "9.3: 0–12")
        #expect(AppSettings(logicalDayStartHour: 13).fieldsOutsideValidRanges() == [.logicalDayStartHour])
        #expect(AppSettings(logicalDayStartHour: -1).fieldsOutsideValidRanges() == [.logicalDayStartHour])
        #expect(AppSettings(idleResetHours: 1).fieldsOutsideValidRanges().isEmpty, "9.3: 1–48")
        #expect(AppSettings(idleResetHours: 48).fieldsOutsideValidRanges().isEmpty, "9.3: 1–48")
        #expect(AppSettings(idleResetHours: 0).fieldsOutsideValidRanges() == [.idleResetHours])
        #expect(AppSettings(idleResetHours: 49).fieldsOutsideValidRanges() == [.idleResetHours])
    }

    // ⚠ **A case with no rule behind it is the way this whole file goes quiet.** `RangedField` is
    // what the repair switches on and what the screen lists, so a case nothing can ever produce
    // reads as a field that is always fine. This asks for a record that produces each case, and
    // that it produces **only** that case — a fixture that happened to be bad in two fields would
    // otherwise stand in for the one it was written for.
    @Test func everyFieldTheRuleNamesCanActuallyBeProduced() {
        #expect(
            Set(outOfRangeByField.keys) == Set(AppSettings.RangedField.allCases),
            "REQ-CFG-018 / 9.3: a RangedField case with no out-of-range record to show for it"
        )
        for field in AppSettings.RangedField.allCases {
            guard let record = outOfRangeByField[field] else {
                Issue.record("no out-of-range record for \(field)")
                continue
            }
            #expect(
                record.fieldsOutsideValidRanges() == [field],
                "9.3: \(field)'s record is out of range in \(record.fieldsOutsideValidRanges())"
            )
        }
    }

    // MARK: - The repair

    // **The reason the repair is per field.** The reader chose the task file and the log folder
    // through a picker, and 9.3 gives neither a range; taking the whole record for one bad number
    // would make them find both again, plus the appearance and every flag.
    @Test func onlyTheFieldsOutsideTheirRangeAreSetBack() {
        let saved = AppSettings(
            appearance: .dark,
            focusViewDimmed: true,
            displayName: "Studio",
            // The two numbers, both outside 9.3's ranges.
            logicalDayStartHour: 23,
            idleResetHours: 0,
            taskFilePath: "/Users/someone/Vault/Task.md",
            logFolderPath: "/Users/someone/Vault/Logs",
            logFileName: "Sessions.md",
            showCompletedTasks: true,
            logTaskAsLink: true,
            logDailySummary: true,
            menuBarDisplayMode: .timeOnly,
            pauseResumeHotKey: realShortcut,
            launchAtLogin: true
        )

        let asRead = saved.resettingFieldsOutsideValidRanges()

        #expect(asRead.reset == [.logicalDayStartHour, .idleResetHours])
        #expect(asRead.settings.logicalDayStartHour == 4, "9.3: the default")
        #expect(asRead.settings.idleResetHours == 12, "9.3: the default")
        // Everything 9.3 gives no range to is exactly as it was saved.
        #expect(asRead.settings.taskFilePath == saved.taskFilePath)
        #expect(asRead.settings.logFolderPath == saved.logFolderPath)
        #expect(asRead.settings.logFileName == "Sessions.md")
        #expect(asRead.settings.displayName == "Studio")
        #expect(asRead.settings.appearance == .dark)
        #expect(asRead.settings.focusViewDimmed)
        #expect(asRead.settings.showCompletedTasks)
        #expect(asRead.settings.logTaskAsLink)
        #expect(asRead.settings.logDailySummary)
        #expect(asRead.settings.menuBarDisplayMode == .timeOnly)
        #expect(asRead.settings.launchAtLogin)
        // A shortcut that does hold up keeps its assignment. Resetting all four would take away
        // three bindings to answer for one.
        #expect(asRead.settings.pauseResumeHotKey == realShortcut)
    }

    // **A repair that still does not hold up is a repair that changed nothing that mattered.** This
    // is the one property the whole design rests on: each rule reads one field, so putting that one
    // field back to a default that is itself within range has to be enough.
    @Test func whateverComesBackIsWithinRange() {
        var records: [AppSettings] = Array(outOfRangeByField.values)
        // Every field at once, which is the record a version with different ranges would leave.
        records.append(AppSettings(
            displayName: "",
            logicalDayStartHour: 99,
            idleResetHours: -5,
            logFileName: "logs/today.md",
            pauseResumeHotKey: bareKey,
            showWindowHotKey: bareKey,
            startNextHotKey: bareKey,
            skipHotKey: bareKey
        ))

        for record in records {
            let asRead = record.resettingFieldsOutsideValidRanges()
            #expect(asRead.settings.isWithinValidRanges(), "REQ-CFG-018: \(asRead.reset) came back still out of range")
            #expect(asRead.settings.fieldsOutsideValidRanges().isEmpty)
            #expect(!asRead.reset.isEmpty, "a record that was out of range reported nothing reset")
        }
    }

    // The eight together, so a switch that quietly skipped one would be caught. The arm in the
    // repair is exhaustive, so this is about the values it assigns, not about the cases existing.
    @Test func eachFieldIsSetBackToTheDefault9_3States() {
        let fallback = AppSettings.default
        for (field, record) in outOfRangeByField {
            let asRead = record.resettingFieldsOutsideValidRanges()
            #expect(asRead.reset == [field])
            switch field {
            case .logicalDayStartHour: #expect(asRead.settings.logicalDayStartHour == fallback.logicalDayStartHour)
            case .idleResetHours: #expect(asRead.settings.idleResetHours == fallback.idleResetHours)
            case .logFileName: #expect(asRead.settings.logFileName == AppSettings.defaultLogFileName)
            case .displayName: #expect(asRead.settings.displayName == AppSettings.defaultDisplayName)
            case .pauseResumeHotKey: #expect(asRead.settings.pauseResumeHotKey == nil, "9.3: unset by default")
            case .showWindowHotKey: #expect(asRead.settings.showWindowHotKey == nil, "9.3: unset by default")
            case .startNextHotKey: #expect(asRead.settings.startNextHotKey == nil, "9.3: unset by default")
            case .skipHotKey: #expect(asRead.settings.skipHotKey == nil, "9.3: unset by default")
            }
        }
    }

    // A record that holds up comes back untouched, and says nothing was reset. Without this, a
    // repair that reset a field on every launch would pass everything above.
    @Test func aRecordThatHoldsUpIsHandedBackAsItIs() {
        for record in [AppSettings.default, AppSettings(logicalDayStartHour: 0, idleResetHours: 48,
                                                        logFileName: "Sessions.md",
                                                        pauseResumeHotKey: realShortcut)] {
            let asRead = record.resettingFieldsOutsideValidRanges()
            #expect(asRead.reset.isEmpty)
            #expect(asRead.settings == record)
        }
    }

    // REQ-LOG-001: the field the ruling was written about. Empty, whitespace, a leading dot and a
    // path separator are what `isValidLogFileName` refuses, and each of them decides where — or
    // whether — a session is written.
    @Test func aLogFileNameTheChangePathRefusesIsRefusedAtLaunchToo() {
        for name in ["", "   ", ".MdoroLog.md", "logs/MdoroLog.md", "/MdoroLog.md", "../MdoroLog.md"] {
            let saved = AppSettings(logFolderPath: "/Users/someone/Vault/Logs", logFileName: name)
            #expect(!AppSettings.isValidLogFileName(name), "9.3: `\(name)` is not a file name")
            let asRead = saved.resettingFieldsOutsideValidRanges()
            #expect(asRead.reset == [.logFileName], "REQ-LOG-001: `\(name)` was taken as a file name")
            #expect(asRead.settings.logFileName == AppSettings.defaultLogFileName)
            // The folder is not the thing that failed, and it is the half the reader picked.
            #expect(asRead.settings.logFolderPath == "/Users/someone/Vault/Logs")
        }
    }

    // MARK: - The read at launch

    // **The whole point of the change, at the place the reading happens.** A store handing back a
    // record with bad values is what an older version or a hand edit leaves, and what comes out of
    // `loadForStartup` is what the app runs on.
    @Test func theLaunchReadRepairsWhatTheFileHeldAndSaysWhichFields() throws {
        let bad = AppSettings(
            displayName: " ",
            logicalDayStartHour: 23,
            taskFilePath: "/Users/someone/Vault/Task.md",
            logFileName: "",
            skipHotKey: bareKey
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryStateStore(initial: PersistedState(
            timer: .idle(now: now, settings: bad),
            presets: PresetContext.initial(),
            settings: bad,
            savedAt: now
        ))

        let startup = store.loadForStartup(now: now)

        #expect(startup.readFailure == nil, "an out-of-range value reads perfectly well")
        #expect(startup.setAsideAt == nil, "Decision 0036: the file is not broken, so it is not set aside")
        #expect(startup.mayPersist, "the repair is written back by the caller's own save")
        #expect(Set(startup.settingsReset) == [.logicalDayStartHour, .displayName, .logFileName, .skipHotKey])
        let read = try #require(startup.saved?.settings)
        #expect(read.isWithinValidRanges(), "REQ-CFG-018: the launch ran on a record out of range")
        #expect(read.logFileName == AppSettings.defaultLogFileName)
        #expect(read.logicalDayStartHour == 4)
        #expect(read.displayName == AppSettings.defaultDisplayName)
        #expect(read.skipHotKey == nil)
        #expect(read.taskFilePath == "/Users/someone/Vault/Task.md", "the path 9.3 gives no range keeps")
    }

    // A file that holds up must come back with nothing reported, or the band shows at every launch.
    @Test func aLaunchThatFoundNothingWrongSaysNothingWasReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let good = AppSettings(logFolderPath: "/Users/someone/Vault/Logs", logFileName: "Sessions.md")
        let store = InMemoryStateStore(initial: PersistedState(
            timer: .idle(now: now, settings: good),
            presets: PresetContext.initial(),
            settings: good,
            savedAt: now
        ))

        let startup = store.loadForStartup(now: now)

        #expect(startup.settingsReset.isEmpty)
        #expect(startup.saved?.settings == good)
    }

    // A first launch has no file, so there is nothing to have been out of range.
    @Test func aFirstLaunchHasNothingToPutBack() {
        let startup = InMemoryStateStore().loadForStartup(now: Date())
        #expect(startup.settingsReset.isEmpty)
        #expect(startup.saved == nil)
    }

    // A read that failed hands back no settings at all, so nothing is reported as reset either —
    // the sentence that belongs to that launch is REQ-ERR-017's, not this one's, and two bands
    // saying different things about the same file would be worse than one.
    @Test func aReadThatFailedReportsNoResetFields() {
        let startup = RefusingStore().loadForStartup(now: Date())
        #expect(startup.readFailure != nil)
        #expect(startup.settingsReset.isEmpty)
    }

    // **A real file, written and read back.** The values above are built in memory, which cannot
    // show that such a record survives the encoder and the decoder — and if the decode threw, the
    // file would be set aside (Decision 0036) and this whole path would never run. It does not
    // throw: an out-of-range number is a number.
    @Test func aFileOnDiskHoldingSuchValuesIsReadAsRepairedRatherThanSetAside() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let bad = AppSettings(
            logicalDayStartHour: 23,
            idleResetHours: 99,
            logFolderPath: "/Users/someone/Vault/Logs",
            logFileName: ".hidden.md",
            pauseResumeHotKey: bareKey
        )
        let written = PersistedState(
            timer: .idle(now: now, settings: bad),
            presets: PresetContext.initial(),
            settings: bad,
            savedAt: now
        )
        try JSONEncoder.iso8601.encode(written).write(to: fileURL)

        let store = FileStateStore(fileURL: fileURL)
        let startup = store.loadForStartup(now: now)

        #expect(startup.readFailure == nil, "an out-of-range value is not a file that cannot be read")
        #expect(startup.setAsideAt == nil, "Decision 0036: only content that cannot be understood is set aside")
        #expect(Set(startup.settingsReset) == [.logicalDayStartHour, .idleResetHours, .logFileName, .pauseResumeHotKey])

        let read = try #require(startup.saved?.settings)
        #expect(read.isWithinValidRanges())
        #expect(read.logFileName == AppSettings.defaultLogFileName)
        #expect(read.logFolderPath == "/Users/someone/Vault/Logs")

        // **The read writes nothing.** Decision 0036 keeps writing out of it; the repair reaches
        // the file through the caller's own save.
        let bytes = try Data(contentsOf: fileURL)
        let parsed = try JSONSerialization.jsonObject(with: bytes)
        let onDisk = try #require(parsed as? [String: Any])
        let settingsOnDisk = try #require(onDisk["settings"] as? [String: Any])
        #expect(settingsOnDisk["logFileName"] as? String == ".hidden.md", "the read altered the file")
    }
}

// A store whose read fails, so there are no saved settings to check.
private struct RefusingStore: StateStore {
    func load() throws -> PersistedState? { throw StateStoreError.corrupted }
    func save(_ state: PersistedState) throws {}
    func setAsideUnreadableState() throws -> URL? { nil }
}

// REQ-CFG-018 / 9.3: **the list has to arrive somewhere a reader is.** `swift test` cannot link the
// Mac app, so the route is read out of its source — the same route `FailuresThatReachSomeoneTests`
// takes for REQ-ERR-017, and for the same reason: a property that is assigned and displayed nowhere
// passes every other test in this repository while the screen stays empty.
//
// **What this keeps**: each named file reads the property, the member that carries the notice is
// called rather than only declared, the words come from `Format` rather than from MdoroCore
// (Decision 0022), and a file that moves or is renamed fails rather than passing on an empty
// folder. **What it cannot keep**: that the band is reached from `body`, that it is laid out where
// it can be seen, or that the wording is right. Those want a running app.
@Suite("The reader is told which settings were put back (REQ-CFG-018)")
struct SettingsResetReachesTheReaderTests {

    // The window carries the whole notice — which settings, what it means for the log, and the way
    // to dismiss. The menu carries the fact and opens the window for the rest, exactly as
    // Decision 0037 has it for a failed restore.
    @Test func bothMacScreensReadTheListAndTheWindowCanDismissIt() throws {
        let expected = [
            "MainWindowView.swift": [
                "model.settingsResetAtLaunch",
                // Declared and left out of the layout is the failure this asks about.
                "SettingsResetBanner(",
                // "Once at launch" means the reader can close it, so the means has to be there.
                "acknowledgeSettingsResetAtLaunch",
                // The list itself, in the words the settings window uses.
                "Format.settingLabels(",
            ],
            // Mdoro runs with the main window shut (Decision 0037), and the value the reader chose
            // is already gone from the file, so this line is the last place the fact can reach.
            "MenuBarViews.swift": ["model.settingsResetAtLaunch"],
        ]

        let files = try swiftFiles(under: "PomodoroMac/PomodoroMac/Views")
        for (name, tokens) in expected {
            let text = try #require(files[name], "\(name) moved or was renamed")
            for token in tokens {
                #expect(text.contains(token), "REQ-CFG-018: \(name) does not carry `\(token)`")
            }
        }
    }

    // Decision 0022: the cases belong to this package, the words to each platform. A sentence kept
    // here would have to be written again on every screen, and the copy that gets read would be the
    // one no catalogue can reach.
    @Test func theFieldsAreNamedByTheCoreAndWordedByTheMacApp() throws {
        let core = try source("Packages/MdoroCore/Sources/MdoroCore/TimerContext.swift")
        for word in ["Day start hour", "Idle reset hours", "Log file name", "Skip shortcut"] {
            #expect(!core.contains("\"\(word)\""), "Decision 0022: `\(word)` is a display string in this package")
        }
        let words = try source("PomodoroMac/PomodoroMac/Views/Theme.swift")
        #expect(words.contains("func settingLabel("), "the words for RangedField are nowhere")
        // One `String(localized:)` per case, so `StringCatalogTests` can find each one in the
        // catalogue. A name built by interpolation would be extracted as `%@` and checked by nothing.
        for field in AppSettings.RangedField.allCases {
            #expect(words.contains("case .\(field.rawValue): return String(localized: \""),
                    "Decision 0022: \(field.rawValue) has no wording, or builds its key at run time")
        }
    }
}
