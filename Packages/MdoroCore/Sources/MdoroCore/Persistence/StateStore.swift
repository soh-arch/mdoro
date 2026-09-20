import Foundation

// REQ-ERR-017 / Decision 0036: **a file that cannot be read is never written over.** The
// caller moves it aside first (`setAsideUnreadableState`), then starts from a clean state and
// names on screen where the old one went. Nothing here asks the user to move a file by hand:
// waiting for that would mean either saving nothing all day or overwriting after all.
// When the move itself fails, saving stops rather than taking the file with it.
public enum StateStoreError: Error, Equatable, Sendable {
    // It could be read, but not understood.
    case corrupted
    // A schema newer than this build. The barrier that stops a downgrade reading and writing it into ruin.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    // REQ-ERR-010 / Decision 0034: a domain and a code, never the words the OS chose.
    case ioFailed(ErrorCode)
    // REQ-ERR-017 / Decision 0036: the unreadable file could not be set aside. **It is not overwritten.**
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

    // Decision 0036: **failing to read a file is not the same as the file being broken.**
    // Only content that cannot be understood is set aside. Moving a file the disk merely failed to
    // answer for would **push sound data away under another name.** The switch is exhaustive, so a
    // new case cannot compile until someone decides which side it falls on.
    var meansTheContentIsUnusable: Bool {
        switch self {
        case .corrupted, .unsupportedSchemaVersion: true
        case .ioFailed, .couldNotSetAside: false
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

// REQ-PER-001 / 002: the way in to persistence and restore. The implementation swaps out, so it can be tested.
public protocol StateStore: Sendable {
    // Returns nil when nothing was saved. A broken file throws, which is not the same as nil.
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

    // REQ-PER-002 / 003: the launch entry point, reading and deciding the restore in one call.
    // With nothing saved it returns the initial state, otherwise the state after the REQ-PER-003 decision.
    func loadAndRestore(now: Date, settings: AppSettings = .default) throws -> TimerEngine.Reduction {
        StateRestoration.reduction(from: try load(), now: now, settings: settings)
    }
}

// REQ-ERR-017 / Decision 0035 / 0036: what a launch found, and what it is allowed to do next.
//
// The read and the answer to a failed read are one procedure, not two, because the wrong order
// destroys the file: restoring first and saving afterwards writes a clean state over the very
// bytes the screen is about to tell the reader to go and find.
// `Reduction` is not Sendable. It is only ever built on the main actor at launch, so that is fine.
public struct StateStartup {
    // The saved state, when it read. Both a failed read and no saved file leave this nil.
    //
    // ⚠ **`saved.settings` is what this launch reads the file as, which is not always what the file
    // holds**: REQ-CFG-018 / 9.3 puts a value outside its range back to its default on the way in,
    // and `settingsReset` below names each one that happened to. Nothing else here is altered.
    public let saved: PersistedState?
    public let reduction: TimerEngine.Reduction
    // REQ-CFG-018 / REQ-PER-002 / 9.3: which of the saved settings was outside its range and has
    // been put back to its default. Empty for a file that held up, for a launch with nothing saved,
    // and for a read that failed.
    //
    // **It is separate from `saved` because `saved` no longer shows it.** The repaired value is
    // indistinguishable from one the reader chose, and the launch saves over the file it came from,
    // so this list is the only thing left that says a setting moved (REQ-ERR-017's shape: a launch
    // may not quietly lose what the reader set).
    public let settingsReset: [AppSettings.RangedField]
    // Why the read failed. nil means it read — or that there was nothing saved.
    public let readFailure: StateStoreError?
    // Why setting aside failed. **While this is not nil, nothing may be saved.**
    public let setAsideFailure: StateStoreError?
    // Where it went. Shown on screen as a place the reader can go and fetch it.
    public let setAsideAt: URL?

    // Decision 0036: what is holding saving back. **Not setting a file aside is not permission to
    // overwrite it** — a file the I/O never answered for is left where it is, and not written over
    // either. This is nil only when the read succeeded, or when the file has been set aside.
    public var persistBlockedBy: StateStoreError? {
        guard let readFailure else { return nil }
        guard readFailure.meansTheContentIsUnusable else { return readFailure }
        return setAsideFailure
    }

    // Decision 0036: never write over a file that has not been set aside.
    public var mayPersist: Bool { persistBlockedBy == nil }

    // The one sentence for the screen. If setting aside failed, the sentence that says it succeeded cannot be shown.
    public var displayMessage: String? { (setAsideFailure ?? readFailure)?.displayMessage }
}

public extension StateStore {
    // REQ-PER-002 / 003 / REQ-ERR-017: the read at launch. **It includes what to do when that read fails.**
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

        // REQ-CFG-018 / REQ-PER-002 / 9.3: **the ranges hold for a value read back from the file,
        // not only for one the reader has just typed.** Both paths that change a setting in this
        // process ask `isWithinValidRanges()` before applying it, and the read asked nothing at all
        // — so a value written by an older version, or edited by hand in Application Support, was
        // taken exactly as it stood. REQ-LOG-001 is where it told: `logFileName` is half of the path
        // the next session is written to (`AppSettings.logFilePath`), and an empty name, a leading
        // dot or a slash would have gone straight through to it.
        //
        // **Here rather than at the property the caller assigns it to**, because the restore decision
        // reads these same settings a few lines below: REQ-TIM-033 measures the pause this launch
        // found against `idleResetHours`, so a value repaired after this call would already have
        // decided whether a PAUSED session comes back or falls through to PENDING_DECISION.
        //
        // **Nothing is written back from here.** Decision 0036 keeps this read from writing anything;
        // the caller's own save is what puts the repair on disk.
        var settingsReset: [AppSettings.RangedField] = []
        if let savedSettings = saved?.settings {
            let asRead = savedSettings.resettingFieldsOutsideValidRanges()
            saved?.settings = asRead.settings
            settingsReset = asRead.reset
        }

        // Decision 0036: **only a file whose content cannot be read** is set aside before going on.
        var setAsideAt: URL?
        var setAsideFailure: StateStoreError?
        if readFailure?.meansTheContentIsUnusable == true {
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
            // The reduction reads `saved.settings`, which the repair above has already put right.
            reduction: StateRestoration.reduction(from: saved, now: now, settings: settings),
            settingsReset: settingsReset,
            readFailure: readFailure,
            setAsideFailure: setAsideFailure,
            setAsideAt: setAsideAt
        )
    }
}

// REQ-ERR-017 / Decision 0035 / 0036: the one sentence the screen shows about saving.
//
// Three reasons can stand at once, and they do not expire alike: a store that could not be
// made and a file that may not be written over never resolve, while a single failed write is
// gone as soon as one succeeds. **The ones that cannot resolve go first.**
//
// No argument has a default. A caller that leaves one out would compile, and the screen would
// go quiet while saving stayed stopped — which is the whole failure this requirement exists
// to prevent. Making every candidate explicit is what keeps that from being a silent edit.
public enum PersistenceStatus {
    public static func problemMessage(
        storeUnavailable: StateStoreError?,
        persistBlockedBy: StateStoreError?,
        lastSaveFailure: StateStoreError?
    ) -> String? {
        (storeUnavailable ?? persistBlockedBy ?? lastSaveFailure)?.displayMessage
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

// The implementation for tests, and for paths that run without persistence.
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
