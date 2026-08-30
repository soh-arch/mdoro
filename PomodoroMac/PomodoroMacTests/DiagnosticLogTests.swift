import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-ERR-010 / Decision 0018 / 0034: what `AppModel` actually writes to the diagnostic log.
//
// `MdoroCore` owns the format and holds it under `swift test`; what it cannot reach is the
// call sites, which live in this target. That gap was real — POL-034 found that
// `preset.notificationSound.diagnosticValue` could be changed back to `.rawValue` in two
// places and every test in the repository would still pass. So these read the file back
// rather than the fields handed in, which is the only version a reader on an issue sees.
//
// **Never touch what belongs to the user.** Empty bookmarks are handed in (nothing can be written
// to the vault or to the log), the diagnostic log points at a temporary directory, and the state
// is kept in memory. Left at their defaults, these tests write to the host app's real destinations.

// One event per line: `timestamp LEVEL code key=value ...`.
private struct LoggedEvent {
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

// Decision 0034: `case(domain:code)`, and nothing else is accepted.
private func hasDiagnosticShape(_ value: String) -> Bool {
    guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return false }
    let caseName = value[value.startIndex..<open]
    let inside = value[value.index(after: open)..<value.index(before: value.endIndex)]
    let parts = inside.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, !caseName.isEmpty else { return false }
    return caseName.allSatisfy(\.isLetter)
        && !parts[0].isEmpty && parts[0].allSatisfy { $0.isLetter || $0 == "." }
        && Int(parts[1]) != nil
}

private struct Recording {
    let directory: URL
    let text: String
    let events: [LoggedEvent]
    // POL-047: what the app asked the notification centre for, had one been there.
    let notifications: [RecordedNotifications.Call]

    func events(_ code: String) -> [LoggedEvent] { events.filter { $0.code == code } }
}

@MainActor
private func record(
    preset: Preset,
    settings: AppSettings = AppSettings(),
    _ body: (AppModel) -> Void
) throws -> Recording {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroMacDiagnostics-\(UUID().uuidString)", isDirectory: true)

    let saved = PersistedState(
        timer: .idle(now: Date(), settings: settings),
        presets: PresetContext(presets: [preset], activePresetId: preset.id),
        settings: settings,
        savedAt: Date()
    )
    // POL-047: the notification sink is swapped out too. **The real target is the user's own
    // Notification Centre.** What these tests read is the diagnostic log, not the notifications.
    let notifications = RecordedNotifications()
    let model = AppModel(
        store: InMemoryStateStore(initial: saved),
        diagnostics: DiagnosticLog(directory: directory),
        // Empty bookmarks. With no destination set, nothing is even queued (REQ-LOG-002 /
        // Decision 0033): the entry stops at `log.notRecorded` and never reaches the user's folder.
        bookmarks: VaultBookmarks(),
        notifications: notifications,
        // POL-053: every case below runs a session to its end, and RUNNING is where REQ-PER-006
        // tells the OS to keep the machine awake. `IdleSleepTests` is where that rule is checked.
        idleSleep: RecordedSleepGuard()
    )
    model.diagnostics.open(preset: preset, settings: settings)
    body(model)

    let text = try String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )
    // Clean up once it has been read. From here on, everything is judged against text.
    try? FileManager.default.removeItem(at: directory)
    return Recording(
        directory: directory,
        text: text,
        events: text.split(separator: "\n").compactMap { LoggedEvent(String($0)) },
        notifications: notifications.calls
    )
}

// Make one session that has finished. `send` puts `sessionEndAt` on the real clock, so the finish
// is caused by a `tick` that steps past it.
@MainActor
private func runOneSessionToItsEnd(_ model: AppModel, taskSnapshot: String) {
    model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: taskSnapshot))
    let endAt = model.timer.sessionEndAt ?? Date()
    model.tick(now: endAt.addingTimeInterval(1))
}

@Suite("What the Mac writes to the diagnostic log (REQ-ERR-010 / Decision 0018 / 0034)")
@MainActor
struct DiagnosticLogTests {

    // POL-047: this suite runs inside MdoroMac.app, so every notification it asked for was
    // delivered to the person at the machine — two at a time, once per case below. The
    // requests still have to be made, because what these tests read is the record the app
    // writes of having made them. Only the destination changed.
    @Test func theRequestsAreStillMadeAndNoneOfThemLeaveTheProcess() throws {
        var preset = Preset.standard()
        preset.notificationSound = .chime

        let recording = try record(preset: preset) { model in
            model.sendNotificationSoundTest(preset)
            runOneSessionToItsEnd(model, taskSnapshot: "task")
        }

        // The diagnostic log is written as it always was.
        #expect(recording.events("notify.test").count == 1)
        #expect(recording.events("notify.finished").count == 1)
        // And delivery stops right here.
        #expect(recording.notifications.contains(.soundTest(.chime)))
        #expect(recording.notifications.contains(.sessionFinished(.work)))
        #expect(recording.notifications.filter { $0 == .soundTest(.chime) }.count == 1)
    }

    // Decision 0018: the reader is a stranger on an issue, with no table saying what sound `chime`
    // is. Dropping the name for the raw value alone leaves a line that parses but cannot be read.
    @Test func aSoundIsWrittenWithTheNameTheSettingsScreenShows() throws {
        var preset = Preset.standard()
        preset.notificationSound = .chime

        let recording = try record(preset: preset) { model in
            model.sendNotificationSoundTest(preset)
            runOneSessionToItsEnd(model, taskSnapshot: "task")
        }

        let test = try #require(recording.events("notify.test").first)
        let finished = try #require(recording.events("notify.finished").first)
        // `chime` on its own is contained in `sound=chime(Glass)`, so look at the value itself.
        #expect(test.fields["sound"] == "chime(Glass)")
        #expect(finished.fields["sound"] == "chime(Glass)")
        #expect(test.fields["sound"] != NotificationSound.chime.rawValue)
        // The header at the top carries the same value (the environment header of Decision 0018).
        #expect(recording.text.contains("sound=chime(Glass)"))
    }

    // There are five sounds, and two of them have the same raw value as display name, so looking
    // at only one shows no difference.
    @Test func everySoundIsWrittenTheSameWay() throws {
        for sound in NotificationSound.allCases {
            var preset = Preset.standard()
            preset.notificationSound = sound
            let recording = try record(preset: preset) { $0.sendNotificationSoundTest(preset) }
            let test = try #require(recording.events("notify.test").first)
            #expect(test.fields["sound"] == sound.diagnosticValue)
        }
    }

    // Decision 0034: whoever threw the failure, `why` is `case(domain:code)`.
    @Test func everyReasonIsWrittenAsADomainAndACode() throws {
        let recording = try record(preset: Preset.standard()) { model in
            // Extending is not possible in IDLE. A rejected action is recorded.
            model.send(.extend)
            // Committing a session that has finished reveals there is nowhere to write it.
            runOneSessionToItsEnd(model, taskSnapshot: "task")
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "task"))
        }

        let reasons = recording.events.compactMap { $0.fields["why"] }.filter { $0 != "-" }
        #expect(!reasons.isEmpty, "not one line carries `why`, so this test checked nothing")
        for reason in reasons {
            #expect(hasDiagnosticShape(reason), "not `case(domain:code)`: \(reason)")
        }

        let rejected = try #require(recording.events("action.rejected").first)
        #expect(rejected.fields["why"] == TimerError.invalidStateForAction.diagnosticSummary)
        // REQ-LOG-002 / Decision 0033: the line for a session with nowhere to be written. It reads
        // `log.notRecorded` rather than `log.blocked` because nothing was blocked and nothing
        // failed — `UnsetLogDestinationTests` is where that distinction is held.
        let notRecorded = try #require(recording.events("log.notRecorded").first)
        #expect(notRecorded.fields["why"] == ErrorCode.logFolderNotSet.summary("noFolder"))
    }

    // REQ-ERR-010 / Decision 0018: **it is never put in, rather than masked on the way out.**
    // Hand in a task name, a path, a file name and a host name, then look at the whole file.
    @Test func nothingTheUserWroteReachesTheFile() throws {
        let taskName = "REVIEWTHEQUARTERLYPLAN"
        let vaultPath = "/Users/someone/Vault/UNIQUETASKFILE.md"
        let logFolder = "/Users/someone/Vault/UNIQUELOGFOLDER"
        let logFileName = "UNIQUELOGNAME.md"
        let presetName = "UNIQUEPRESETNAME"
        let hostName = ProcessInfo.processInfo.hostName

        var preset = Preset.standard()
        preset.name = presetName
        let settings = AppSettings(
            taskFilePath: vaultPath, logFolderPath: logFolder, logFileName: logFileName
        )

        let recording = try record(preset: preset, settings: settings) { model in
            runOneSessionToItsEnd(model, taskSnapshot: taskName)
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: taskName))
            model.reloadTasksFromDisk()
            // Make it emit the settings-changed line too. This is the path that writes `vault=`
            // and `logDir=`.
            model.settings.logicalDayStartHour = 5
            model.stop()
        }

        for secret in [taskName, vaultPath, logFolder, logFileName, presetName, hostName] {
            #expect(
                !recording.text.contains(secret),
                "REQ-ERR-010: `\(secret)` appears in the diagnostic log"
            )
        }
        // The path is never put in, but whether the same setting is still in use can be
        // followed (Decision 0018).
        #expect(recording.text.contains("vault=\(DiagnosticRedaction.digest(vaultPath))"))
        // The scan must not have been looking at an empty file.
        #expect(recording.events.count > 3, "too few lines, so the forbidden-word check above saw nothing")
    }

    // That a task is selected is recorded; which task it is, never.
    @Test func aSelectedTaskIsCountedNotNamed() throws {
        let recording = try record(preset: Preset.standard()) { model in
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "SOMETASKNAME"))
        }
        let action = try #require(recording.events("action").first)
        #expect(action.fields["task"] == "set")
        #expect(action.fields["do"] == "startWork")
    }
}
