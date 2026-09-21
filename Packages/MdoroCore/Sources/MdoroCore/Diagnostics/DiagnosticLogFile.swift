import Foundation

// REQ-ERR-010 / Decision 0018: an append-only log kept in two generations.
// **Nothing here deletes old lines.** At the size limit the file is renamed, and that is all.
public final class DiagnosticLogFile: @unchecked Sendable {

    public let directory: URL
    public var currentURL: URL { directory.appendingPathComponent(DiagnosticLogFormat.currentFileName) }
    public var previousURL: URL { directory.appendingPathComponent(DiagnosticLogFormat.previousFileName) }

    // Not even a log that cannot be written is passed over in silence.
    // REQ-ERR-010 / Decision 0034 / 0035: a domain and a code, never the words the OS chose.
    // This is the one failure whose code has nowhere to be written down — the log is the thing
    // that is broken — so it goes to the settings screen instead, and it goes there as a code.
    public private(set) var lastFailure: ErrorCode?

    private let header: DiagnosticHeader
    // REQ-ERR-010 / Decision 0018: the header is the only place the OS version, the app version and
    // the settings appear at all. A file that already exists carries the header of whichever launch
    // created it, so a record attached to a bug report would describe the machine as it was then —
    // before an OS update, before a task file was chosen. **Each launch writes its own header, once,
    // ahead of its first line.** Nothing already in the file is read, rewritten or removed: this is
    // one more append. Guarded by the same lock as `lastFailure`.
    private var hasWrittenHeader = false
    private let maxBytes: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        directory: URL,
        header: DiagnosticHeader,
        maxBytes: Int = DiagnosticLogFormat.maxFileBytes,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.header = header
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func write(_ event: DiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try append(DiagnosticLogFormat.line(event) + "\n")
            lastFailure = nil
        } catch {
            lastFailure = ErrorCode(error)
        }
    }

    // The export joins both generations into one, previous then current, in time order.
    public func exportedText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return [previousURL, currentURL]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined()
    }

    private func append(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // **Only the absence of a file opens one.** `open(with:)` replaces whatever is at
        // `currentURL` with this launch's header and this one line, so it must be reached for a file
        // that is not there — never for one that is there and could not be measured.
        guard let size = try currentSize() else {
            try open(with: data)
            return
        }
        // REQ-ERR-010: this launch's header goes in ahead of its first line. A rotation writes the
        // header itself, so it is counted here only to keep the size limit honest either way.
        let pendingHeader = hasWrittenHeader ? Data() : Data(DiagnosticLogFormat.header(header).utf8)
        if DiagnosticLogFormat.shouldRotate(
            currentBytes: size,
            incomingBytes: pendingHeader.count + data.count,
            maxBytes: maxBytes
        ) {
            try rotate()
            try open(with: data)
            return
        }
        // REQ-ERR-010: one call, the way `open(with:)` does it. Written as two calls, a header that
        // succeeded and a line that threw would leave the header on disk with the debt still
        // standing, and the next event would add a second one for the same launch.
        var payload = pendingHeader
        payload.append(data)
        let handle = try FileHandle(forWritingTo: currentURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
        // Only once it is on disk, again as in `open(with:)`.
        hasWrittenHeader = true
    }

    private func open(with data: Data) throws {
        var contents = Data(DiagnosticLogFormat.header(header).utf8)
        contents.append(data)
        try contents.write(to: currentURL, options: .atomic)
        // Only once it is on disk. A write that failed leaves the header still owed, and the next
        // event tries again.
        hasWrittenHeader = true
    }

    private func rotate() throws {
        if fileManager.fileExists(atPath: previousURL.path) {
            try fileManager.removeItem(at: previousURL)
        }
        try fileManager.moveItem(at: currentURL, to: previousURL)
    }

    // The size of the file that is there, or `nil` when there is no file at all. **Those are the
    // two answers; a number for a file nothing could measure is not among them.** Both readers of
    // this treat 0 as a file that is not yet in the way: `append` above opens a new one over it, and
    // `DiagnosticLogFormat.shouldRotate` never rotates at 0 — so answering 0 for a file that could
    // not be measured deletes the diagnostic log (REQ-ERR-010) and switches the two generations off,
    // and the only sign of either is that a log someone was asked to paste into an issue is a
    // header and one line. Refusing instead costs the line that was being written: `write(_:)`
    // catches it into `lastFailure`, which the settings screen reads.
    // `docs/CONTEXT.md` §2 ("failures must not be silenced" — the heading is Japanese, and so is
    // the document) is what chooses that direction.
    private func currentSize() throws -> Int? {
        guard fileManager.fileExists(atPath: currentURL.path) else { return nil }
        // A file that goes away between these two calls throws rather than being taken for absent.
        // One line is lost and nothing on disk is written over, which is the safe way round.
        let attributes = try fileManager.attributesOfItem(atPath: currentURL.path)
        return try MeasuredLogSize.bytes(in: attributes)
    }
}

// Reading a size out of what the file system said, kept apart from reading the file — the shape
// `ListenerReadiness.settledPort` uses. **This is the one place the decision can be tried**: a real
// `attributesOfItem` cannot be made to hand back a dictionary with no `.size` in it, so asked
// through a file the refusing branch is unreachable and only the answering one gets tested.
enum MeasuredLogSize {

    // The name is the claim: the caller has already established that the file is there, and a file
    // that is there has a size. Deliberately carries no `ErrorCode` of its own, as
    // `NoPortOnAReadyListener` does: Decision 0034 hands out a fixed number per case from the bands
    // in `ErrorCode.swift`, none of those bands covers measuring a file, and opening one is a
    // decision about that ledger. Bridged, this reaches `lastFailure` as this type's own name.
    struct NoSizeOnAFileThatIsThere: Error {}

    // `.size` is documented as an `NSNumber`. What is refused here is its absence — and anything
    // else standing in its place, since a value that is not a number is not a size either.
    static func bytes(in attributes: [FileAttributeKey: Any]) throws -> Int {
        guard let size = attributes[.size] as? NSNumber else { throw NoSizeOnAFileThatIsThere() }
        return size.intValue
    }
}
