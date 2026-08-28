import Foundation

// REQ-ERR-010 / Decision 0034: a failure is recorded as a domain and a code, never as the
// words the OS chose. `localizedDescription` follows the system locale and usually carries a
// file name, so a value that cannot hold a string closes both leaks by construction rather
// than by redaction (Decision 0018 takes the same shape).
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
}

// REQ-ERR-010 / Decision 0034: the screen and the diagnostic log answer different questions.
// The log wants a cause that is the same string in every locale; the screen wants to know
// what happened and what to do next. One type, two answers, and no shared string between them.
public protocol DiagnosableError: Error {
    var errorCode: ErrorCode { get }
    // `case(domain:code)`, e.g. `writeFailed(NSCocoaErrorDomain:513)`.
    var diagnosticSummary: String { get }
    // Fixed English, per case (REQ-UIX-038). Never derived from the OS.
    var displayMessage: String { get }
}
