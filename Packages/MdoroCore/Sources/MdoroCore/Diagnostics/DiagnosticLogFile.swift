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
        if DiagnosticLogFormat.shouldRotate(currentBytes: size, incomingBytes: data.count, maxBytes: maxBytes) {
            try rotate()
            try open(with: data)
            return
        }
        let handle = try FileHandle(forWritingTo: currentURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func open(with data: Data) throws {
        var contents = Data(DiagnosticLogFormat.header(header).utf8)
        contents.append(data)
        try contents.write(to: currentURL, options: .atomic)
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
