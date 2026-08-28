import Testing
import Foundation
@testable import MdoroCore

// Tests/MdoroCoreTests/ から5つ上がリポジトリのルート。
private var repositoryRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url
}

private func source(_ path: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
}

// A directory the owner cannot write to. If the OS does not actually refuse,
// the test proves nothing, so it checks that it did.
private func unwritableDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroReachTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    return directory
}

private func discard(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
}

// Refuses everything, the way a container that has gone missing would.
private struct RefusingStateStore: StateStore {
    func load() throws -> PersistedState? { throw StateStoreError.corrupted }
    func save(_ state: PersistedState) throws {
        throw StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
    }
}

@Suite("A failure needs somewhere to arrive (REQ-ERR-016 / 017 / REQ-ERR-010 / Decision 0035)")
struct FailuresThatReachSomeoneTests {

    // MARK: - REQ-ERR-017: the state store

    // Why `try?` was the bug and not a shorthand. A store that cannot be read and a machine
    // with nothing saved yet produce the same value once the failure is dropped, so the app
    // cannot tell "your sessions and presets are gone" from "welcome, first run".
    @Test func aSwallowedReadIsIndistinguishableFromAFirstRun() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let swallowed = try? RefusingStateStore().loadAndRestore(now: now)
        #expect(swallowed == nil, "the failure has to be able to get out at all")

        // What `try?` leaves the caller with, next to what a genuinely empty store gives.
        let afterSwallowing = swallowed ?? StateRestoration.reduction(from: nil, now: now)
        let firstRun = StateRestoration.reduction(from: nil, now: now)
        #expect(afterSwallowing.context.runState == firstRun.context.runState)
        #expect(afterSwallowing.presets.presets.count == firstRun.presets.presets.count)
        #expect(afterSwallowing.effects.isEmpty && firstRun.effects.isEmpty)
    }

    // REQ-ERR-017: the call sites have to be shaped so the failure lands somewhere.
    // `AppModel` is in the Mac target and cannot be imported here, so this reads the source.
    // Decision 0035 named these three lines; the fourth is the store that could not be made
    // at all, where every later save fails and nothing on screen would ever say so.
    @Test func theStateStoreIsNeverReadOrWrittenWithATryQuestionMark() throws {
        let appModel = try source("PomodoroMac/PomodoroMac/AppModel.swift")
        for swallowed in ["try? store", "try? self.store", "try? FileStateStore"] {
            #expect(
                !appModel.contains(swallowed),
                "REQ-ERR-017: `\(swallowed)` drops a StateStoreError that has a screen waiting for it"
            )
        }
        // 復元は起動時に1度、保存は解消するまで。届き先が両方あること。
        #expect(appModel.contains("stateRestoreProblem"), "the restore failure has nowhere to arrive")
        #expect(appModel.contains("stateSaveProblem"), "the save failure has nowhere to arrive")
    }

    // The three sentences Decision 0035 found written and unreachable. They are what the two
    // screens above show, so they have to survive being read off the error itself.
    @Test func everyStateStoreFailureHasASentenceForTheScreen() {
        let failures: [StateStoreError] = [
            .corrupted,
            .unsupportedSchemaVersion(found: 9, supported: 1),
            .ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
        ]
        var seen = Set<String>()
        for failure in failures {
            let message = failure.displayMessage
            let isEnglishOnly = message.allSatisfy(\.isASCII)
            let showsACode = message.contains(where: \.isNumber)
            #expect(!message.isEmpty)
            #expect(isEnglishOnly, "REQ-UIX-038: the app's own strings are English only")
            #expect(!showsACode, "the screen never shows a code")
            #expect(seen.insert(message).inserted, "each case must say something of its own")
        }
    }

    // MARK: - REQ-ERR-010: the diagnostic log's own write

    // The one code that goes on a screen. It cannot go to the log — the log is what failed —
    // so the settings screen is the only place left, and it still must not carry the OS's words.
    @Test func theDiagnosticLogsOwnFailureIsKeptAsACode() throws {
        let directory = try unwritableDirectory()
        defer { discard(directory) }

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

    // MARK: - REQ-ERR-016: the refusal the iPhone receives

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

    // Decision 0035: the sender does not choose the words on the receiver's screen.
    // Two Macs saying different things about the same refusal reach the same sentence here.
    @Test func whatTheMacWroteInMessageChangesNothingOnScreen() {
        let terse = ProtocolErrorPayload(code: .taskNotFound, message: "taskNotFound")
        let chatty = ProtocolErrorPayload(code: .taskNotFound, message: "no such task in the current list")
        #expect(terse.code.displayMessage == chatty.code.displayMessage)
        #expect(terse.code.displayMessage != terse.message)
        #expect(terse.code.displayMessage != chatty.message)
    }

    // REQ-ERR-016: the payload has to reach a view at all. `lastError` was assigned and read
    // by nobody, which is the state Decision 0035 was written to end.
    @Test func theRefusalReachesAViewAndItsMessageDoesNot() throws {
        let clientModel = try source("PomodoroMac/PomodoroiOS/ClientModel.swift")
        #expect(clientModel.contains("lastRefusal"), "nothing holds the refusal")
        #expect(
            !clientModel.contains("$0.message"),
            "10.2: `message` is diagnostic — the iPhone must not carry the Mac's wording"
        )

        // `displayMessage` は MdoroCore が持つ（REQ-PRT-001）。読む側が1つはあること。
        let views = ["PomodoroMac/PomodoroiOS/Views/MainScreen.swift"]
        let readers = try views.filter { try source($0).contains("displayMessage") }
        #expect(!readers.isEmpty, "REQ-ERR-016: the refusal is held but never shown")
    }

    // MARK: - Decision 0034: the OS's own words reach no screen

    // Every place the pre-release audit found them. Nothing in these files needs them: what
    // reaches a reader here is a code (the diagnostic log's own write, Decision 0035's one
    // exception) or a fixed English sentence. `AppModel` is not on the list — the two
    // `String(describing:)` left there spell our own payload-free enums into `error.message`,
    // which 10.2 keeps as diagnostic and no screen reads.
    @Test func theWordsTheOSChoseReachNoScreen() throws {
        let files = [
            "Packages/MdoroCore/Sources/MdoroCore/Diagnostics/DiagnosticLogFile.swift",
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
