import Foundation

// REQ-COM-003 / Decision 0040: the Mac's `id` is made once and then never again.
//
// **It is kept beside `state.json`, not inside it.** Decision 0036 has `state.json` set aside
// whole when it cannot be read, and the app carries on from defaults — correct for a timer that
// can start again, and fatal for an identity: every iPhone paired with this Mac would go quiet
// at once, with nothing on either screen to say why. The state file is also rewritten on every
// change, and this is written once in the life of the install, so the file that is touched
// constantly is not the file that must survive.
//
// It is not a secret — it goes out in a TXT record to anyone on the LAN — so it needs no
// Keychain. The tokens do, and they are elsewhere.
public struct ServerIdentityFile: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // The same container as `state.json`. The sandbox resolves it inside the container, so no
    // bookmark is needed.
    public static func inApplicationSupport(
        directoryName: String = "Mdoro",
        fileName: String = "identity.json"
    ) throws -> ServerIdentityFile {
        let fileManager = FileManager.default
        do {
            let base = try fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = base.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return ServerIdentityFile(fileURL: directory.appendingPathComponent(fileName))
        } catch {
            throw StateStoreError.ioFailed(ErrorCode(error))
        }
    }

    // What is on file, or a new one — and whether the next launch will see the same answer.
    //
    // REQ-COM-003 (v2.27): **an id that could not be written down is not handed out at all.**
    // Handing it out with a warning attached is not enough — a warning is a thing a call site can
    // ignore, and the Mac then advertises, pairs, and finds the id gone at the next launch, with
    // every pairing made under it orphaned. Only the two cases that carry an id can reach the air,
    // so forgetting to check is not a way to advertise one.
    public enum Outcome: Equatable, Sendable {
        // On file, and it will be there next launch too.
        case identified(ServerID)
        // The file was handed over and nothing usable was in it, so a fresh id was written over
        // it (the one case that writes over what is on disk). This launch advertises — broken is
        // not unreadable — but the caller is told, because the pairings filed under whatever the
        // file used to say are not coming back.
        case replaced(ServerID)
        // REQ-COM-003 (v2.26): **the file was not handed over.** An id may be sitting in it,
        // intact and unread, so there is no id here — and none is made in its place.
        case unreadable(ErrorCode)
        // REQ-COM-003 (v2.27): **made, and then not kept — the write failed.** The id is not in
        // here on purpose: it would be gone at the next launch, so every pairing made under it
        // would be an orphan, and the only safe thing to do with it is nothing.
        case notKept(ErrorCode)

        // This launch's id, or nil because this Mac must stay off the air.
        public var id: ServerID? {
            switch self {
            case let .identified(id): id
            case let .replaced(id): id
            case .unreadable, .notKept: nil
            }
        }

        // What went wrong, or nil when nothing did.
        public var problem: ErrorCode? {
            switch self {
            case .identified: nil
            case .replaced: .identityUnreadable
            case let .unreadable(code): code
            case let .notKept(code): code
            }
        }

        // REQ-ERR-010 / Decision 0034: `case(domain:code)`, the one shape every failure is
        // written in. The cases are named apart because the app does different things with
        // them — two go on the air and two do not.
        public var diagnosticSummary: String? {
            switch self {
            case .identified: nil
            case .replaced: ErrorCode.identityUnreadable.summary("replaced")
            case let .unreadable(code): code.summary("unreadable")
            case let .notKept(code): code.summary("notKept")
            }
        }
    }

    private struct Stored: Codable {
        let id: ServerID
    }

    public func loadOrCreate() -> Outcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return create(replacing: false)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // **The file is left exactly as it is, and no id is made to stand in for it.**
            // REQ-COM-003 (v2.26): a read that failed once may well succeed next launch, so
            // writing over it here would turn a passing fault into every pairing lost — and
            // going on the air under an invented id does the same damage from the other side.
            // The Mac would be one nobody has heard of: every paired iPhone asked for a six-digit
            // code, and the token issued in reply filed under an id that is gone at the next
            // launch. Orphans on both ends. **Not being able to read it is not the same as
            // there being nothing to read** (the discipline REQ-ERR-017 already applies to
            // `state.json`), so the caller is told which of the two this is.
            return .unreadable(ErrorCode(error))
        }

        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            // Nothing readable is in there to lose, and leaving it would regenerate on every
            // launch. This is the one case that writes over what is already on disk.
            return create(replacing: true)
        }
        return .identified(stored.id)
    }

    private func create(replacing: Bool) -> Outcome {
        let id = ServerID.generate()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Stored(id: id)).write(to: fileURL, options: .atomic)
            return replacing ? .replaced(id) : .identified(id)
        } catch {
            // REQ-COM-003 (v2.27): the id made here is dropped, not returned. It would not be
            // read back next launch, so anything paired under it would be orphaned then.
            return .notKept(ErrorCode(error))
        }
    }
}
