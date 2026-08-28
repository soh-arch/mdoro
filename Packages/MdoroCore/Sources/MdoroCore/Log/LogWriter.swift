import Foundation

public enum LogWriteError: Error, Equatable, Sendable {
    // REQ-LOG-002: 作成先ディレクトリが存在しない。REQ-LOG-021: Task.md と同一パス。
    case invalidFilePath
    // REQ-ERR-010 / Decision 0034: the OS failure is carried as a domain and a code.
    // It never carries `localizedDescription`, which changes language and names files.
    case readFailed(ErrorCode)
    case writeFailed(ErrorCode)
    // 挿入以外の変更が起きようとした。
    case wouldModifyExistingLines
}

extension LogWriteError: DiagnosableError {

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

// REQ-LOG-001〜004 / 022: 実績ログへの追記。
// **このアプリが利用者のファイルへ書き込む唯一の経路である。**
public struct LogWriter: Sendable {
    public let fileURL: URL
    // REQ-LOG-021 を書き込みのたびに確かめるために持つ。
    // 設定画面の検証だけに頼ると、呼び忘れ・設定値の破損・シンボリックリンクで素通りする。
    public let taskFileURL: URL?
    public let options: LogFormatter.Options

    public init(fileURL: URL, taskFileURL: URL? = nil, options: LogFormatter.Options = .default) {
        self.fileURL = fileURL
        self.taskFileURL = taskFileURL
        self.options = options
    }

    private var fileManager: FileManager { .default }

    // REQ-LOG-021: ログファイルのパストして Task.md と同一のファイルを指定できない。
    public static func validate(logFileURL: URL, taskFileURL: URL?) throws {
        if let taskFileURL,
           logFileURL.standardizedFileURL.resolvingSymlinksInPath()
            == taskFileURL.standardizedFileURL.resolvingSymlinksInPath() {
            throw LogWriteError.invalidFilePath
        }
        // REQ-LOG-002: 作成先ディレクトリが存在しない場合はエラーとし、設定の修正を促す。
        let directory = logFileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LogWriteError.invalidFilePath
        }
    }

    public func append(_ entry: LogEntry, calendar: Calendar = .current) throws {
        // REQ-LOG-021 / 第1原則: 書き込む直前に、書き込み先が Task.md でないことを確かめる。
        try Self.validate(logFileURL: fileURL, taskFileURL: taskFileURL)

        // REQ-LOG-004: 書き込み前にファイルを再読み込みし、外部変更を取り込んでから追記する。
        let existing: String
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                existing = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                throw LogWriteError.readFailed(ErrorCode(error))
            }
        } else {
            // REQ-LOG-002: ファイルが存在しない場合は新規作成する。
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

    // REQ-LOG-004 / REQ-PLT-004: 一時ファイルへ書き出してから差し替える。
    // **同一ディレクトリ内**に置く。サンドボックス下でディレクトリを跨ぐ rename は失敗する。
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

// REQ-LOG-005 / REQ-ERR-004: 書き込みに失敗してもタイマーを止めない。
// キューに積んで再試行し、3回失敗した時点で通知する。
public final class LogWriteQueue: @unchecked Sendable {
    public static let failureThreshold = 3

    public struct FlushResult: Equatable, Sendable {
        public var written: Int
        public var pending: Int
        public var consecutiveFailures: Int
        // 3回失敗に達した。
        public var shouldNotify: Bool
        public var lastError: LogWriteError?
    }

    private let lock = NSLock()
    private var queue: [LogEntry] = []
    private var consecutiveFailures = 0
    private var didNotify = false

    public init(entries: [LogEntry] = []) {
        queue = entries
    }

    // 未書き込みのぶん。**プロセスをまたいで失わないよう永続化する** (REQ-LOG-005)。
    // committedAt は既に立っているので、ここで落とすと二度と書き直されない。
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

    // 先頭から順に書き込む。失敗したらそこで止め、残りはキューに保持したままにする。
    // 順序を守るのは、ログが時系列の記録だからである。
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

        if lastError == nil {
            consecutiveFailures = 0
            didNotify = false
        } else {
            consecutiveFailures += 1
        }

        let reachedThreshold = consecutiveFailures >= Self.failureThreshold
        let shouldNotify = reachedThreshold && !didNotify
        if shouldNotify { didNotify = true }

        return FlushResult(
            written: written,
            pending: queue.count,
            consecutiveFailures: consecutiveFailures,
            shouldNotify: shouldNotify,
            lastError: lastError
        )
    }
}
