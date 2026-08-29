import Foundation

public enum LogWriteError: Error, Equatable, Sendable {
    // REQ-LOG-002: the target directory does not exist. REQ-LOG-021: the same path as Task.md.
    case invalidFilePath
    // REQ-ERR-010 / Decision 0034: the OS failure is carried as a domain and a code.
    // It never carries `localizedDescription`, which changes language and names files.
    case readFailed(ErrorCode)
    case writeFailed(ErrorCode)
    // A change other than an insertion was about to happen.
    case wouldModifyExistingLines
}

extension LogWriteError: ReportableError {

    public var errorCode: ErrorCode {
        switch self {
        case .invalidFilePath: .logInvalidFilePath
        case let .readFailed(code), let .writeFailed(code): code
        case .wouldModifyExistingLines: .logWouldModifyExistingLines
        }
    }

    public var diagnosticSummary: String { errorCode.summary(caseName) }

    private var caseName: String {
        switch self {
        case .invalidFilePath: "invalidFilePath"
        case .readFailed: "readFailed"
        case .writeFailed: "writeFailed"
        case .wouldModifyExistingLines: "wouldModifyExistingLines"
        }
    }

    // REQ-ERR-004 / REQ-UIX-038: entries stay queued on failure (REQ-LOG-005), so each
    // sentence says that too — otherwise the reader assumes the session was lost.
    public var displayMessage: String {
        switch self {
        case .invalidFilePath:
            "The folder set for the session log cannot be used. Choose it again in Settings."
        case .readFailed:
            "The existing session log could not be read, so nothing was written. Check that the file can be opened; unwritten entries stay queued."
        case .writeFailed:
            "The session log could not be written. Check that the folder still exists and has free space; unwritten entries stay queued."
        case .wouldModifyExistingLines:
            "Writing would have changed lines that are already in the session log, so nothing was written. Check the file around today's heading."
        }
    }
}

// REQ-LOG-001 to 004 / 022: appending to the session log.
// **This is the only path by which the app writes to a file of the user's.**
public struct LogWriter: Sendable {
    public let fileURL: URL
    // Held so REQ-LOG-021 can be checked on every write.
    // Relying on the settings screen alone lets a missed call, a corrupted value, or a symlink through.
    public let taskFileURL: URL?
    public let options: LogFormatter.Options

    public init(fileURL: URL, taskFileURL: URL? = nil, options: LogFormatter.Options = .default) {
        self.fileURL = fileURL
        self.taskFileURL = taskFileURL
        self.options = options
    }

    private var fileManager: FileManager { .default }

    // REQ-LOG-021: the log file path may not name the same file as Task.md.
    public static func validate(logFileURL: URL, taskFileURL: URL?) throws {
        if let taskFileURL,
           logFileURL.standardizedFileURL.resolvingSymlinksInPath()
            == taskFileURL.standardizedFileURL.resolvingSymlinksInPath() {
            throw LogWriteError.invalidFilePath
        }
        // REQ-LOG-002: a missing target directory is an error, and the user is asked to fix the setting.
        let directory = logFileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LogWriteError.invalidFilePath
        }
    }

    public func append(_ entry: LogEntry, calendar: Calendar = .current) throws {
        // REQ-LOG-021 / first principle: immediately before writing, confirm the destination is not Task.md.
        try Self.validate(logFileURL: fileURL, taskFileURL: taskFileURL)

        // REQ-LOG-004: reread the file before writing, so changes made elsewhere are carried over.
        let existing: String
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                existing = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                throw LogWriteError.readFailed(ErrorCode(error))
            }
        } else {
            // REQ-LOG-002: create the file when it does not exist.
            existing = ""
        }

        let line = LogFormatter.line(for: entry, options: options, calendar: calendar)
        let heading = LogFormatter.dayHeading(for: entry.logicalDate, calendar: calendar)

        let insertion: LogFileEditor.Insertion
        do {
            insertion = try LogFileEditor.inserting(
                line: line, underHeading: heading, logicalDate: entry.logicalDate,
                into: existing, calendar: calendar
            )
        } catch {
            throw LogWriteError.wouldModifyExistingLines
        }

        try writeAtomically(insertion.contents)
    }

    // REQ-LOG-004 / REQ-PLT-004: write to a temporary file, then swap it in.
    // It goes **in the same directory**, which is one way to satisfy the real constraint: the two
    // paths must be on the same volume (`docs/PLATFORM.md`). Directories do not enter into it.
    private func writeAtomically(_ contents: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try Data(contents.utf8).write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw LogWriteError.writeFailed(ErrorCode(error))
        }
    }
}

// REQ-LOG-005 / REQ-ERR-004: a failed write never stops the timer.
// Entries are queued and retried; the user is told once three of them have failed — three in a
// row, or three of the last ten (Decision 0039).
public final class LogWriteQueue: @unchecked Sendable {
    // REQ-ERR-004: three failures are enough to speak up.
    public static let failureThreshold = 3
    // REQ-ERR-004 / Decision 0039: how far back a failure keeps counting. Failures that come and go
    // never build up a run, and a bug that refuses one write in three would otherwise stay quiet
    // forever — which is exactly the bug worth hearing about.
    public static let recentWindow = 10

    private enum FlushOutcome {
        case succeeded
        case failed
    }

    public struct FlushResult: Equatable, Sendable {
        public var written: Int
        public var pending: Int
        // Kept for diagnostics: it tells steady failure apart from intermittent failure.
        public var consecutiveFailures: Int
        // How many of the last `recentWindow` flushes failed, this one included.
        public var recentFailures: Int
        // A threshold was reached and the user has not been told about it yet.
        public var shouldNotify: Bool
        public var lastError: LogWriteError?
    }

    private let lock = NSLock()
    private var queue: [LogEntry] = []
    private var consecutiveFailures = 0
    // The outcome of each of the last `recentWindow` flushes, oldest first.
    private var recentOutcomes: [FlushOutcome] = []
    private var didNotify = false

    public init(entries: [LogEntry] = []) {
        queue = entries
    }

    // What has not been written yet. **Persisted so it survives across processes** (REQ-LOG-005).
    // committedAt is already set, so anything dropped here is never written again.
    public var pendingEntries: [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return queue
    }

    public var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }

    public func enqueue(_ entry: LogEntry) {
        lock.lock(); defer { lock.unlock() }
        queue.append(entry)
    }

    // Written from the front, in order. On a failure it stops there and the rest stays queued.
    // The order is kept because the log is a record in time.
    @discardableResult
    public func flush(using write: (LogEntry) throws -> Void) -> FlushResult {
        lock.lock(); defer { lock.unlock() }

        var written = 0
        var lastError: LogWriteError?

        while let entry = queue.first {
            do {
                try write(entry)
                queue.removeFirst()
                written += 1
            } catch let error as LogWriteError {
                lastError = error
                break
            } catch {
                lastError = .writeFailed(ErrorCode(error))
                break
            }
        }

        // Decision 0039: one outcome per flush, only the last `recentWindow` of them kept.
        // A flush with nothing queued tried to write nothing, so it is evidence of neither success
        // nor failure and stays out of the window. Letting it in would let idle flushes wash real
        // failures out — ten of them now, where the old counter only ever lost two.
        // `consecutiveFailures` is deliberately left alone: resetting on such a flush is how it
        // behaved before this window existed, and only the window is being corrected here.
        let attemptedAWrite = written > 0 || lastError != nil
        if attemptedAWrite {
            recentOutcomes.append(lastError == nil ? .succeeded : .failed)
            if recentOutcomes.count > Self.recentWindow {
                recentOutcomes.removeFirst(recentOutcomes.count - Self.recentWindow)
            }
        }
        consecutiveFailures = lastError == nil ? 0 : consecutiveFailures + 1
        let recentFailures = recentOutcomes.count(where: { $0 == .failed })

        // REQ-ERR-004: a run of three is the special case of three within the last ten, so the
        // second test alone would already decide this. Both are spelled out because a run is what
        // the reader looks for, and because each number is reported on its own.
        let reachedThreshold = consecutiveFailures >= Self.failureThreshold
            || recentFailures >= Self.failureThreshold
        let shouldNotify = reachedThreshold && !didNotify
        // Saying it once is enough while the same trouble stands. Enough successes to fall back
        // under both thresholds arm it again.
        didNotify = reachedThreshold

        return FlushResult(
            written: written,
            pending: queue.count,
            consecutiveFailures: consecutiveFailures,
            recentFailures: recentFailures,
            shouldNotify: shouldNotify,
            lastError: lastError
        )
    }
}
