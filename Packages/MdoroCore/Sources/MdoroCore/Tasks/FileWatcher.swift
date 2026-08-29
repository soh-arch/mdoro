import Foundation

// REQ-TSK-002 / REQ-PLT-006: watch Task.md for changes and reread it after a 300ms debounce.
// **The parent directory is watched, not the descriptor.** A save through a temporary file swaps
// the inode, and a watch held on the descriptor stops meaning anything.
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

    // The watch is on the directory, so an unrelated save fires it too. The debounce gathers them up.
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

// REQ-TSK-001 / REQ-PLT-003: reading Task.md.
// **This type offers no way to write.** Read-only is held by the OS bookmark and by the API alike.
public struct TaskFileReader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public enum ReadError: Error, Equatable, Sendable {
        // REQ-ERR-001: Task.md is missing, or cannot be reached.
        case unavailable
    }

    // REQ-ERR-003: only the first 5MB is read. Nothing loads the whole file into memory; the handle
    // gives up the limit and no more.
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
