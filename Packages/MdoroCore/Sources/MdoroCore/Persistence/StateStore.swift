import Foundation

// REQ-ERR-017 / Decision 0036: **a file that cannot be read is never written over.** The
// caller moves it aside first (`setAsideUnreadableState`), then starts from a clean state and
// names on screen where the old one went. Nothing here asks the user to move a file by hand:
// waiting for that would mean either saving nothing all day or overwriting after all.
// When the move itself fails, saving stops rather than taking the file with it.
public enum StateStoreError: Error, Equatable, Sendable {
    // 読めたが解釈できない。
    case corrupted
    // このビルドより新しいスキーマ。ダウングレード時に読み書きして壊さないための防壁。
    case unsupportedSchemaVersion(found: Int, supported: Int)
    // REQ-ERR-010 / Decision 0034: a domain and a code, never the words the OS chose.
    case ioFailed(ErrorCode)
    // REQ-ERR-017 / Decision 0036: 読めないファイルを退避できなかった。**上書きはしない。**
    case couldNotSetAside(ErrorCode)
}

extension StateStoreError: ReportableError {

    public var errorCode: ErrorCode {
        switch self {
        case .corrupted: .stateCorrupted
        case .unsupportedSchemaVersion: .stateUnsupportedSchemaVersion
        case let .ioFailed(code): code
        case let .couldNotSetAside(code): code
        }
    }

    public var diagnosticSummary: String { errorCode.summary(caseName) }

    private var caseName: String {
        switch self {
        case .corrupted: "corrupted"
        case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
        case .ioFailed: "ioFailed"
        case .couldNotSetAside: "couldNotSetAside"
        }
    }

    // REQ-UIX-038 / Decision 0034: fixed English per case.
    // Decision 0036: the file is never overwritten, so these say what became of it. The
    // sentence carries no location — the name is stamped with the time it was made, so the
    // screen that shows this puts the path beside it.
    public var displayMessage: String {
        switch self {
        case .corrupted:
            "The saved state could not be read. Mdoro moved the file aside and started from a clean state."
        case .unsupportedSchemaVersion:
            "The saved state was written by a newer version of Mdoro. Mdoro moved the file aside and started from a clean state; update Mdoro to open it again."
        case .ioFailed:
            "The saved state could not be read or written. Check that Mdoro's Application Support folder is available."
        case .couldNotSetAside:
            "The saved state could not be read, and Mdoro could not move the unreadable file aside. Nothing is being saved, so the file is left as it is."
        }
    }
}

// REQ-PER-001 / 002: 永続化と復元の窓口。実体の差し替えでテストできるようにする。
public protocol StateStore: Sendable {
    // 保存が存在しない場合は nil を返す。壊れている場合は throw する（nil と区別する）。
    func load() throws -> PersistedState?
    func save(_ state: PersistedState) throws

    // REQ-ERR-017 / Decision 0036: move the unreadable state out of the way, under a name that
    // says when it was set aside, and answer where it went. Returns nil when there was nothing
    // to move. Throwing means the file is still there and must not be written over.
    // A protocol requirement rather than an extension: `AppModel` holds `any StateStore`, and a
    // store that keeps a file has to be able to replace this.
    func setAsideUnreadableState() throws -> URL?
}

public extension StateStore {
    // A store that keeps nothing on disk has nothing to lose, and nothing to move.
    func setAsideUnreadableState() throws -> URL? { nil }

    // REQ-PER-002 / 003: 読み込みと復元判定をまとめた起動時の入り口。
    // 保存が無ければ初期状態、あれば REQ-PER-003 の判定を通した状態を返す。
    func loadAndRestore(now: Date, settings: AppSettings = .default) throws -> TimerEngine.Reduction {
        StateRestoration.reduction(from: try load(), now: now, settings: settings)
    }
}

// REQ-ERR-017 / Decision 0035 / 0036: what a launch found, and what it is allowed to do next.
//
// The read and the answer to a failed read are one procedure, not two, because the wrong order
// destroys the file: restoring first and saving afterwards writes a clean state over the very
// bytes the screen is about to tell the reader to go and find.
// `Reduction` は Sendable ではない。起動時に main actor 上でしか作らないので、それでよい。
public struct StateStartup {
    // 読めた保存。読めなかった場合と、保存が無かった場合はどちらも nil。
    public let saved: PersistedState?
    public let reduction: TimerEngine.Reduction
    // 読めなかった理由。nil なら読めた（あるいは保存が無かった）。
    public let readFailure: StateStoreError?
    // 退避できなかった理由。**nil でない間は保存してはならない。**
    public let setAsideFailure: StateStoreError?
    // 退避先。取りに行ける場所として画面に出す。
    public let setAsideAt: URL?

    // Decision 0036: 退避できなかったファイルの上には書かない。
    public var mayPersist: Bool { setAsideFailure == nil }

    // 画面に出す1文。退避できなかったのなら、退避したと書いてある文は出せない。
    public var displayMessage: String? { (setAsideFailure ?? readFailure)?.displayMessage }
}

public extension StateStore {
    // REQ-PER-002 / 003 / REQ-ERR-017: 起動時の読み込み。**失敗したときに何をするかまで含む。**
    func loadForStartup(now: Date, settings: AppSettings = .default) -> StateStartup {
        var saved: PersistedState?
        var readFailure: StateStoreError?
        do {
            saved = try load()
        } catch let error as StateStoreError {
            readFailure = error
        } catch {
            readFailure = .ioFailed(ErrorCode(error))
        }

        // Decision 0036: 読めなかったファイルは、続行する前に退避する。
        var setAsideAt: URL?
        var setAsideFailure: StateStoreError?
        if readFailure != nil {
            do {
                setAsideAt = try setAsideUnreadableState()
            } catch let error as StateStoreError {
                setAsideFailure = error
            } catch {
                setAsideFailure = .couldNotSetAside(ErrorCode(error))
            }
        }

        return StateStartup(
            saved: saved,
            reduction: StateRestoration.reduction(from: saved, now: now, settings: settings),
            readFailure: readFailure,
            setAsideFailure: setAsideFailure,
            setAsideAt: setAsideAt
        )
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
