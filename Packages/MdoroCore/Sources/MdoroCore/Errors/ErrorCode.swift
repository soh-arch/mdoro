import Foundation

// REQ-ERR-010 / Decision 0034: a failure is recorded as a domain and a code, never as the
// words the OS chose. `localizedDescription` follows the system locale and usually carries a
// file name, so what closes both leaks is the bridge, not the type: `init(_ error:)` is the
// only way an OS failure gets in here, and it reads nothing but `domain` and `code`. The
// other initialisers take values the app wrote itself, and two stored fields leave nowhere
// for a third. `ErrorReportingTests.aRefusalFromTheFileSystemKeepsOnlyItsDomainAndCode`
// guards the half of that which varies with the file — it produces the same failure in two
// folders the OS names differently and requires one answer. The rest is the two fields.
public struct ErrorCode: Equatable, Hashable, Sendable, CustomStringConvertible {

    // Decision 0034: our own failures carry a domain too, so a reader of the diagnostic log
    // cannot tell them apart from OS failures by their shape.
    public static let ownDomain = "Mdoro"

    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    // Codes in the `Mdoro` domain are fixed per case, and they are handed out in five
    // places: the table below, `TimerError.errorCode` in Effect.swift, which owns 40–49,
    // `CommandTranslation.Parameter.errorCode`, which owns 50–59, `AuthFailureCode.errorCode`
    // in ProtocolTypes.swift, which owns 60–69, and `ProtocolRefusal.errorCode` beside it,
    // which owns 70–79. Read all five before taking a number —
    // `everyCodeInOurOwnDomainMeansOneThing` walks the union.
    //
    // A number taken here is also written into the ledger in
    // `ACodeKeepsItsMeaningTests.swift`, which holds each number against its meaning and keeps
    // a withdrawn number withdrawn. Taking one without recording it there fails that suite.
    public init(own code: Int) {
        self.init(domain: Self.ownDomain, code: code)
    }

    // Every Swift error bridges to `NSError`, so the cause survives at full resolution
    // while the words the OS wrote are dropped here.
    public init(_ error: some Error) {
        let bridged = error as NSError
        self.init(domain: bridged.domain, code: bridged.code)
    }

    public var description: String { "\(domain):\(code)" }

    // The one shape the diagnostic log uses for every failure: `case(domain:code)`.
    public func summary(_ caseName: String) -> String { "\(caseName)(\(self))" }
}

// Decision 0034: fixed codes for the `Mdoro` domain. Allocated once and never reused, so a
// number found in an issue always means the same thing — 0034 fixes the code per case, and
// `ACodeKeepsItsMeaningTests` is what holds the second half. This is not the whole domain:
// 40–49 are allocated with `TimerError` instead, at the bottom of this table.
public extension ErrorCode {
    // 1–9: writing the session log.
    static let logInvalidFilePath = ErrorCode(own: 1)
    static let logWouldModifyExistingLines = ErrorCode(own: 2)
    static let logFolderNotSet = ErrorCode(own: 3)
    static let logFileChangedWhileWriting = ErrorCode(own: 4)
    // 10–19: persisting state.
    static let stateCorrupted = ErrorCode(own: 10)
    static let stateUnsupportedSchemaVersion = ErrorCode(own: 11)
    // Decision 0040: the file holding the `id` was read and held nothing this version knows.
    static let identityUnreadable = ErrorCode(own: 12)
    // REQ-SEC-002 / Decision 0040: the device token records could not be read. The Keychain
    // reported success and handed back something that is not the records, so there is no
    // `OSStatus` to carry — but the consequence is the one that matters: **what is on file may
    // still be intact, so it must not be written over.**
    static let deviceTokensUnreadable = ErrorCode(own: 13)
    // 20–29: notifications.
    static let notificationsNotAllowed = ErrorCode(own: 20)
    // 30–39: reaching a folder the user picked (security-scoped bookmarks).
    static let bookmarkCreationFailed = ErrorCode(own: 30)
    static let bookmarkResolutionFailed = ErrorCode(own: 31)
    static let accessDenied = ErrorCode(own: 32)
    // 40–49: actions the timer refused. Owned by `TimerError.errorCode`, which switches
    // exhaustively, so a new case cannot reach the diagnostic log without a number.
    // 50–59: the fields of a `command` (10.2). Owned by `CommandTranslation.Parameter`,
    // which switches exhaustively for the same reason.
    // 60–69: refused connections (10.2 `authFailed.code`). Owned by `AuthFailureCode`,
    // exhaustive for the same reason again.
    // 70–79: REQ-PRT-004 — refused connections whose reason 10.2 carries on `error.code`
    // instead, because `authFailed.code` has no word for it. Owned by `ProtocolRefusal`,
    // exhaustive for the same reason again.
}

// REQ-ERR-010 / Decision 0034: anything that reaches the diagnostic log's `why` field
// answers these two, whoever raised it. A reader must not be able to tell an OS failure
// from one of ours by how it is written, so there is one shape and no exceptions.
public protocol DiagnosableError: Error {
    var errorCode: ErrorCode { get }
    // `case(domain:code)`, e.g. `writeFailed(NSCocoaErrorDomain:513)`.
    var diagnosticSummary: String { get }
}

// The screen asks a different question than the log: what happened, and what to do next.
// A failure conforms when the sentence belongs with the case — one per case, so the screen
// and the log never share a string. Fixed English (REQ-UIX-038), never from the OS.
// Reaching a screen is not the test. `TimerError` reaches one, but `PresetEditorView` owns
// that wording and folds several cases into a single line, so it stays diagnostic-only.
public protocol ReportableError: DiagnosableError {
    var displayMessage: String { get }
}
