import Foundation

// REQ-ERR-010 / Decision 0034: a failure is recorded as a domain and a code, never as the
// words the OS chose. `localizedDescription` follows the system locale and usually carries a
// file name, so what closes both leaks is the bridge, not the type: `init(_ error:)` is the
// only way an OS failure gets in here, and it reads nothing but `domain` and `code`. The
// other initialisers take values the app wrote itself. `ErrorReportingTests`
// .aRefusalFromTheFileSystemKeepsOnlyItsDomainAndCode holds that bridge shut, by producing
// the same failure in two folders the OS names differently and requiring one answer.
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

    // Codes in the `Mdoro` domain are fixed per case. The table below owns every number.
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

// Decision 0034: fixed codes for the `Mdoro` domain. Allocated once here, never reused,
// so a number found in an issue always means the same thing.
public extension ErrorCode {
    // 1–9: writing the session log.
    static let logInvalidFilePath = ErrorCode(own: 1)
    static let logWouldModifyExistingLines = ErrorCode(own: 2)
    static let logFolderNotSet = ErrorCode(own: 3)
    // 10–19: persisting state.
    static let stateCorrupted = ErrorCode(own: 10)
    static let stateUnsupportedSchemaVersion = ErrorCode(own: 11)
    // 20–29: notifications.
    static let notificationsNotAllowed = ErrorCode(own: 20)
    // 30–39: reaching a folder the user picked (security-scoped bookmarks).
    static let bookmarkCreationFailed = ErrorCode(own: 30)
    static let bookmarkResolutionFailed = ErrorCode(own: 31)
    static let accessDenied = ErrorCode(own: 32)
    // 40–49: actions the timer refused. Owned by `TimerError.errorCode`, which switches
    // exhaustively, so a new case cannot reach the diagnostic log without a number.
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
// Only failures that actually reach a screen answer it — the sentence lives with the case
// so the two outputs never share a string. Fixed English (REQ-UIX-038), never from the OS.
public protocol ReportableError: DiagnosableError {
    var displayMessage: String { get }
}
