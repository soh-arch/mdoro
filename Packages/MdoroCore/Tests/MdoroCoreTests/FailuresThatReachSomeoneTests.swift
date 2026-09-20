import Testing
import Foundation
@testable import MdoroCore

// The tools for reading the repository's own sources live in `RepositorySources.swift`.

private func temporaryDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroReachTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func discard(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
}

// A state file written by a newer build. Decodes cleanly, then fails the version guard —
// the shape the reproduction probe used.
private func stateFromTheFuture(pendingLogEntry: LogEntry? = nil) throws -> Data {
    var state = PersistedState.initial(now: Date(timeIntervalSince1970: 1_700_000_000))
    state.schemaVersion = 99
    if let pendingLogEntry { state.pendingLogEntries = [pendingLogEntry] }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(state)
}

private func sampleEntry() -> LogEntry {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return LogEntry(
        sessionType: .work, startedAt: start, endedAt: start.addingTimeInterval(1500),
        elapsedSeconds: 1500, outcome: .completed, presetName: "Standard",
        presetEditedDuringSession: false, taskSnapshot: "仕様書のレビュー", extendedSeconds: 0,
        loopCountAfterCompletion: 1, longBreakInterval: 4, logicalDate: start
    )
}

// Fails a read with whatever it was handed, and remembers whether the set-aside was asked
// for. Recording the question rather than its result is what lets the branch be checked in
// both directions: a store that refuses to move the file cannot tell "not asked" from "asked
// and failed".
private final class SpyStateStore: StateStore, @unchecked Sendable {
    let failure: StateStoreError
    private(set) var setAsideWasAsked = false

    init(failing failure: StateStoreError) { self.failure = failure }

    func load() throws -> PersistedState? { throw failure }
    func save(_ state: PersistedState) throws {}
    func setAsideUnreadableState() throws -> URL? {
        setAsideWasAsked = true
        return URL(fileURLWithPath: "/tmp/mdoro-tests/state.json.unreadable-19700101-000000")
    }
}

// A launch that ends with saving stopped: the read fails, and nothing can be moved out of
// the way (either because it must not be, or because the move itself failed).
private struct StoppedStateStore: StateStore {
    let readFailure: StateStoreError

    func load() throws -> PersistedState? { throw readFailure }
    func save(_ state: PersistedState) throws {}
    func setAsideUnreadableState() throws -> URL? {
        throw StateStoreError.couldNotSetAside(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
    }
}

// Refuses everything, the way a container that has gone missing would.
private struct RefusingStateStore: StateStore {
    func load() throws -> PersistedState? { throw StateStoreError.corrupted }
    func save(_ state: PersistedState) throws {
        throw StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
    }
}

@Suite("A failure needs somewhere to arrive (REQ-ERR-016 / 017 / REQ-ERR-010 / Decisions 0035, 0036)")
struct FailuresThatReachSomeoneTests {

    // MARK: - REQ-ERR-017 / Decision 0036: the unreadable file survives

    // The damage the audit measured: 19 bytes of the user's file became 1389 bytes of a clean
    // one, because a launch that restores first and saves afterwards writes over it. The order is
    // what prevents it, so the test runs the whole launch — read, set aside, then the save that
    // would otherwise land on top.
    @Test func anUnreadableStateFileIsSetAsideBeforeAnythingIsWrittenOverIt() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let original = try stateFromTheFuture(pendingLogEntry: sampleEntry())
        try original.write(to: fileURL)

        let store = FileStateStore(fileURL: fileURL)
        let startup = store.loadForStartup(now: Date())

        #expect(startup.readFailure == .unsupportedSchemaVersion(found: 99, supported: 1))
        #expect(startup.mayPersist, "the file is safe now, so the app carries on saving")
        let setAsideAt = try #require(startup.setAsideAt, "REQ-ERR-017: the file has to go somewhere")
        #expect(setAsideAt.lastPathComponent.hasPrefix("state.json.unreadable-"))

        // The save that would destroy it.
        try store.save(PersistedState.initial(now: Date()))

        #expect(try Data(contentsOf: setAsideAt) == original, "the user's bytes must survive intact")
        #expect(try Data(contentsOf: fileURL) != original, "the new state is a separate file")
        // REQ-LOG-005: what goes with it. It has to be recoverable from the file that was set
        // aside.
        let rescued = try #require(try? JSONDecoder.iso8601.decode(PersistedState.self, from: Data(contentsOf: setAsideAt)))
        #expect(rescued.pendingLogEntries.count == 1, "the unwritten log entry is still in the file")
    }

    // Decision 0036: **the timestamp is there because there is a second time.** A fixed name would
    // let the second breakage delete the first one's evidence, which is the thing being preserved.
    @Test func aSecondBreakageDoesNotEatTheFirstOnesEvidence() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let store = FileStateStore(fileURL: fileURL)

        var setAside: [URL] = []
        for marker in ["first", "second"] {
            try Data("not a state file at all: \(marker)".utf8).write(to: fileURL)
            let startup = store.loadForStartup(now: Date())
            #expect(startup.readFailure == .corrupted)
            setAside.append(try #require(startup.setAsideAt))
        }

        #expect(setAside[0] != setAside[1], "the second set-aside took the first one's name")
        #expect(try String(contentsOf: setAside[0], encoding: .utf8).contains("first"))
        #expect(try String(contentsOf: setAside[1], encoding: .utf8).contains("second"))
    }

    // Decision 0036: **never write over what could not be set aside.** Saving stops instead, and
    // says so.
    @Test func aFileThatCannotBeMovedIsNotWrittenOverEither() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let original = Data("not a state file at all".utf8)
        try original.write(to: fileURL)
        // Readable, but not movable. Only writing to the directory is closed off.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let startup = FileStateStore(fileURL: fileURL).loadForStartup(now: Date())

        #expect(startup.readFailure == .corrupted)
        guard case .couldNotSetAside = try #require(startup.setAsideFailure) else {
            Issue.record("expected couldNotSetAside, got \(String(describing: startup.setAsideFailure))")
            return
        }
        #expect(!startup.mayPersist, "REQ-ERR-017: nothing may be written over a file that could not be moved")
        #expect(try Data(contentsOf: fileURL) == original, "the file is left exactly as it was")

        // A sentence saying it was moved aside must not go out when nothing was moved aside.
        let shown = try #require(startup.displayMessage)
        #expect(shown == StateStoreError.couldNotSetAside(ErrorCode(own: 0)).displayMessage)
        #expect(shown != StateStoreError.corrupted.displayMessage)
    }

    // Decision 0036: **being unreadable and being broken are two different things.** Only a file
    // whose content cannot be interpreted is moved. A disk that did not answer says nothing about
    // the bytes, and moving that file pushes intact data off under another name.
    //
    // Both directions are covered, so inverting the branch fails here either way: the two
    // unusable-content cases must ask, and the I/O case must not.
    @Test func onlyAFileWhoseContentIsUnusableIsMovedAside() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for failure: StateStoreError in [.corrupted, .unsupportedSchemaVersion(found: 99, supported: 1)] {
            let store = SpyStateStore(failing: failure)
            let startup = store.loadForStartup(now: now)
            #expect(store.setAsideWasAsked, "\(failure) leaves an unreadable file where the next save lands")
            #expect(startup.setAsideAt != nil)
            #expect(startup.mayPersist, "the file is out of the way, so saving carries on")
            #expect(startup.persistBlockedBy == nil)
        }

        // A transient I/O failure. **Never push intact data off under another name.**
        let unreachable = SpyStateStore(failing: .ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 256)))
        let startup = unreachable.loadForStartup(now: now)
        #expect(!unreachable.setAsideWasAsked, "Decision 0036: a file that was merely unreachable is left alone")
        #expect(startup.setAsideAt == nil)
        #expect(startup.setAsideFailure == nil)

        // **Not setting it aside and being free to write over it are two different things.**
        #expect(!startup.mayPersist, "REQ-ERR-017: nothing may be written over it either")
        #expect(startup.persistBlockedBy == unreachable.failure, "the status line has to know why saving stopped")
        #expect(startup.displayMessage == unreachable.failure.displayMessage)
    }

    // Decision 0036: **the timestamp alone is not enough.** Two breakages inside one second want
    // the same name, and `moveItem` refuses an occupied one — which would stop saving for the
    // rest of the day over a name. The counter is what avoids that.
    //
    // Waiting for a real collision would make this test depend on which second it runs in, so
    // the collision is built: the name for the current second and the next two are taken
    // before the call, and whichever the store reaches for is already there.
    @Test func aSetAsideNeverTakesAnEarlierOnesName() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        try Data("the state that broke".utf8).write(to: fileURL)

        let now = Date()
        let occupied = try (0...2).map { offset -> URL in
            let stamp = FileStateStore.stampFormatter.string(from: now.addingTimeInterval(Double(offset)))
            let url = directory.appendingPathComponent("state.json.unreadable-\(stamp)")
            try Data("an earlier set-aside".utf8).write(to: url)
            return url
        }

        let startup = FileStateStore(fileURL: fileURL).loadForStartup(now: now)

        let setAsideAt = try #require(
            startup.setAsideAt,
            "the name was taken, so without the counter the move throws and saving stops"
        )
        #expect(setAsideAt.lastPathComponent.hasSuffix("-2"), "got \(setAsideAt.lastPathComponent)")
        #expect(!occupied.contains(setAsideAt))
        #expect(startup.mayPersist)
        for url in occupied {
            #expect(try String(contentsOf: url, encoding: .utf8) == "an earlier set-aside",
                    "an earlier set-aside was written over")
        }
        #expect(try String(contentsOf: setAsideAt, encoding: .utf8) == "the state that broke")
    }

    // MARK: - REQ-ERR-017: saving stops, and the status line says so

    // Three reasons can stand at once and they do not expire alike, so the order is fixed
    // where it can be run. The case that matters most is the quiet one: an `.ioFailed` read
    // sets nothing aside and lets no save run, so unless the reason that stopped it is passed
    // through, every candidate is nil and the status line has nothing to show.
    @Test func aStoppedSaveIsNeverSilentOnTheStatusLine() {
        let unavailable = StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        let blocked = StateStoreError.couldNotSetAside(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        let lastSave = StateStoreError.corrupted

        // With nothing wrong, it stays quiet.
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: nil, lastSaveFailure: nil) == nil)

        // Only the reason saving stopped is standing. **Return nil here and it leaves the screen.**
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: blocked, lastSaveFailure: nil
        ) == blocked.displayMessage)

        // What cannot be resolved comes first. A failure of the moment clears as soon as the next
        // write succeeds, so it comes last.
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: unavailable, persistBlockedBy: blocked, lastSaveFailure: lastSave
        ) == unavailable.displayMessage)
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: blocked, lastSaveFailure: lastSave
        ) == blocked.displayMessage)
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: nil, lastSaveFailure: lastSave
        ) == lastSave.displayMessage)

        // Read straight from the launch result. **On a launch where saving stops, not one of them
        // is silent.**
        let stopped: [StateStoreError] = [
            .ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 256)),
            .couldNotSetAside(ErrorCode(domain: NSCocoaErrorDomain, code: 513)),
        ]
        for failure in stopped {
            let startup = StoppedStateStore(readFailure: failure).loadForStartup(now: Date())
            #expect(!startup.mayPersist, "\(failure) has to stop saving")
            #expect(PersistenceStatus.problemMessage(
                storeUnavailable: nil,
                persistBlockedBy: startup.persistBlockedBy,
                lastSaveFailure: nil
            ) != nil, "REQ-ERR-017: saving is stopped and the status line says nothing")
        }
    }

    // The one line the test above cannot execute, because `stateSaveProblem` lives in the Mac
    // target: the model has to hand over every candidate. Dropping `persistBlockedBy` from the
    // call compiles and passes everything else, and the screen goes quiet exactly when saving
    // has stopped for good.
    @Test func theStatusLineIsWiredToEveryReasonSavingCanStop() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        let declaration = try #require(appModel.range(of: "var stateSaveProblem"))
        let rest = appModel[declaration.lowerBound...]
        let body = rest.range(of: "\n\n").map { String(rest[..<$0.lowerBound]) } ?? String(rest)

        for candidate in ["storeUnavailable", "persistBlockedBy", "lastSaveFailure"] {
            #expect(
                body.contains(candidate),
                "REQ-ERR-017: `\(candidate)` never reaches the status line — \(body)"
            )
        }
    }

    // Decision 0036 rewrote two of these, so the sentence and the behaviour are checked together:
    // what the screen claims happened to the file has to be what happened to it.
    @Test func theSentencesSayWhatBecameOfTheFile() {
        #expect(StateStoreError.corrupted.displayMessage.contains("moved the file aside"))
        #expect(StateStoreError.unsupportedSchemaVersion(found: 9, supported: 1)
            .displayMessage.contains("moved the file aside"))
        #expect(StateStoreError.couldNotSetAside(ErrorCode(own: 0))
            .displayMessage.contains("could not move the unreadable file aside"))
        // Nothing is moved on an I/O failure, so nothing may claim it was.
        let unreachable = StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 256))
        #expect(!unreachable.displayMessage.contains("moved the file aside"))
        #expect(!unreachable.displayMessage.contains("aside"))

        // The sentences of v2.14. **They said the opposite of what happens.**
        for failure in [StateStoreError.corrupted, .unsupportedSchemaVersion(found: 9, supported: 1)] {
            #expect(!failure.displayMessage.contains("left the file alone"))
            #expect(!failure.displayMessage.contains("move it aside"), "the user is not asked to do it by hand")
        }
    }

    // MARK: - REQ-ERR-017: the state store's failures get out at all

    // A store that cannot be read and a machine with nothing saved yet must not produce the
    // same answer — that equivalence is what `try?` created, and why it was a bug rather than
    // a shorthand. Both branches are checked, so breaking either one fails this.
    @Test func aStoreThatCannotBeReadIsNotAFirstRun() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Nothing saved is merely nothing saved: starting quietly from the initial state is fine.
        let firstRun = InMemoryStateStore().loadForStartup(now: now)
        #expect(firstRun.readFailure == nil)
        #expect(firstRun.displayMessage == nil, "a first run has nothing to say")
        #expect(firstRun.mayPersist)
        #expect(firstRun.reduction.context.runState == .idle)
        #expect(!firstRun.reduction.presets.presets.isEmpty, "a first run still has the built-in preset")
        #expect(firstRun.reduction.effects.isEmpty)

        // When it could not be read, it must not come back wearing the same face.
        let refused = RefusingStateStore().loadForStartup(now: now)
        #expect(refused.readFailure == .corrupted)
        #expect(refused.displayMessage != nil, "REQ-ERR-017: the failure has to have something to say")
        #expect(throws: StateStoreError.self) { try RefusingStateStore().loadAndRestore(now: now) }
    }

    // REQ-ERR-017: the call sites have to be shaped so the failure lands somewhere.
    // `AppModel` is in the Mac target and cannot be imported here, so this reads the source.
    // Decision 0035 named three lines; the fourth is the store that could not be made at all,
    // where every later save fails and nothing on screen would ever say so.
    @Test func theStateStoreIsNeverReadOrWrittenWithATryQuestionMark() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        for swallowed in ["try? store", "try? self.store", "try? FileStateStore"] {
            #expect(
                !appModel.contains(swallowed),
                "REQ-ERR-017: `\(swallowed)` drops a StateStoreError that has a screen waiting for it"
            )
        }
        // Decision 0036: the one step the tests above cannot execute, because saving happens
        // in the Mac target. The store-level behaviour is proved; this is the caller obeying it.
        #expect(
            appModel.contains("guard mayPersist"),
            "Decision 0036: persist() has to stand down when the unreadable file could not be moved"
        )
    }

    // MARK: - REQ-ERR-016 / 017: the sentences reach a reader

    // **Look at the use, not the declaration.** Deleting the display while leaving the property
    // assigned passed the whole suite before this test existed, on both platforms — the same
    // shape as the `lastError` hole Decision 0035 was written to close.
    //
    // **And look at every screen the clause names, not at "somewhere".** This asked whether any
    // file under each Views folder mentioned the reader, so one screen answered for a whole
    // platform: `MenuBarViews` held nothing and `FocusView` held nothing, and both clauses still
    // read as kept. Both were in fact empty — the menu is the one surface Decision 0037 added
    // REQ-ERR-017's sentence for, and the focus view is a `fullScreenCover` that covers the very
    // overlay `MainScreen` answers REQ-ERR-016 with.
    //
    // **And look at the call, not only the declaration.** Reading whole files let a member be
    // written out in full and never used: `refusalNotice(` declared on the focus view and left
    // out of the layout, `stateNotices` declared and cut from the menu. Every property above is
    // still written down in that case, so every clause still read as kept, while nothing put a
    // sentence on the screen. The second table below asks for the call.
    //
    // **What this keeps**: the named file reads the named property, so the value has a route to
    // that screen; the member that carries the notice is called rather than only declared; and
    // moving or renaming the file fails rather than passing on an empty folder.
    // **What it cannot keep**: that the call is reached from `body` rather than from some other
    // member nothing calls, that the branch inside it ever runs (a notice wrapped in `if false`
    // still counts), that the state it reads is ever assigned, that the timer which takes it
    // away again is still there, that the wording is right, or that the notice is laid out where
    // it can be seen. Those want a running app.
    @Test func everyScreenTheFailureMustReachActuallyReadsIt() throws {
        // REQ-ERR-017 / Decision 0037: the window's band **and** the menu. The set-aside path
        // (Decision 0036) and the dismissal are asked of the window alone, on purpose: the menu
        // carries the fact and opens the window for the rest.
        let macScreens = [
            "MainWindowView.swift": [
                "model.stateRestoreProblem", "model.stateSaveProblem", "model.stateSetAsidePath",
                // "Once at startup" means the user can dismiss it, so the means has to be there too.
                "acknowledgeStateRestoreProblem",
            ],
            "MenuBarViews.swift": ["model.stateRestoreProblem", "model.stateSaveProblem"],
        ]
        // REQ-ERR-016: wherever the user was standing when the tap was refused.
        let iosScreens = [
            "MainScreen.swift": ["model.lastRefusal", "RefusalNotice("],
            // The focus view keeps its own notice rather than `RefusalNotice`: REQ-UIX-010 allows
            // no coloured ground here and wants it gone in a few seconds, so only the route in is
            // pinned.
            "FocusView.swift": ["model.lastRefusal"],
        ]

        let folders = [
            ("REQ-ERR-017", "PomodoroMac/PomodoroMac/Views", macScreens),
            ("REQ-ERR-016", "PomodoroMac/PomodoroiOS/Views", iosScreens),
        ]
        for (clause, folder, screens) in folders {
            let views = try swiftFiles(under: folder)
            for (name, readers) in screens.sorted(by: { $0.key < $1.key }) {
                let text = try #require(
                    views[name],
                    "\(clause): \(folder)/\(name) is gone — the screen it answered for now has nothing"
                )
                for reader in readers {
                    #expect(
                        text.contains(reader),
                        "\(clause): \(name) does not read `\(reader)` — the failure never reaches that screen"
                    )
                }
            }
        }

        // REQ-ERR-016 / REQ-ERR-017: the member that carries the notice has to be called.
        // A declaration is the one place a name can sit with nothing using it, so it is blanked
        // out and the name has to survive the blanking. A type's name written with `(` is a call
        // already — `struct StateRestoreBanner: View` cannot match `StateRestoreBanner(`.
        // body → `content` → `StateRestoreBanner` → the dismissal, and body → `statusBar` →
        // the failed save. Each link is asked for; the chain is not walked.
        let macMembers = [
            "MainWindowView.swift": ["content", "statusBar", "StateRestoreBanner("],
            "MenuBarViews.swift": ["stateNotices"],
        ]
        // `MainScreen` builds its notice in `body` itself, so `RefusalNotice(` above is already
        // the call. The focus view holds both halves in members of its own: the one that draws
        // the band, and the one `.onChange` hands the refusal to.
        let iosMembers = [
            "FocusView.swift": ["refusalNotice(", "showRefusal("],
        ]

        let calls = [
            ("REQ-ERR-017", "PomodoroMac/PomodoroMac/Views", macMembers),
            ("REQ-ERR-016", "PomodoroMac/PomodoroiOS/Views", iosMembers),
        ]
        for (clause, folder, screens) in calls {
            let views = try swiftFiles(under: folder)
            for (name, members) in screens.sorted(by: { $0.key < $1.key }) {
                let text = try #require(
                    views[name],
                    "\(clause): \(folder)/\(name) is gone — the screen it answered for now has nothing"
                )
                for member in members {
                    let withoutDeclaration = text
                        .replacingOccurrences(of: "var \(member)", with: "var <declared>")
                        .replacingOccurrences(of: "func \(member)", with: "func <declared>")
                    #expect(
                        withoutDeclaration.contains(member),
                        "\(clause): \(name) declares `\(member)` and never calls it — the notice is written but not shown"
                    )
                }
            }
        }
    }

    // MARK: - REQ-ERR-016: what the iPhone is allowed to keep

    // 10.2 lists the codes the Mac can send. The receiver owns the wording, so every one of
    // them needs a sentence — including the codes no view reaches today, because the next one
    // to be sent must not arrive mute.
    @Test func everyRefusalTheMacCanSendHasSomethingToSay() {
        var seen = Set<String>()
        for code in ProtocolErrorCode.allCases {
            let message = code.displayMessage
            let isEnglishOnly = message.allSatisfy(\.isASCII)
            let showsACode = message.contains(where: \.isNumber)
            #expect(!message.isEmpty, "\(code) has nothing to say")
            #expect(isEnglishOnly, "REQ-UIX-038: the app's own strings are English only")
            #expect(message.hasSuffix("."))
            #expect(!showsACode, "Decision 0035 allows a code on one screen only, and this is not it: \(code)")
            #expect(seen.insert(message).inserted, "\(code) says what another code already said")
        }
    }

    // The switch behind `displayMessage` is exhaustive with no `default`, so a code added to
    // 10.2 fails to compile until someone writes its sentence. That is the guard; this fixes
    // the table it guards, because a `default` added later would make the test above pass
    // while every new code said the same thing.
    @Test func theCodeTableIsTheOneIn10point2() {
        let inTheSpec: Set<String> = [
            "invalidStateForAction", "extendWindowClosed", "presetLimitReached", "presetNameDuplicate",
            "presetNameInvalid", "cannotDeleteActivePreset", "cannotDeleteLastPreset", "presetNotFound",
            "settingOutOfRange", "invalidFilePath", "invalidPresetOrder", "taskFileUnavailable",
            "taskNotFound", "logWriteFailed", "protocolVersionMismatch",
        ]
        #expect(Set(ProtocolErrorCode.allCases.map(\.rawValue)) == inTheSpec)
        #expect(ProtocolErrorCode.allCases.count == inTheSpec.count, "the count has to match the list in 10.2")
    }

    // 10.2 / Decision 0035: `message` is diagnostic, and the sender does not choose the words
    // on the receiver's screen. The route is what gets checked, not a literal — no file in the
    // iPhone target may read the field at all, so nothing downstream has it to show. Comparing
    // two payloads that differ only in `message` proves nothing: `displayMessage` reads the
    // code, so it could not have come out any other way.
    @Test func theWireWordingHasNoRouteToTheiPhonesScreen() throws {
        for (name, text) in try swiftFiles(under: "PomodoroMac/PomodoroiOS", recursive: true) {
            // `Self.message(for:)` is wording the receiver owns. Calls to it pass straight through.
            let reads = text.replacingOccurrences(of: ".message(", with: ".ownWording(")
            #expect(!reads.contains(".message"), "10.2: \(name) reads the Mac's wording off the wire")
        }

        // Without also checking that there is exactly one intake, nothing guarantees the scan
        // above covers every route.
        let wiring = try swiftFiles(under: "PomodoroMac/PomodoroiOS", recursive: true)
            .filter { $0.value.contains("receivedError: {") }.keys.sorted()
        #expect(wiring == ["ClientModel.swift"], "the refusal is now taken in elsewhere too: \(wiring)")
    }

    // What the Mac actually puts in `message` is its own failure written as `case(domain:code)`
    // (Decision 0034). If a sentence on the iPhone ever contained one, the wording would have
    // crossed the wire after all.
    @Test func theSentenceOnScreenIsNeverTheWordTheMacSent() {
        var sent = TimerError.allCases.map(\.diagnosticSummary)
        sent += CommandTranslation.Parameter.allCases.flatMap {
            [
                CommandTranslation.Failure.missingParameter($0).diagnosticSummary,
                CommandTranslation.Failure.invalidParameter($0).diagnosticSummary,
                CommandTranslation.Failure.valueOutOfRange($0).diagnosticSummary,
            ]
        }
        for code in ProtocolErrorCode.allCases {
            let shown = code.displayMessage
            for sentAsMessage in sent {
                #expect(shown != sentAsMessage)
                #expect(!shown.contains(sentAsMessage), "the wire's wording survived into the screen: \(code)")
            }
        }
    }

    // Decision 0034: what `message` carries may change, and nothing on the iPhone moves with it.
    // The screen reads `code`, so pinning the route from a refusal to the code it is sent
    // under is what fails if the sentence someone sees changes; the summary is checked not
    // to appear in it, which is the only way the payload could leak through.
    @Test func rewritingTheWireMessageLeavesTheiPhonesSentenceWhereItWas() {
        let route: [TimerError: ProtocolErrorCode] = [
            .invalidStateForAction: .invalidStateForAction,
            .extendWindowClosed: .extendWindowClosed,
            .settingOutOfRange: .settingOutOfRange,
            .presetNotFound: .presetNotFound,
            .presetLimitReached: .presetLimitReached,
            .presetNameConflict: .presetNameDuplicate,
            .cannotDeleteLastPreset: .cannotDeleteLastPreset,
            .cannotDeleteActivePreset: .cannotDeleteActivePreset,
            .taskNotFound: .taskNotFound,
        ]
        #expect(route.count == TimerError.allCases.count, "a refusal has appeared with no route to a code")
        for error in TimerError.allCases {
            #expect(ProtocolErrorCode(error) == route[error], "\(error) now reaches a different sentence")
        }
        // A malformed command keeps its own code as well — `protocolErrorCode`, not the one
        // Decision 0034 added, which is the mix-up the two names exist to prevent.
        for parameter in CommandTranslation.Parameter.allCases {
            for failure in [
                CommandTranslation.Failure.missingParameter(parameter),
                CommandTranslation.Failure.invalidParameter(parameter),
            ] {
                #expect(failure.protocolErrorCode == .invalidStateForAction)
                #expect(!failure.protocolErrorCode.displayMessage.contains(failure.diagnosticSummary))
            }
            // REQ-CFG-018: a value that cannot be read reaches the sentence a value outside its
            // range reaches, not the one a malformed command reaches.
            let unreadable = CommandTranslation.Failure.valueOutOfRange(parameter)
            #expect(unreadable.protocolErrorCode == .settingOutOfRange)
            #expect(!unreadable.protocolErrorCode.displayMessage.contains(unreadable.diagnosticSummary))
        }
    }

    // Three refusals the Mac raises before the state machine sees the command — no `stableId`,
    // a task that is gone, no `settings` — were the last ones sent as a sentence. `AppModel`
    // is in the Mac target, so its source is what says whether any prose is left.
    //
    // **Look at the shape, not the declaration.** Checking only that the three sentences are gone
    // would pass again the moment someone writes a fourth, so every payload the file builds is
    // held to `case(domain:code)` instead.
    @Test func theRefusalsTheMacRaisesItselfCarryACodeAndNoSentence() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        for prose in ["No stableId", "That task no longer exists", "No settings"] {
            #expect(!appModel.contains(prose), "10.2: `\(prose)` still goes out as `error.message`")
        }
        let payloads = appModel.components(separatedBy: "ProtocolErrorPayload(").dropFirst()
        #expect(!payloads.isEmpty, "nothing here builds an error payload any more")
        for payload in payloads {
            #expect(
                payload.prefix(200).contains("diagnosticSummary"),
                "Decision 0034: an `error.message` written in a shape of its own"
            )
        }

        // 10.2 / Decision 0035: **the iPhone's screen looks it up from `code`.** Each of the three
        // keeps the code it was already sent under, so the sentence a reader sees does not move.
        #expect(CommandTranslation.Failure.missingParameter(.stableId)
            .protocolErrorCode == .invalidStateForAction)
        #expect(CommandTranslation.Failure.missingParameter(.settings)
            .protocolErrorCode == .invalidStateForAction)
        #expect(ProtocolErrorCode(TimerError.taskNotFound) == .taskNotFound)
        #expect(
            ProtocolErrorCode.invalidStateForAction.displayMessage
                == "Your Mac did not accept that. The timer is not in a state where it applies."
        )
        #expect(
            ProtocolErrorCode.taskNotFound.displayMessage
                == "That task is no longer in the list. Reload the tasks and pick it again."
        )
    }

    // REQ-ERR-010 / Decision 0034 / 0035: no refusal in `MdoroServer` goes out as prose. A
    // sentence put into `authFailed.message` reaches no screen — the iPhone takes `code` and
    // keeps its own wording, exactly as it does for `error` (10.2 / Decision 0035) — so it
    // reaches nobody, in a shape nothing else in the app uses.
    //
    // The payload has no parameter for a sentence any more, so the compiler holds this for
    // anyone who builds. That is not everyone: `swift test` cannot compile the Mac target,
    // and the parameter could come back. **Look at the shape, not the declaration** — every
    // payload the file builds is read, not just the six sentences that were there.
    @Test func theRefusalsTheServerSendsCarryACodeAndNoSentence() throws {
        let server = withoutComments(try source("PomodoroMac/PomodoroMac/Server/MdoroServer.swift"))
        for prose in [
            "Wrong pairing code", "Start pairing on the Mac", "Pairing ended after five wrong codes",
            "This device is not registered", "Another device is connected",
            "The connection was not approved",
        ] {
            #expect(!server.contains(prose), "10.2: `\(prose)` still goes out as `authFailed.message`")
        }
        let payloads = server.components(separatedBy: "AuthFailedPayload(").dropFirst()
        #expect(!payloads.isEmpty, "nothing here refuses a connection any more")
        for payload in payloads {
            #expect(
                !payload.prefix(200).contains("message:"),
                "Decision 0034: an `authFailed.message` written in a shape of its own"
            )
        }

        // 10.2 / Decision 0035: the sentence the iPhone shows comes from the code, so none of
        // this moved what a reader sees. `ConnectionViews` still owns the wording.
        #expect(AuthFailedPayload(code: .invalidPairingCode).code == .invalidPairingCode)
        #expect(
            AuthFailedPayload(code: .invalidPairingCode).message
                == AuthFailureCode.invalidPairingCode.diagnosticSummary
        )
        let views = try source("PomodoroMac/PomodoroiOS/Views/ConnectionViews.swift")
        for code in AuthFailureCode.allCases {
            #expect(views.contains("case .\(code.rawValue):"), "the iPhone has nothing to say for \(code)")
        }
    }

    // The refusal reaches the iPhone, and it has to reach the log too. **No clause asks for that
    // line** — the reader Decision 0018 wrote the log for is the whole of why it exists. "It will
    // not pair" is the report; five wrong codes, a pairing window that has closed and a token this
    // Mac does not know otherwise leave the same silence in the log that reader pastes into an
    // issue.
    //
    // **A line that has to be remembered is a line that gets forgotten**, so the record and the
    // send are one call, and this holds it that way: every `AuthFailedPayload` the file builds
    // has to be inside `refuse`. `MdoroMacTests` reads what comes out; this reads whether every
    // path goes through it, and it runs in CI, which that target does not.
    @Test func everyRefusalTheServerSendsIsWrittenDownFirst() throws {
        let server = withoutComments(try source("PomodoroMac/PomodoroMac/Server/MdoroServer.swift"))
        let beforeEachPayload = server.components(separatedBy: "AuthFailedPayload(").dropLast()
        #expect(!beforeEachPayload.isEmpty, "nothing here refuses a connection any more")
        for text in beforeEachPayload {
            let enclosingFunction = text.components(separatedBy: "func ").last ?? ""
            #expect(
                enclosingFunction.hasPrefix("refuse("),
                "a refusal is sent from somewhere other than `refuse`, so it is never written down"
            )
        }
        // And `refuse` writes one. Both halves, because either alone passes with the other gone.
        let refuseBody = try #require(server.components(separatedBy: "func refuse(").last)
        #expect(
            refuseBody.prefix(300).contains("record(refusal:"),
            "`refuse` no longer records anything, so every refusal is silent again"
        )
        let recordBody = try #require(server.components(separatedBy: "func record(refusal").last)
        #expect(
            recordBody.prefix(300).contains("conn.refused"),
            "the refusal no longer reaches the diagnostic log"
        )
        // Decision 0018: the code, never the name of the device that was turned away.
        #expect(
            !recordBody.prefix(300).contains("deviceName"),
            "Decision 0018: the refused device's name is being written to the diagnostic log"
        )
    }

    // MARK: - REQ-ERR-010: the diagnostic log's own write

    // The one code that goes on a screen. It cannot go to the log — the log is what failed —
    // so the settings screen is the only place left, and it still must not carry the OS's words.
    @Test func theDiagnosticLogsOwnFailureIsKeptAsACode() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let file = DiagnosticLogFile(
            directory: directory,
            header: DiagnosticHeader(
                appVersion: "1.0", build: "1", osVersion: "macOS 26.0", architecture: "arm64", settings: []
            )
        )
        file.write(DiagnosticEvent(code: "probe"))

        let failure = try #require(file.lastFailure, "the file system must actually refuse, or this proves nothing")
        #expect(failure.domain == NSCocoaErrorDomain)
        #expect(failure.code == NSFileWriteNoPermissionError)
        // REQ-ERR-010: what reaches the settings screen is `domain:code` and nothing else.
        #expect(failure.description == "\(NSCocoaErrorDomain):\(NSFileWriteNoPermissionError)")
        #expect(!failure.description.contains(directory.path), "REQ-ERR-010: no file paths")
        #expect(!failure.description.contains(DiagnosticLogFormat.currentFileName), "REQ-ERR-010: no file names")
    }

    // MARK: - Decision 0034: the OS's own words reach no screen

    // Every file that has ever reached for them. Nothing in these files needs them: what
    // reaches a reader here is a code (the diagnostic log's own write, Decision 0035's one
    // exception) or a fixed English sentence. `AppModel` is on the list for the same rule at one
    // remove — a `String(describing:)` there spells our own error enums into `error.message`,
    // which holds no OS text but is a shape of its own, which Decision 0034 does not allow either.
    @Test func theWordsTheOSChoseReachNoScreen() throws {
        let files = [
            "Packages/MdoroCore/Sources/MdoroCore/Diagnostics/DiagnosticLogFile.swift",
            "PomodoroMac/PomodoroMac/AppModel.swift",
            "PomodoroMac/PomodoroMac/Views/SettingsView.swift",
            "PomodoroMac/PomodoroiOS/Client/LiveActivityController.swift",
            "PomodoroMac/PomodoroiOS/ClientModel.swift",
        ]
        for path in files {
            let text = try source(path)
            for leak in ["String(describing:", "localizedDescription"] {
                #expect(!text.contains(leak), "REQ-ERR-010 / Decision 0034: \(path) still carries `\(leak)`")
            }
        }
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
