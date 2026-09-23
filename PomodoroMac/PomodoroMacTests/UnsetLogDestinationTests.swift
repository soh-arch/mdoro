import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-LOG-002 / Decision 0033: what `AppModel` does with a session that finishes while no folder
// has been chosen for the session log.
//
// **This is the state every user is in on their first run**, and Decision 0033 says what it is
// not: nothing is written, nothing is queued, nothing is a failure, and the screen says so. Treat
// it as a failed write instead and the entry goes into the retry queue, the status line says
// writing has failed, and REQ-ERR-004 notifies on the third session — and because the queue is
// persisted it grows across restarts until a folder is chosen, at which point every session since
// installation pours into the file at once.
//
// `MdoroCore` holds the rule itself (`LogDestinationTests` under `swift test`). What it cannot
// reach is this wiring, which is where all three bugs were.
//
// **Never touch what belongs to the user.** The state store is in memory, the diagnostic log points
// at a temporary directory, the notification sink and the sleep guard are recorded rather than
// raised, and `start()` is never called — it raises a listener and a Bonjour registration, and
// the reader's own Mdoro is running.

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

@MainActor
private final class Harness {
    let store: InMemoryStateStore
    let notifications = RecordedNotifications()
    let model: AppModel
    private let directory: URL

    // A bookmark that resolves to nothing. **This is "a folder has been chosen", not "it works"**:
    // every write through it fails, which is exactly the case REQ-LOG-005 keeps a queue for.
    static let unreachableFolder = Data("not a bookmark".utf8)

    init(logFolder: Data?, saved: PersistedState? = nil) {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MdoroUnsetLog-\(UUID().uuidString)", isDirectory: true)
        let preset = Preset.standard()
        let settings = AppSettings()
        store = InMemoryStateStore(initial: saved ?? PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            savedAt: Date()
        ))
        let diagnostics = DiagnosticLog(directory: directory)
        model = AppModel(
            store: store,
            diagnostics: diagnostics,
            bookmarks: VaultBookmarks(taskFile: nil, logFolder: logFolder),
            notifications: notifications,
            idleSleep: RecordedSleepGuard(),
            // Decision 0040: the Keychain is the reader's too. Nothing here pairs anything.
            deviceTokens: TokensKeptNowhere()
        )
        // What `start()` does before anything else. The rest of `start()` is deliberately skipped.
        diagnostics.open(preset: preset, settings: settings)
    }

    // `send` puts `sessionEndAt` on the real clock, so the finish comes from a tick past it.
    //
    // REQ-TIM-043: WORK holds a minute's grace for extending and commits nothing until it runs out,
    // so the tick goes past the grace as well. That is the path with no action of the reader's on
    // it — `abort` would commit too, but it also takes the loop count back (REQ-TIM-036). It leaves
    // the timer in IDLE, ready for the next call.
    func runOneSessionToItsEnd(taskSnapshot: String = "task") {
        model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: taskSnapshot))
        let endAt = model.timer.sessionEndAt ?? Date()
        model.tick(now: endAt.addingTimeInterval(TimerEngine.extensionGraceSeconds + 1))
    }

    var savedEntries: [LogEntry] { (try? store.load())?.pendingLogEntries ?? [] }

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

@MainActor
private func entry(_ start: Date, task: String) -> LogEntry {
    LogEntry(
        sessionType: .work, startedAt: start, endedAt: start.addingTimeInterval(1500),
        elapsedSeconds: 1500, outcome: .completed, presetName: "Standard",
        presetEditedDuringSession: false, taskSnapshot: task, extendedSeconds: 0,
        loopCountAfterCompletion: 1, longBreakInterval: 4, logicalDate: start
    )
}

@Suite("A log folder nobody has chosen (REQ-LOG-002 / Decision 0033)")
@MainActor
struct UnsetLogDestinationTests {

    // (a) REQ-LOG-002: not written, and **not queued either**. The queue is persisted, so an entry
    // that gets in is still there after a restart and lands in the file whenever one is chosen.
    @Test func aSessionThatFinishesWithNoFolderSetIsNeitherWrittenNorQueued() {
        let harness = Harness(logFolder: nil)
        defer { harness.cleanUp() }

        for _ in 0 ..< 3 { harness.runOneSessionToItsEnd() }

        #expect(harness.model.logFolderNotSet, "REQ-LOG-002: and the screen reads this")
        #expect(harness.model.pendingLogCount == 0)
        #expect(harness.savedEntries.isEmpty, "REQ-PER-001: nothing was left in the state file either")
        #expect(harness.lines("log.write").isEmpty, "no write was attempted")
        #expect(harness.lines("log.notRecorded").count == 3, "the three sessions did happen")
    }

    // (b) Decision 0033: **unset is not a failure.** REQ-ERR-004 notified on the third session, so
    // a new user met "the session log could not be written" before they had set anything up.
    @Test func anUnsetFolderIsNeverReportedAsAFailedWrite() {
        let harness = Harness(logFolder: nil)
        defer { harness.cleanUp() }

        // More sessions than REQ-ERR-004's threshold of three.
        for _ in 0 ..< 5 { harness.runOneSessionToItsEnd() }

        #expect(!harness.model.logWriteFailed, "REQ-ERR-004: nothing was attempted, so nothing failed")
        #expect(harness.model.lastLogError == nil)
        #expect(!harness.notifications.calls.contains(.logWriteFailure),
                "REQ-ERR-004 / Decision 0033: the notification is for writes that failed")
        // Decision 0033 / 0018: a reader on an issue has to tell this apart from a failure, and the
        // level is the first thing they sort by.
        for line in harness.lines("log.notRecorded") {
            #expect(line.level == "INFO")
            #expect(line.fields["why"] == ErrorCode.logFolderNotSet.summary("noFolder"))
        }
    }

    // The timer is untouched by any of it (Decision 0033: "the timer works completely without a log").
    @Test func theSessionStillFinishesAndStillCounts() {
        let harness = Harness(logFolder: nil)
        defer { harness.cleanUp() }

        harness.runOneSessionToItsEnd()

        #expect(harness.model.timer.loopCount == 1, "REQ-TIM-030: the loop counted")
        // REQ-LOG-019 / Decision 0033: with nothing to write, the session is settled all the same.
        // Left unset, REQ-PER-003(d) asks on the next launch whether to record a session that has
        // nowhere to be recorded.
        #expect(harness.model.timer.committedAt != nil)
    }

    // (c) What reaches the reader on the day they finally choose a folder, if nothing stops it:
    // days of sessions, written at once, none of them asked for.
    @Test func choosingAFolderLaterWritesNothingFromBefore() {
        let before = Harness(logFolder: nil)
        defer { before.cleanUp() }
        for _ in 0 ..< 3 { before.runOneSessionToItsEnd() }

        // The same state file, reopened with a folder now set — which is all that choosing one
        // leaves behind for the next launch to act on.
        let after = Harness(logFolder: Harness.unreachableFolder, saved: try? before.store.load())
        defer { after.cleanUp() }
        after.model.flushLogQueue()

        #expect(!after.model.logFolderNotSet, "a folder is set now")
        #expect(after.model.pendingLogCount == 0, "there was nothing left over to pour in")
        #expect(after.lines("log.write").isEmpty, "not one write was attempted for a past session")
        #expect(!after.model.logWriteFailed)
    }

    // The state files that already exist. An earlier version queued these with nowhere to write
    // them; Decision 0033 says they were never meant to exist, so they go.
    @Test func aQueueLeftOverFromBeforeIsDroppedWhenNoFolderIsSet() throws {
        let taskName = "UNIQUETASKNAMEFROMTHEQUEUE"
        let settings = AppSettings()
        let preset = Preset.standard()
        let saved = PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            pendingLogEntries: [entry(Date(), task: taskName), entry(Date(), task: taskName)],
            savedAt: Date()
        )

        let harness = Harness(logFolder: nil, saved: saved)
        defer { harness.cleanUp() }
        harness.model.writeStartupDiagnostics()

        #expect(harness.model.pendingLogCount == 0)
        #expect(harness.savedEntries.isEmpty, "and the state file no longer carries them")
        let dropped = try #require(harness.lines("log.dropped").first)
        #expect(dropped.fields["count"] == "2", "dropping records is not done quietly")
        #expect(dropped.level == "WARN")
        // Decision 0018: the count, and nothing the user wrote.
        #expect(!harness.logText.contains(taskName))
    }

    // REQ-LOG-005, unchanged. A queue left over while a folder *was* set holds real write failures,
    // and `committedAt` is already set on those sessions: drop them and the record is gone for good.
    @Test func aQueueLeftOverFromARealFailureIsKeptAndRetried() {
        let settings = AppSettings()
        let preset = Preset.standard()
        let saved = PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            pendingLogEntries: [entry(Date(), task: "task"), entry(Date(), task: "task")],
            savedAt: Date()
        )

        let harness = Harness(logFolder: Harness.unreachableFolder, saved: saved)
        defer { harness.cleanUp() }
        harness.model.writeStartupDiagnostics()

        #expect(harness.model.pendingLogCount == 2, "REQ-LOG-005: they are still owed to the file")
        #expect(harness.savedEntries.count == 2)
        #expect(harness.lines("log.dropped").isEmpty, "nothing was dropped, so nothing is reported")

        // The retry REQ-LOG-005 asks for, and the failure REQ-ERR-004 asks to be told about.
        harness.model.flushLogQueue()
        #expect(harness.model.pendingLogCount == 2, "a failed retry leaves them queued")
        #expect(harness.model.logWriteFailed, "REQ-ERR-004: this one really did fail")
        #expect(harness.model.lastLogError != nil)
        #expect(!harness.lines("log.write").isEmpty, "and the attempt is in the log")
    }

    // The other direction for (a): with a folder set, an entry still reaches the queue. Without
    // this, a guard that refused every entry would pass every test above.
    @Test func aSessionThatFinishesWithAFolderSetIsStillQueued() {
        let harness = Harness(logFolder: Harness.unreachableFolder)
        defer { harness.cleanUp() }

        harness.runOneSessionToItsEnd()

        #expect(!harness.model.logFolderNotSet)
        #expect(harness.model.pendingLogCount == 1, "REQ-LOG-005: a failed write keeps its entry")
        #expect(harness.savedEntries.count == 1, "and it survives a restart")
        #expect(harness.lines("log.notRecorded").isEmpty, "this session was recorded; it just could not be written")
    }
}

// REQ-ERR-004 / Decision 0039. The other end of the same distinction: a folder **is** set, and
// reaching it fails. The bookmark does not resolve — the folder was deleted, renamed, or moved to
// a volume that is not mounted — so `VaultFileAccess.withAccess` throws and the write never reaches
// `LogWriteQueue.flush` at all.
//
// **That whole path has to be counted.** Leave it out and `logWriteFailed` is raised, so the screen
// says writing has failed, while the threshold it is supposed to be counted against never moves:
// the notification cannot arrive however long the folder stays gone. Decision 0039 asks that
// failures which never build a run still be heard; this one does not even build an attempt.
@Suite("A log folder that cannot be reached (REQ-ERR-004 / Decision 0039)")
@MainActor
struct UnreachableLogFolderTests {

    // Two sessions already owed to the file, so every flush below has something to attempt.
    private func savedQueue() -> PersistedState {
        let settings = AppSettings()
        let preset = Preset.standard()
        return PersistedState(
            timer: .idle(now: Date(), settings: settings),
            presets: PresetContext(presets: [preset], activePresetId: preset.id),
            settings: settings,
            pendingLogEntries: [entry(Date(), task: "task"), entry(Date(), task: "task")],
            savedAt: Date()
        )
    }

    @Test func threeFlushesThatCannotReachTheFolderNotifyExactlyOnce() {
        let harness = Harness(logFolder: Harness.unreachableFolder, saved: savedQueue())
        defer { harness.cleanUp() }

        for _ in 0 ..< 3 { harness.model.flushLogQueue() }

        #expect(harness.notifications.calls.count(where: { $0 == .logWriteFailure }) == 1,
                "REQ-ERR-004: three failed attempts are told about, and told about once")
        #expect(harness.model.logWriteFailed, "and the screen says so as well")
        #expect(harness.model.lastLogError != nil)
    }

    // The threshold is three, so two attempts are not enough. Without this, counting every attempt
    // as if it had already crossed would pass the test above.
    @Test func twoFlushesThatCannotReachTheFolderSayNothingYet() {
        let harness = Harness(logFolder: Harness.unreachableFolder, saved: savedQueue())
        defer { harness.cleanUp() }

        for _ in 0 ..< 2 { harness.model.flushLogQueue() }

        #expect(!harness.notifications.calls.contains(.logWriteFailure),
                "REQ-ERR-004: two failures are under the threshold")
    }

    // REQ-ERR-004 / REQ-ERR-010: each `log.write` line carries the counts the notification is
    // decided on, and whether that attempt told the user — so a pasted log tells "not reached yet"
    // apart from "reached, already told".
    @Test func eachFailedAttemptLogsTheCountsTheNotificationIsDecidedOn() {
        let harness = Harness(logFolder: Harness.unreachableFolder, saved: savedQueue())
        defer { harness.cleanUp() }

        for _ in 0 ..< 4 { harness.model.flushLogQueue() }

        let lines = harness.lines("log.write")
        #expect(lines.map { $0.fields["consecutiveFailures"] } == ["1", "2", "3", "4"])
        #expect(lines.map { $0.fields["recentFailures"] } == ["1", "2", "3", "4"])
        #expect(lines.map { $0.fields["notified"] } == ["no", "no", "yes", "no"],
                "REQ-ERR-004: told on the third, and not again while the trouble stands")
    }

    // REQ-LOG-005: nothing was written, so nothing may be dropped. `committedAt` is already set on
    // these sessions — lose them here and they are never written at all.
    @Test func nothingLeavesTheQueueWhenTheFolderCannotBeReached() {
        let harness = Harness(logFolder: Harness.unreachableFolder, saved: savedQueue())
        defer { harness.cleanUp() }

        for _ in 0 ..< 3 { harness.model.flushLogQueue() }

        #expect(harness.model.pendingLogCount == 2)
        #expect(harness.savedEntries.count == 2, "and they survive a restart")
    }

    // REQ-LOG-002 / Decision 0033: with no folder set, flushing repeatedly reports nothing — no
    // failure on the screen, no notification. Every user starts in this state.
    //
    // **What this cannot test, and why nothing can.** It does not show that the counting stays out
    // of the unset path, because the state that would tell the two apart does not exist: nothing an
    // unset destination owns ever reaches the queue. `bookmarks.logFolder` only ever goes from unset
    // to set (`setLogFolder` is its one writer), entries carried over from a state file are dropped
    // before the queue is built, and `LogWriteQueue.enqueue` refuses the rest. So unset implies an
    // empty queue, and an empty queue is nothing owed to the file — which `recordFailedAttempt`
    // already reads as no attempt at all, wherever it is called from. The first assertion below is
    // that implication, and it is what keeps REQ-ERR-004 away from here; the early return in
    // `flushLogQueue` is an economy, not the thing that enforces it.
    @Test func whileNoFolderIsSetNothingIsOwedToTheFileAndNothingIsReported() {
        let harness = Harness(logFolder: nil, saved: savedQueue())
        defer { harness.cleanUp() }

        for _ in 0 ..< 5 { harness.model.flushLogQueue() }

        #expect(harness.model.pendingLogCount == 0,
                "REQ-LOG-002 / Decision 0033: two entries were carried in, and an unset folder took none of them")
        #expect(!harness.model.logWriteFailed,
                "Decision 0033: unset is not a failed write, however often writing is tried")
        #expect(harness.model.lastLogError == nil)
        #expect(!harness.notifications.calls.contains(.logWriteFailure),
                "REQ-ERR-004 / Decision 0033: nothing was attempted, so nothing failed")
    }
}
