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

private let everyFailure: [any ReportableError] = [
    LogWriteError.invalidFilePath,
    LogWriteError.wouldModifyExistingLines,
    LogWriteError.fileChangedWhileWriting,
    LogWriteError.readFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)),
    LogWriteError.writeFailed(ErrorCode(domain: NSPOSIXErrorDomain, code: 28)),
    StateStoreError.corrupted,
    StateStoreError.unsupportedSchemaVersion(found: 9, supported: 1),
    StateStoreError.ioFailed(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
    StateStoreError.couldNotSetAside(ErrorCode(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
]

@Suite("OS errors are recorded as codes, not as their own words (REQ-ERR-010 / Decision 0034)")
struct ErrorReportingTests {

    // The point of the change: the words the OS chose survive nowhere.
    //
    // Refuse the same write twice, in two folders the OS will name differently. Everything
    // the app produces has to come out identical, so nothing that varies with the file — a
    // path, a name, or anything built from one — can have got through. That is the leak
    // REQ-ERR-010 names, and it is as far as this comparison reaches: a constant slice of
    // the OS's wording, the same on both runs, would pass here. What rules that out is that
    // `ErrorCode` stores two fields and neither is a place to put one.
    //
    // Comparing the app's output against the OS text directly shows nothing either way: the
    // output is short and the OS's is long, so containment only runs in the trivially true
    // direction.
    @Test func aRefusalFromTheFileSystemKeepsOnlyItsDomainAndCode() throws {
        var refusals: [(error: LogWriteError, url: URL, directory: URL, osWords: String)] = []
        defer { refusals.forEach { discard($0.directory) } }

        for _ in 0..<2 {
            let directory = try unwritableDirectory()
            let url = directory.appendingPathComponent("MdoroLog.md")

            // Take the same refusal bare first, so the OS's own words are on record.
            var osWords = ""
            do {
                try Data("probe".utf8).write(to: url, options: .atomic)
            } catch {
                osWords = String(describing: error) + error.localizedDescription
            }
            try #require(!osWords.isEmpty, "the file system must actually refuse, or this proves nothing")

            var thrown: LogWriteError?
            do {
                try LogWriter(fileURL: url).append(sampleEntry())
            } catch let error as LogWriteError {
                thrown = error
            }
            refusals.append((try #require(thrown), url, directory, osWords))
        }

        let error = refusals[0].error
        guard case let .writeFailed(code) = error else {
            Issue.record("expected writeFailed, got \(error)")
            return
        }

        // Losing the words must not cost resolution: permission, space and absence stay distinct.
        #expect(code.domain == NSCocoaErrorDomain, "the OS domain must survive")
        #expect(code.code == NSFileWriteNoPermissionError, "the OS code must survive")
        #expect(error.diagnosticSummary == "writeFailed(NSCocoaErrorDomain:513)")
        #expect(
            Mirror(reflecting: error).children.first?.value is ErrorCode,
            "Decision 0034: `init(_ error:)` reads only the domain and the code, so that is all this holds"
        )

        // Two different folders, so the OS had two different things to say.
        try #require(
            refusals[0].osWords != refusals[1].osWords,
            "the OS must name the folder, or this comparison proves nothing"
        )
        #expect(refusals[0].error == refusals[1].error, "the payload must not vary with the OS text")
        #expect(refusals[0].error.diagnosticSummary == refusals[1].error.diagnosticSummary)
        #expect(refusals[0].error.displayMessage == refusals[1].error.displayMessage)
        #expect(String(describing: refusals[0].error) == String(describing: refusals[1].error))

        for refusal in refusals {
            for produced in [
                refusal.error.diagnosticSummary, refusal.error.displayMessage, String(describing: refusal.error),
            ] {
                #expect(!produced.contains(refusal.url.lastPathComponent), "REQ-ERR-010: no file names")
                #expect(!produced.contains(refusal.directory.path), "REQ-ERR-010: no file paths")
            }
        }
    }

    // A refused action is our own failure, and the log must not show that it is.
    @Test func everyRefusedActionCarriesADomainAndACodeToo() {
        for error in TimerError.allCases {
            #expect(error.errorCode.domain == ErrorCode.ownDomain, "\(error) has no domain")
            #expect(
                hasDiagnosticShape(error.diagnosticSummary),
                "not `case(domain:code)`: \(error.diagnosticSummary)"
            )
            #expect(
                error.diagnosticSummary == "\(error)(\(error.errorCode))",
                "the summary must name the case it came from"
            )
        }
        let codes = TimerError.allCases.map(\.errorCode.code)
        #expect(Set(codes).count == codes.count, "Decision 0034: a code means one thing")
    }

    // The one place these reach a reader is the diagnostic log's `why` field, and the
    // whole point is that one spelling serves every source. Walk `allCases`, not a list.
    @Test func aRefusedActionIsSpelledLikeAFailureFromTheOS() {
        let fromTheOS = LogWriteError.writeFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        for error in TimerError.allCases {
            #expect(
                shape(of: error.diagnosticSummary) == shape(of: fromTheOS.diagnosticSummary),
                "\(error.diagnosticSummary) is shaped differently from \(fromTheOS.diagnosticSummary)"
            )
            #expect(
                DiagnosticField("why", error.diagnosticSummary).value == error.diagnosticSummary,
                "the log format must not have to rewrite \(error.diagnosticSummary)"
            )
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
            .logFileChangedWhileWriting,
            .stateCorrupted, .stateUnsupportedSchemaVersion,
            .notificationsNotAllowed,
            .bookmarkCreationFailed, .bookmarkResolutionFailed, .accessDenied,
        ] + TimerError.allCases.map(\.errorCode)
            + CommandTranslation.Parameter.allCases.map(\.errorCode)
            + AuthFailureCode.allCases.map(\.errorCode)
        let allOurs = table.allSatisfy { $0.domain == ErrorCode.ownDomain }
        #expect(allOurs)
        #expect(Set(table.map(\.code)).count == table.count, "Decision 0034: a code means one thing")
    }

    // A malformed command is our own failure too, and it goes out over the wire rather than
    // into the log — but 10.2 keeps `message` diagnostic, so it is held to the same shape.
    //
    // The case name says what went wrong with a field and the code says which field, so the
    // pair has to stay unique across both: folding two fields onto one number would read as
    // the same failure in an issue. That is what the payload used to spell out in words.
    @Test func aMalformedCommandCarriesADomainAndACodeToo() {
        var seen = Set<String>()
        for parameter in CommandTranslation.Parameter.allCases {
            for failure in [
                CommandTranslation.Failure.missingParameter(parameter),
                CommandTranslation.Failure.invalidParameter(parameter),
            ] {
                #expect(failure.errorCode.domain == ErrorCode.ownDomain, "\(failure) has no domain")
                #expect(
                    hasDiagnosticShape(failure.diagnosticSummary),
                    "not `case(domain:code)`: \(failure.diagnosticSummary)"
                )
                #expect(failure.diagnosticSummary.hasSuffix("(\(failure.errorCode))"))
                #expect(
                    seen.insert(failure.diagnosticSummary).inserted,
                    "\(failure) is written the same way as another failure"
                )
                // Decision 0018 rewrites whitespace in a field; there must be none to rewrite.
                #expect(
                    DiagnosticField("why", failure.diagnosticSummary).value == failure.diagnosticSummary,
                    "the log format must not have to rewrite \(failure.diagnosticSummary)"
                )
            }
        }
    }

    // A refused connection goes out over the wire too, and 10.2 keeps `authFailed.message`
    // diagnostic just as it keeps `error.message` diagnostic — so it is held to the same
    // shape. Six hand-written sentences used to sit in that field instead (POL-050).
    @Test func aRefusedConnectionCarriesADomainAndACodeToo() {
        let fromTheOS = LogWriteError.writeFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        var seen = Set<String>()
        for code in AuthFailureCode.allCases {
            #expect(code.errorCode.domain == ErrorCode.ownDomain, "\(code) has no domain")
            #expect(
                hasDiagnosticShape(code.diagnosticSummary),
                "not `case(domain:code)`: \(code.diagnosticSummary)"
            )
            #expect(code.diagnosticSummary == "\(code.rawValue)(\(code.errorCode))")
            #expect(
                shape(of: code.diagnosticSummary) == shape(of: fromTheOS.diagnosticSummary),
                "\(code.diagnosticSummary) is shaped differently from \(fromTheOS.diagnosticSummary)"
            )
            // Decision 0018 rewrites whitespace in a field; there must be none to rewrite.
            #expect(
                DiagnosticField("why", code.diagnosticSummary).value == code.diagnosticSummary,
                "the log format must not have to rewrite \(code.diagnosticSummary)"
            )
            #expect(seen.insert(code.diagnosticSummary).inserted, "\(code) reads as another refusal")
        }
        let codes = AuthFailureCode.allCases.map(\.errorCode.code)
        #expect(Set(codes).count == codes.count, "Decision 0034: a code means one thing")
    }

    // Decision 0034: a reader must not be able to tell where a failure came from by its shape.
    // Walk `allCases`, not a list — the payload is what used to break this.
    @Test func aMalformedCommandIsSpelledLikeAFailureFromTheOS() {
        let fromTheOS = LogWriteError.writeFailed(ErrorCode(domain: NSCocoaErrorDomain, code: 513))
        for parameter in CommandTranslation.Parameter.allCases {
            let failure = CommandTranslation.Failure.missingParameter(parameter)
            #expect(
                shape(of: failure.diagnosticSummary) == shape(of: fromTheOS.diagnosticSummary),
                "\(failure.diagnosticSummary) is shaped differently from \(fromTheOS.diagnosticSummary)"
            )
            // The field name is a literal this repository writes, not a leak — but it is the
            // thing a payload would carry, so the summary must not have taken it along.
            #expect(
                !failure.diagnosticSummary.contains(parameter.rawValue),
                "the payload survived into the summary: \(failure.diagnosticSummary)"
            )
        }
    }

    // REQ-LOG-005: even a type nobody planned for lands as a domain and a code.
    @Test func anUnforeseenFailureStillArrivesAsADomainAndCode() {
        let queue = LogWriteQueue()
        queue.enqueue(sampleEntry(), to: .configured)
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
