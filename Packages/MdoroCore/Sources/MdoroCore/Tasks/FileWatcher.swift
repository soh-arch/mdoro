import Foundation

// REQ-TSK-002 / REQ-PLT-006: Task.md の変更を監視し、300ms のデバウンスを挟んで再読み込みする。
// **記述子ではなく親ディレクトリを監視する。** 一時ファイル経由の保存で inode が差し替わると、
// 記述子に張った監視は無効になる。
public final class FileWatcher: @unchecked Sendable {
    public static let debounceInterval: TimeInterval = 0.3

    private let directoryURL: URL
    private let fileName: String
    private let queue: DispatchQueue
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void

    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pendingWork: DispatchWorkItem?

    public init(
        fileURL: URL,
        debounce: TimeInterval = FileWatcher.debounceInterval,
        queue: DispatchQueue = DispatchQueue(label: "MdoroCore.FileWatcher"),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.directoryURL = fileURL.deletingLastPathComponent()
        self.fileName = fileURL.lastPathComponent
        self.debounce = debounce
        self.queue = queue
        self.onChange = onChange
    }

    public var watchedFileName: String { fileName }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard source == nil else { return }

        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { throw LogWriteError.invalidFilePath }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleNotification() }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { stop() }

    // ディレクトリ単位の監視なので無関係な保存でも発火する。デバウンスで束ねる。
    private func scheduleNotification() {
        lock.lock(); defer { lock.unlock() }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.pendingWork = nil
            self.lock.unlock()
            self.onChange()
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}

// REQ-TSK-001 / REQ-PLT-003: Task.md の読み込み。
// **この型に書き込む手段はない。** OS のブックマークと API の両方で読み取り専用を担保する。
public struct TaskFileReader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public enum ReadError: Error, Equatable, Sendable {
        // REQ-ERR-001: Task.md が存在しない / アクセス権がない。
        case unavailable
    }

    // REQ-ERR-003: 先頭 5MB のみを読む。全体をメモリへ載せず、ハンドルから上限ぶんだけ読む。
    public func read() throws -> TaskParseResult {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw ReadError.unavailable
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: TaskParser.maxBytes + 1) else {
            throw ReadError.unavailable
        }
        return try TaskParser.parse(data: data)
    }
}
