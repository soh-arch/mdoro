import Testing
import Foundation
@testable import MdoroCore

// A directory the owner cannot write to. If the OS does not actually refuse,
// the tests below prove nothing, so each one checks that it did.
private func unwritableDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroErrorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    return directory
}

private func discard(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
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

// Keeps only the kind of each character and collapses runs, so
// `writeFailed(NSCocoaErrorDomain:513)` and `invalidFilePath(Mdoro:1)` both become `a(a:9)`.
// Length must not give away where a failure came from either.
private func shape(of summary: String) -> String {
    var result = ""
    for character in summary {
        let symbol: Character = character.isLetter ? "a" : (character.isNumber ? "9" : character)
        if result.last != symbol { result.append(symbol) }
    }
    return result
}

// Accepts `case(domain:code)` and nothing else. Dots are allowed in the domain because
// some frameworks hand one over as a type name (`Network.NWError:48`).
private func hasDiagnosticShape(_ summary: String) -> Bool {
    guard let open = summary.firstIndex(of: "("), summary.hasSuffix(")") else { return false }
    let caseName = summary[summary.startIndex..<open]
    let inside = summary[summary.index(after: open)..<summary.index(before: summary.endIndex)]
    let parts = inside.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, !caseName.isEmpty else { return false }
    return caseName.allSatisfy(\.isLetter)
        && !parts[0].isEmpty && parts[0].allSatisfy { $0.isLetter || $0 == "." }
        && Int(parts[1]) != nil
}

private let everyFailure: [any DiagnosableError] = [
    LogWriteError.invalidFilePath,
    LogWriteError.wouldModifyExistingLines,
    LogWriteError.readFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)),
    LogWriteError.writeFailed(ErrorCode(domain: NSPOSIXErrorDomain, code: 28)),
    StateStoreError.corrupted,
    StateStoreError.unsupportedSchemaVersion(found: 9, supported: 1),
    StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
]

@Suite("OS errors are recorded as codes, not as their own words (REQ-ERR-010 / Decision 0034)")
struct ErrorReportingTests {

    // The point of the change: the words the OS chose survive nowhere.
    @Test func aRefusalFromTheFileSystemKeepsOnlyItsDomainAndCode() throws {
        let directory = try unwritableDirectory()
        defer { discard(directory) }
        let url = directory.appendingPathComponent("MdoroLog.md")

        // Take the same refusal bare first, so the OS's own words are at hand to compare against.
        var osWords = ""
        do {
            try Data("probe".utf8).write(to: url, options: .atomic)
        } catch {
            osWords = String(describing: error) + error.localizedDescription
        }
        try #require(!osWords.isEmpty, "the file system must actually refuse, or this test proves nothing")

        var thrown: LogWriteError?
        do {
            try LogWriter(fileURL: url).append(sampleEntry())
        } catch let error as LogWriteError {
            thrown = error
        }
        let error = try #require(thrown)
        guard case let .writeFailed(code) = error else {
            Issue.record("expected writeFailed, got \(error)")
            return
        }

        // Losing the words must not cost resolution: permission, space and absence stay distinct.
        #expect(code.domain == NSCocoaErrorDomain, "the OS domain must survive")
        #expect(code.code == NSFileWriteNoPermissionError, "the OS code must survive")
        #expect(error.diagnosticSummary == "writeFailed(NSCocoaErrorDomain:513)")

        // The payload has no room for a string at all. That is the guarantee, not a redaction pass.
        #expect(
            Mirror(reflecting: error).children.first?.value is ErrorCode,
            "Decision 0034: the payload is a domain and a code, so the OS's words have nowhere to go"
        )
        for produced in [error.diagnosticSummary, error.displayMessage, String(describing: error)] {
            #expect(!osWords.contains(produced), "nothing the app produces may be a slice of the OS text")
            #expect(!produced.contains(url.lastPathComponent), "REQ-ERR-010: no file names")
            #expect(!produced.contains(directory.path), "REQ-ERR-010: no file paths")
        }
    }

    // Persistence is held to the same rule as the session log.
    @Test func theStateStoreCarriesTheSameDomainAndCode() throws {
        let directory = try unwritableDirectory()
        defer { discard(directory) }
        let store = FileStateStore(fileURL: directory.appendingPathComponent("state.json"))

        var thrown: StateStoreError?
        do {
            try store.save(PersistedState.initial(now: Date()))
        } catch let error as StateStoreError {
            thrown = error
        }
        let error = try #require(thrown)
        guard case let .ioFailed(code) = error else {
            Issue.record("expected ioFailed, got \(error)")
            return
        }
        #expect(code.domain == NSCocoaErrorDomain)
        #expect(code.code == NSFileWriteNoPermissionError)
        #expect(error.diagnosticSummary == "ioFailed(NSCocoaErrorDomain:513)")
        #expect(Mirror(reflecting: error).children.first?.value is ErrorCode)
    }

    // Decision 0034: a reader of the diagnostic log must not be able to tell
    // an OS failure from one of ours by how it is written.
    @Test func ourOwnFailuresAreShapedExactlyLikeTheOnesFromTheOS() {
        let ours = LogWriteError.invalidFilePath
        let theirs = LogWriteError.writeFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))

        #expect(ours.errorCode.domain == ErrorCode.ownDomain, "our own failures carry a domain too")
        #expect(ours.diagnosticSummary == "invalidFilePath(Mdoro:1)")
        #expect(theirs.diagnosticSummary == "writeFailed(NSCocoaErrorDomain:513)")
        #expect(
            shape(of: ours.diagnosticSummary) == shape(of: theirs.diagnosticSummary),
            "a reader must not be able to tell where a failure came from by its shape"
        )
    }

    @Test func everyFailureIsWrittenAsCaseDomainAndCode() {
        for failure in everyFailure {
            #expect(
                hasDiagnosticShape(failure.diagnosticSummary),
                "not `case(domain:code)`: \(failure.diagnosticSummary)"
            )
            #expect(failure.diagnosticSummary.hasSuffix("(\(failure.errorCode))"))
        }
    }

    // Decision 0018 rewrites whitespace in a field, so the shape must contain none —
    // which the OS's own text always did.
    @Test func aSummaryReachesTheDiagnosticLogUnchanged() {
        for failure in everyFailure {
            #expect(
                DiagnosticField("why", failure.diagnosticSummary).value == failure.diagnosticSummary,
                "the log format must not have to rewrite \(failure.diagnosticSummary)"
            )
        }
        let refused = LogWriteError.writeFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        let line = DiagnosticLogFormat.line(DiagnosticEvent(
            code: "log.write", fields: [DiagnosticField("why", refused.diagnosticSummary)]
        ))
        #expect(line.hasSuffix("why=writeFailed(NSCocoaErrorDomain:513)"), "the example Decision 0034 gives")
    }

    // The screen answers a different question: what happened, and what to do next.
    // No domain, no code, and never a string that came from the OS.
    @Test func everyFailureAlsoHasItsOwnFixedEnglishSentence() {
        var seen = Set<String>()
        for failure in everyFailure {
            let message = failure.displayMessage
            let isEnglishOnly = message.allSatisfy(\.isASCII)
            let showsACode = message.contains(where: \.isNumber)
            #expect(!message.isEmpty)
            #expect(isEnglishOnly, "REQ-UIX-038: the app's own strings are English only")
            #expect(message.hasSuffix("."))
            #expect(!showsACode, "the screen never shows a code")
            #expect(seen.insert(message).inserted, "each case must say something of its own")
        }
    }

    // Numbers are handed out once, so a code pasted into an issue always means the same thing.
    @Test func everyCodeInOurOwnDomainMeansOneThing() {
        let table: [ErrorCode] = [
            .logInvalidFilePath, .logWouldModifyExistingLines, .logFolderNotSet,
            .stateCorrupted, .stateUnsupportedSchemaVersion,
            .notificationsNotAllowed,
            .bookmarkCreationFailed, .bookmarkResolutionFailed, .accessDenied,
        ]
        let allOurs = table.allSatisfy { $0.domain == ErrorCode.ownDomain }
        #expect(allOurs)
        #expect(Set(table.map(\.code)).count == table.count, "Decision 0034: a code means one thing")
    }

    // REQ-LOG-005: even a type nobody planned for lands as a domain and a code.
    @Test func anUnforeseenFailureStillArrivesAsADomainAndCode() {
        let queue = LogWriteQueue()
        queue.enqueue(sampleEntry())
        let result = queue.flush { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 28, userInfo: [NSFilePathErrorKey: "/Users/someone/Vault"])
        }
        guard case let .writeFailed(code)? = result.lastError else {
            Issue.record("expected writeFailed, got \(String(describing: result.lastError))")
            return
        }
        #expect(code == ErrorCode(domain: NSPOSIXErrorDomain, code: 28))
        #expect(!String(describing: result.lastError).contains("/Users/someone/Vault"))
    }
}
