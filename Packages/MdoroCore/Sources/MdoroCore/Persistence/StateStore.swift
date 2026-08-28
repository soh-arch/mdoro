import Foundation

public enum StateStoreError: Error, Equatable, Sendable {
    // 読めたが解釈できない。**黙って初期状態へ戻さない。** 上書きするとユーザーの実績が消える。
    case corrupted
    // このビルドより新しいスキーマ。ダウングレード時に読み書きして壊さないための防壁。
    case unsupportedSchemaVersion(found: Int, supported: Int)
    // REQ-ERR-010 / Decision 0034: a domain and a code, never the words the OS chose.
    case ioFailed(ErrorCode)
}

extension StateStoreError: ReportableError {

    public var errorCode: ErrorCode {
        switch self {
        case .corrupted: .stateCorrupted
        case .unsupportedSchemaVersion: .stateUnsupportedSchemaVersion
        case let .ioFailed(code): code
        }
    }

    public var diagnosticSummary: String { errorCode.summary(caseName) }

    private var caseName: String {
        switch self {
        case .corrupted: "corrupted"
        case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
        case .ioFailed: "ioFailed"
        }
    }

    // REQ-UIX-038 / Decision 0034: fixed English per case. The saved file is never
    // overwritten on these, so every sentence points at the file rather than at a retry.
    public var displayMessage: String {
        switch self {
        case .corrupted:
            "The saved state could not be read. Mdoro left the file alone; move it aside to start from a clean state."
        case .unsupportedSchemaVersion:
            "The saved state was written by a newer version of Mdoro. Update Mdoro, or move the file aside to start from a clean state."
        case .ioFailed:
            "The saved state could not be read or written. Check that Mdoro's Application Support folder is available."
        }
    }
}

// REQ-PER-001 / 002: 永続化と復元の窓口。実体の差し替えでテストできるようにする。
public protocol StateStore: Sendable {
    // 保存が存在しない場合は nil を返す。壊れている場合は throw する（nil と区別する）。
    func load() throws -> PersistedState?
    func save(_ state: PersistedState) throws
}

public extension StateStore {
    // REQ-PER-002 / 003: 読み込みと復元判定をまとめた起動時の入り口。
    // 保存が無ければ初期状態、あれば REQ-PER-003 の判定を通した状態を返す。
    func loadAndRestore(now: Date, settings: AppSettings = .default) throws -> TimerEngine.Reduction {
        StateRestoration.reduction(from: try load(), now: now, settings: settings)
    }
}

// REQ-ERR-017 / Decision 0035: reading and restoring are separate steps because a caller that
// has to report the read's failure needs both halves of it — the failure and whatever it can
// still show. Folding them together forced a second `load()` to get at the saved values, and
// a second read is a second chance to fail differently.
public enum StateRestoration {
    public static func reduction(
        from saved: PersistedState?,
        now: Date,
        settings: AppSettings = .default
    ) -> TimerEngine.Reduction {
        guard let saved else {
            let initial = PersistedState.initial(now: now, settings: settings)
            return TimerEngine.Reduction(context: initial.timer, presets: initial.presets, effects: [])
        }
        return TimerEngine.restore(
            context: saved.timer,
            presets: saved.presets,
            settings: saved.settings,
            now: now
        )
    }
}

// テストと、永続化を持たない実行経路のための実体。
public final class InMemoryStateStore: StateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PersistedState?
    public private(set) var saveCount = 0

    public init(initial: PersistedState? = nil) {
        self.stored = initial
    }

    public func load() throws -> PersistedState? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ state: PersistedState) throws {
        lock.lock(); defer { lock.unlock() }
        stored = state
        saveCount += 1
    }
}
