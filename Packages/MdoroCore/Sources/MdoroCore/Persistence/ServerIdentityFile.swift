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
    public struct Outcome: Equatable, Sendable {
        public let id: ServerID
        // nil when this id is on disk and will be read back next time.
        public let couldNotKeep: ErrorCode?

        public init(id: ServerID, couldNotKeep: ErrorCode? = nil) {
            self.id = id
            self.couldNotKeep = couldNotKeep
        }
    }

    private struct Stored: Codable {
        let id: ServerID
    }

    public func loadOrCreate() -> Outcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return create()
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // **The file is left exactly as it is.** A read that failed once may well succeed
            // next launch, and overwriting here would turn a passing fault into a permanent
            // one — every paired iPhone unpaired because a read was refused for a moment.
            return Outcome(id: ServerID.generate(), couldNotKeep: ErrorCode(error))
        }

        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            // Nothing readable is in there to lose, and leaving it would regenerate on every
            // launch. This is the one case that writes over what is already on disk.
            let replacement = create()
            return Outcome(id: replacement.id, couldNotKeep: replacement.couldNotKeep ?? .identityUnreadable)
        }
        return Outcome(id: stored.id)
    }

    private func create() -> Outcome {
        let id = ServerID.generate()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Stored(id: id)).write(to: fileURL, options: .atomic)
            return Outcome(id: id)
        } catch {
            // The Mac still advertises, and pairing still works for as long as this process
            // lives. It is next launch that will look like a different Mac.
            return Outcome(id: id, couldNotKeep: ErrorCode(error))
        }
    }
}
