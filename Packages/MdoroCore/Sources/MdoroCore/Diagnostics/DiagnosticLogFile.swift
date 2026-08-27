import Foundation

// REQ-ERR-010 / Decision 0018: 追記のみ・2世代のログファイル。
//
// **古い行を削除する処理を持たない。** 「読んで、一部を捨てて、書き戻す」は
// このアプリが最も持ちたくない形をしている（[0002] `Task.md` へは書き込まない）。
// 上限に達したらリネームするだけにすれば、日付のパースも書き戻しも要らない。
public final class DiagnosticLogFile: @unchecked Sendable {

    public let directory: URL
    public var currentURL: URL { directory.appendingPathComponent(DiagnosticLogFormat.currentFileName) }
    public var previousURL: URL { directory.appendingPathComponent(DiagnosticLogFormat.previousFileName) }

    // ログ自体が書けないことは黙って捨てない（CONTEXT「失敗を黙らせない」）。
    public private(set) var lastFailure: String?

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
            lastFailure = String(describing: error)
        }
    }

    // 書き出しは「前の世代 → いまの世代」の時系列で1本にまとめる。
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
