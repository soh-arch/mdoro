import Foundation

// REQ-TSK-002: Task.md の変更を常時監視し、300ms のデバウンスを挟んで再読み込みする。
//
// **記述子ではなく親ディレクトリを監視する。** Obsidian は保存時に一時ファイル経由の置き換えを
// 行うことがあり、ファイル記述子に張った監視は inode 差し替え後に無効化される (REQ-PLT-006)。
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

    // ディレクトリ単位の監視なので、Vault 内の無関係な保存でも発火する。
    // 300ms のデバウンスで束ね、連続保存のたびに読み直さないようにする。
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
//
// **この型に書き込む手段はない。** 読み取り専用であることを、OS のブックマーク
// (`securityScopeAllowOnlyReadAccess`) と、API にそもそも書き込み口を持たないことの両方で担保する。
public struct TaskFileReader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public enum ReadError: Error, Equatable, Sendable {
        // REQ-ERR-001: Task.md が存在しない / アクセス権がない。
        case unavailable
    }

    // REQ-ERR-003: 先頭 5MB のみを読む。切り詰める前に全体をメモリへ載せないよう、
    // ファイルハンドルから上限ぶんだけ読む。
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
