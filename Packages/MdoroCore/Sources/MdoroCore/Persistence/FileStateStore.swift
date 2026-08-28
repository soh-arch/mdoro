import Foundation

// REQ-PER-001 / 002: アプリコンテナ内の JSON として永続化する。
// 書き込みは同一ディレクトリ内の一時ファイル経由。**サンドボックス下ではディレクトリを跨ぐ rename が失敗する。**
public struct FileStateStore: StateStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // FileManager は Sendable ではないため保持しない。
    private var fileManager: FileManager { .default }

    // Application Support 配下。サンドボックスではコンテナ内に解決されるのでブックマークは要らない。
    public static func inApplicationSupport(
        directoryName: String = "Mdoro",
        fileName: String = "state.json"
    ) throws -> FileStateStore {
        let fileManager = FileManager.default
        do {
            let base = try fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = base.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return FileStateStore(fileURL: directory.appendingPathComponent(fileName))
        } catch {
            throw StateStoreError.ioFailed(error.localizedDescription)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() throws -> PersistedState? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StateStoreError.ioFailed(error.localizedDescription)
        }

        let state: PersistedState
        do {
            state = try Self.decoder.decode(PersistedState.self, from: data)
        } catch {
            throw StateStoreError.corrupted
        }

        guard state.schemaVersion <= PersistedState.currentSchemaVersion else {
            throw StateStoreError.unsupportedSchemaVersion(
                found: state.schemaVersion,
                supported: PersistedState.currentSchemaVersion
            )
        }
        return state
    }

    public func save(_ state: PersistedState) throws {
        let data: Data
        do {
            data = try Self.encoder.encode(state)
        } catch {
            throw StateStoreError.ioFailed(error.localizedDescription)
        }

        let directory = fileURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temporaryURL, options: .atomic)

            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                // 差し替え先が無い初回は replaceItemAt が使えないため、移動で置く。
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw StateStoreError.ioFailed(error.localizedDescription)
        }
    }
}
