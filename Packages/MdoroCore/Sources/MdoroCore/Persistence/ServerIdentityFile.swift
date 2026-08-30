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

    // What is on file, or a new one — and, separately, whether the next launch will see the same
    // answer. **An identity that could not be kept is not an identity**, so the caller is given
    // the failure rather than left to assume it worked (REQ-ERR-010 / Decision 0035).
    public enum Outcome: Equatable, Sendable {
        // The id to go on the air with. `couldNotKeep` is non-nil when it will not be read back
        // next launch — it is still this launch's id, and the caller is told.
        case identified(ServerID, couldNotKeep: ErrorCode?)
        // REQ-COM-003 (v2.26): **the file was not handed over.** An id may be sitting in it,
        // intact and unread, so there is no id here — and none is made in its place.
        case unreadable(ErrorCode)

        // This launch's id, or nil when there is none to go on the air with.
        public var id: ServerID? {
            if case let .identified(id, _) = self { id } else { nil }
        }

        // What went wrong, or nil when nothing did.
        public var problem: ErrorCode? {
            switch self {
            case let .identified(_, couldNotKeep): couldNotKeep
            case let .unreadable(code): code
            }
        }

        // REQ-ERR-010 / Decision 0034: `case(domain:code)`, the one shape every failure is
        // written in. The two cases are named apart because the app does different things with
        // them — one goes on the air and one does not.
        public var diagnosticSummary: String? {
            switch self {
            case let .identified(_, couldNotKeep): couldNotKeep?.summary("notKept")
            case let .unreadable(code): code.summary("unreadable")
            }
        }
    }

    private struct Stored: Codable {
        let id: ServerID
    }

    public func loadOrCreate() -> Outcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let made = create()
            return .identified(made.id, couldNotKeep: made.couldNotKeep)
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
            let made = create()
            return .identified(made.id, couldNotKeep: made.couldNotKeep ?? .identityUnreadable)
        }
        return .identified(stored.id, couldNotKeep: nil)
    }

    private func create() -> (id: ServerID, couldNotKeep: ErrorCode?) {
        let id = ServerID.generate()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Stored(id: id)).write(to: fileURL, options: .atomic)
            return (id, nil)
        } catch {
            // The Mac still advertises, and pairing still works for as long as this process
            // lives. It is next launch that will look like a different Mac.
            return (id, ErrorCode(error))
        }
    }
}
