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

        let size = currentSize()
        if size == 0 {
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
        let handle = try FileHandle(forWritingTo: currentURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if !pendingHeader.isEmpty {
            try handle.write(contentsOf: pendingHeader)
        }
        try handle.write(contentsOf: data)
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

    private func currentSize() -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: currentURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
