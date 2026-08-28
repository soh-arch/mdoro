import Testing
import Foundation
@testable import MdoroCore

// リポジトリのソースを読む道具は `RepositorySources.swift`。

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
    // one, because the launch restored first and saved afterwards. The order is the fix, so
    // the test runs the whole launch — read, set aside, then the save that used to land on top.
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

        // The save that used to destroy it.
        try store.save(PersistedState.initial(now: Date()))

        #expect(try Data(contentsOf: setAsideAt) == original, "the user's bytes must survive intact")
        #expect(try Data(contentsOf: fileURL) != original, "the new state is a separate file")
        // REQ-LOG-005: 巻き添えで消えていたもの。退避先から取り出せること。
        let rescued = try #require(try? JSONDecoder.iso8601.decode(PersistedState.self, from: Data(contentsOf: setAsideAt)))
        #expect(rescued.pendingLogEntries.count == 1, "the unwritten log entry is still in the file")
    }

    // Decision 0036: **日時を付けるのは、2度目があるからである。** A fixed name would let the
    // second breakage delete the first one's evidence, which is the thing being preserved.
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

    // Decision 0036: **退避できないまま上書きしない。** Saving stops instead, and says so.
    @Test func aFileThatCannotBeMovedIsNotWrittenOverEither() throws {
        let directory = try temporaryDirectory()
        defer { discard(directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        let original = Data("not a state file at all".utf8)
        try original.write(to: fileURL)
        // 読めるが、動かせない。ディレクトリへの書き込みだけを閉じる。
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let startup = FileStateStore(fileURL: fileURL).loadForStartup(now: Date())

        #expect(startup.readFailure == .corrupted)
        guard case .couldNotSetAside = try #require(startup.setAsideFailure) else {
            Issue.record("expected couldNotSetAside, got \(String(describing: startup.setAsideFailure))")
            return
        }
        #expect(!startup.mayPersist, "REQ-ERR-017: nothing may be written over a file that could not be moved")
        #expect(try Data(contentsOf: fileURL) == original, "the file is left exactly as it was")

        // 退避できていないのに「退避した」と書いてある文を出すわけにいかない。
        let shown = try #require(startup.displayMessage)
        #expect(shown == StateStoreError.couldNotSetAside(ErrorCode(own: 0)).displayMessage)
        #expect(shown != StateStoreError.corrupted.displayMessage)
    }

    // Decision 0036: **読めなかったことと、壊れていることは別である。** Only a file whose content
    // cannot be interpreted is moved. A disk that did not answer says nothing about the bytes,
    // and moving that file pushes intact data off under another name.
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

        // 一時的な I/O の失敗。**無事なデータを別名へ追いやらない。**
        let unreachable = SpyStateStore(failing: .ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 256)))
        let startup = unreachable.loadForStartup(now: now)
        #expect(!unreachable.setAsideWasAsked, "Decision 0036: a file that was merely unreachable is left alone")
        #expect(startup.setAsideAt == nil)
        #expect(startup.setAsideFailure == nil)

        // **退避しないことと、上書きしてよいことは別である。**
        #expect(!startup.mayPersist, "REQ-ERR-017: nothing may be written over it either")
        #expect(startup.persistBlockedBy == unreachable.failure, "the status line has to know why saving stopped")
        #expect(startup.displayMessage == unreachable.failure.displayMessage)
    }

    // Decision 0036: **日時だけでは足りない。** Two breakages inside one second want the same
    // name, and `moveItem` refuses an occupied one — which would stop saving for the rest of
    // the day over a name. The counter is what avoids that.
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

        // 何も起きていなければ黙る。
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: nil, lastSaveFailure: nil) == nil)

        // 止まっている理由だけが立っている状態。**ここで nil を返すと、画面から消える。**
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: blocked, lastSaveFailure: nil
        ) == blocked.displayMessage)

        // 解消しようのないものが先。都度の失敗は次に書けたら消えるので後ろ。
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: unavailable, persistBlockedBy: blocked, lastSaveFailure: lastSave
        ) == unavailable.displayMessage)
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: blocked, lastSaveFailure: lastSave
        ) == blocked.displayMessage)
        #expect(PersistenceStatus.problemMessage(
            storeUnavailable: nil, persistBlockedBy: nil, lastSaveFailure: lastSave
        ) == lastSave.displayMessage)

        // 起動の結果から直に引く。**保存が止まる起動で、黙るものが1つも無いこと。**
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

        // v2.14 の文。**事実と逆だった。**
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

        // 保存が無いだけなら、黙って初期状態から始めてよい。
        let firstRun = InMemoryStateStore().loadForStartup(now: now)
        #expect(firstRun.readFailure == nil)
        #expect(firstRun.displayMessage == nil, "a first run has nothing to say")
        #expect(firstRun.mayPersist)
        #expect(firstRun.reduction.context.runState == .idle)
        #expect(!firstRun.reduction.presets.presets.isEmpty, "a first run still has the built-in preset")
        #expect(firstRun.reduction.effects.isEmpty)

        // 読めなかったのなら、同じ顔で返してはならない。
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

    // **宣言ではなく使用を見る。** Deleting the display while leaving the property assigned
    // passed the whole suite before this test existed, on both platforms — the same shape as
    // the `lastError` hole Decision 0035 was written to close.
    @Test func theFailuresTheModelHoldsAreActuallyReadByAView() throws {
        let macViews = try swiftFiles(under: "PomodoroMac/PomodoroMac/Views")
        let iosViews = try swiftFiles(under: "PomodoroMac/PomodoroiOS/Views")

        for reader in ["model.stateRestoreProblem", "model.stateSaveProblem", "model.stateSetAsidePath"] {
            #expect(
                macViews.values.contains { $0.contains(reader) },
                "REQ-ERR-017: nothing on the Mac's screen reads `\(reader)` — it is held and never shown"
            )
        }
        // 起動時に1度、というのは「利用者が消せる」ということ。消す手段も画面にあること。
        #expect(
            macViews.values.contains { $0.contains("acknowledgeStateRestoreProblem") },
            "REQ-ERR-017: the band cannot be dismissed, so `once at startup` has no meaning"
        )
        for reader in ["model.lastRefusal", "RefusalNotice("] {
            #expect(
                iosViews.values.contains { $0.contains(reader) },
                "REQ-ERR-016: nothing on the iPhone's screen reads `\(reader)` — a refused tap stays silent"
            )
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
        #expect(ProtocolErrorCode.allCases.count == inTheSpec.count, "10.2 の一覧と数を揃える")
    }

    // 10.2 / Decision 0035: `message` is diagnostic, and the sender does not choose the words
    // on the receiver's screen. The route is what gets checked, not a literal — no file in the
    // iPhone target may read the field at all, so nothing downstream has it to show. Comparing
    // two payloads that differ only in `message` proves nothing: `displayMessage` reads the
    // code, so it could not have come out any other way.
    @Test func theWireWordingHasNoRouteToTheiPhonesScreen() throws {
        for (name, text) in try swiftFiles(under: "PomodoroMac/PomodoroiOS", recursive: true) {
            // `Self.message(for:)` は受け取る側が自分で持っている文言。呼び出しは素通しする。
            let reads = text.replacingOccurrences(of: ".message(", with: ".ownWording(")
            #expect(!reads.contains(".message"), "10.2: \(name) reads the Mac's wording off the wire")
        }

        // 受け口が1つであることまで確かめないと、上の走査が全経路を覆っている保証がない。
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

    // POL-042 changed what `message` carries, and nothing on the iPhone may move with it.
    // The screen reads `code`, so pinning the route from a refusal to the code it is sent
    // under is what fails if the sentence someone sees changes; the summary is checked not
    // to appear in it, which is the only way the new payload could have leaked through.
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
        }
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

    // Every place the pre-release audit found them. Nothing in these files needs them: what
    // reaches a reader here is a code (the diagnostic log's own write, Decision 0035's one
    // exception) or a fixed English sentence. `AppModel` joined the list with POL-042 — the
    // two `String(describing:)` it kept spelled our own error enums into `error.message`,
    // which held no OS text but was the last thing written in a shape of its own.
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
