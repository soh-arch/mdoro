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
    // POL-120: the file on disk stopped being the one the insertion was built on, every time it
    // was tried. Nothing was written.
    case fileChangedWhileWriting
}

extension LogWriteError: ReportableError {

    public var errorCode: ErrorCode {
        switch self {
        case .invalidFilePath: .logInvalidFilePath
        case let .readFailed(code), let .writeFailed(code): code
        case .wouldModifyExistingLines: .logWouldModifyExistingLines
        case .fileChangedWhileWriting: .logFileChangedWhileWriting
        }
    }

    public var diagnosticSummary: String { errorCode.summary(caseName) }

    private var caseName: String {
        switch self {
        case .invalidFilePath: "invalidFilePath"
        case .readFailed: "readFailed"
        case .writeFailed: "writeFailed"
        case .wouldModifyExistingLines: "wouldModifyExistingLines"
        case .fileChangedWhileWriting: "fileChangedWhileWriting"
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
        case .fileChangedWhileWriting:
            "The session log kept changing while it was being written, so nothing was written and nothing of yours was replaced. Close the file in your editor; unwritten entries stay queued."
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

    // POL-120: how many times a write is rebuilt when the file turned out to have changed since it
    // was read. A conflict means someone else saved within the same few milliseconds, and reading
    // again and inserting into what they wrote is the answer REQ-LOG-004 already gives. The second
    // attempt clears an ordinary collision and the third leaves room for one more coincidence.
    // Beyond that the file is being written continuously by something else, and the queue
    // (REQ-LOG-005) trying again on the next flush is better than a loop holding the caller here.
    // There is no wait between attempts: this runs on the caller's thread.
    public static let maximumWriteAttempts = 3

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
        try append(entry, calendar: calendar, betweenReadAndReplace: nil)
    }

    // The hook is how a test puts someone else's save into the very gap the guard below is about.
    // **Nothing in the app passes one**, and it is not part of the public surface.
    func append(
        _ entry: LogEntry,
        calendar: Calendar,
        betweenReadAndReplace: (() -> Void)?
    ) throws {
        // REQ-LOG-021 / first principle: immediately before writing, confirm the destination is not Task.md.
        try Self.validate(logFileURL: fileURL, taskFileURL: taskFileURL)

        let line = LogFormatter.line(for: entry, options: options, calendar: calendar)
        let heading = LogFormatter.dayHeading(for: entry.logicalDate, calendar: calendar)

        for _ in 0..<Self.maximumWriteAttempts {
            // REQ-LOG-004: reread the file before writing, so changes made elsewhere are carried over.
            let snapshot = try currentContents()

            let insertion: LogFileEditor.Insertion
            do {
                insertion = try LogFileEditor.inserting(
                    line: line, underHeading: heading, logicalDate: entry.logicalDate,
                    // REQ-LOG-002: a file that is not there yet is written as if it were empty.
                    into: snapshot ?? "", calendar: calendar
                )
            } catch {
                throw LogWriteError.wouldModifyExistingLines
            }

            betweenReadAndReplace?()

            if try writeAtomically(insertion.contents, replacing: snapshot) { return }
        }

        // POL-120: every attempt found the file different from the one it had read, so the entry
        // was never written. REQ-LOG-005 keeps it queued and the next flush reads the file again.
        throw LogWriteError.fileChangedWhileWriting
    }

    // What the insertion is built on, or nil when there is no file yet. **The distinction is kept**:
    // a file that appeared in the meantime belongs to someone else, and writing over it would lose
    // all of it rather than one line.
    private func currentContents() throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw LogWriteError.readFailed(ErrorCode(error))
        }
    }

    // REQ-LOG-004 / REQ-PLT-004: write to a temporary file, then swap it in.
    // It goes **in the same directory**, which is one way to satisfy the real constraint: the two
    // paths must be on the same volume (`docs/PLATFORM.md`). Directories do not enter into it.
    //
    // POL-120 / first principle: the swap replaces the **whole file**, so anything saved to it
    // since `snapshot` was read is inside what is about to be overwritten. `replaceItemAt` is
    // atomic in itself, and that says nothing about the interval before it. So the bytes are read
    // once more here, with the replacement already staged, and compared against the ones the
    // insertion was built on. Returns false when they differ; nothing is written in that case.
    //
    // **Why the contents and not the metadata.** A modification date cannot see a save that lands
    // in the same tick it was taken, and how fine a tick is belongs to the file system, not to us.
    // A size cannot see an edit of equal length. An inode cannot see an editor that writes in
    // place. All three together still miss a same-length, in-place save inside one tick — which is
    // what correcting a typo in a line looks like. The contents have no such blind spot, and their
    // one false negative is harmless: if the bytes match, the insertion was built on exactly what
    // is there, so nothing of the user's is lost by writing it, however many times the file was
    // rewritten to reach that state. The price is one extra read of a file we already read.
    //
    // **This narrows the window; it does not close it.** Between the read below and the swap
    // returning there is still an interval, and a save landing inside it is still lost. What has
    // been taken out of that interval is everything slow — formatting, the insertion, and writing
    // the temporary file all happen before the check. **It cannot be closed:** POSIX offers no
    // compare-and-swap on a file, and an advisory lock binds only processes that ask for one,
    // which the user's editor does not.
    private func writeAtomically(_ contents: String, replacing snapshot: String?) throws -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        // Decision 0042: the name comes from `LogTemporaryFile`, which is also where the startup
        // sweep decides what one of these looks like. Spelling it out here again is how the two
        // would come apart.
        let temporaryURL = directory.appendingPathComponent(
            LogTemporaryFile.name(forLogFileNamed: fileURL.lastPathComponent)
        )
        do {
            try Data(contents.utf8).write(to: temporaryURL, options: .atomic)

            guard try currentContents() == snapshot else {
                try? fileManager.removeItem(at: temporaryURL)
                return false
            }

            if snapshot == nil {
                // REQ-LOG-002: create the file when it does not exist — and it still does not.
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            } else {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            }
        } catch let error as LogWriteError {
            // The reread above refused; it already says what went wrong.
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw LogWriteError.writeFailed(ErrorCode(error))
        }
        return true
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
        // How many of the last `recentWindow` attempts failed, this one included.
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

    // REQ-LOG-002 / Decision 0033: **an entry is taken only when there is somewhere to write it.**
    // The refusal lives at the queue's door because the queue is what REQ-LOG-002 names — "nor
    // queued" — and because a rule kept here cannot be forgotten by a call site. Returns whether
    // the entry was taken; a refusal is not a failure and never reaches `flush`, so it counts
    // towards neither REQ-LOG-005's retries nor REQ-ERR-004's threshold.
    @discardableResult
    public func enqueue(_ entry: LogEntry, to destination: LogDestination) -> Bool {
        guard destination.recordsEntries else { return false }
        lock.lock(); defer { lock.unlock() }
        queue.append(entry)
        return true
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

        // Decision 0039: a flush with nothing queued tried to write nothing, so it is evidence of
        // neither success nor failure and stays out of the window.
        let attemptedAWrite = written > 0 || lastError != nil
        return settle(
            outcome: attemptedAWrite ? (lastError == nil ? .succeeded : .failed) : nil,
            written: written,
            lastError: lastError
        )
    }

    // REQ-ERR-004 / Decision 0039: **an attempt that failed before it could reach the writing.**
    // Getting to the file can fail before a single entry is handed over — resolving the bookmark
    // for the log folder, and starting access to it, both happen outside `flush`. Nothing is
    // written and nothing leaves the queue, so from the user's side this is a failed write like any
    // other, and REQ-ERR-004 counts **write attempts**, not lines. Left out of the count, a log
    // folder that had gone away showed on the screen for as long as it stayed away and never once
    // notified: `flush` was never entered, so no attempt on that path was ever counted.
    //
    // The caller keeps the error itself — it did not come from `LogWriter`, and `lastError` on the
    // result stays nil. Everything else is the same accounting `flush` does, so this shares the
    // window, the run counter, and the say-it-once suppression rather than keeping a second set.
    @discardableResult
    public func recordFailedAttempt() -> FlushResult {
        lock.lock(); defer { lock.unlock() }
        // With nothing owed to the file, nothing was attempted — the same reading `flush` gives a
        // call that found the queue empty. `flush` cannot lean on its callers to never ask, and
        // neither can this.
        return settle(outcome: queue.isEmpty ? nil : .failed, written: 0, lastError: nil)
    }

    // The accounting both entrances share. `outcome` is nil when no write was attempted at all.
    // The caller holds `lock`.
    private func settle(outcome: FlushOutcome?, written: Int, lastError: LogWriteError?) -> FlushResult {
        // Decision 0039: one outcome per attempt, only the last `recentWindow` of them kept.
        // Letting attempts that wrote nothing in would let idle flushes wash real failures out —
        // ten of them now, where the old counter only ever lost two.
        if let outcome {
            recentOutcomes.append(outcome)
            if recentOutcomes.count > Self.recentWindow {
                recentOutcomes.removeFirst(recentOutcomes.count - Self.recentWindow)
            }
        }
        // `consecutiveFailures` is deliberately reset by an attempt that wrote nothing: that is how
        // it behaved before the window existed, and only the window is being corrected here.
        consecutiveFailures = outcome == .failed ? consecutiveFailures + 1 : 0
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
