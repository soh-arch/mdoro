import Foundation

// REQ-LOG-004 / REQ-PLT-004 / Decision 0042: the temporary file an atomic log write goes through —
// **how it is named, how it is recognised, and how the ones left behind are cleared.**
//
// The three live together on purpose. Decision 0042 asks that the side making the name and the side
// recognising it be derived from one place, because written apart they drift, and **whichever half
// drifts is the half nobody runs.** A recogniser that has fallen behind either stops matching, and
// the leftovers pile up in the user's folder, which is what Decision 0042 is about — or starts
// matching something else, and a file of the user's is deleted, which is worse.
//
// The name is `.<log file name>.<UUID>.tmp`, and `isLeftoverName` is the exact inverse of it.
public enum LogTemporaryFile {

    // A leading dot keeps it out of the file lists of Markdown editors. It does not hide it from
    // Finder or `ls`, which is the whole reason Decision 0042 exists.
    private static let prefix = "."
    private static let suffix = ".tmp"

    // The name a write stages its contents under, beside the log file it is about to replace.
    // `id` is a parameter only so that a test can name a leftover the way a write would.
    static func name(forLogFileNamed logFileName: String, id: UUID = UUID()) -> String {
        "\(prefix)\(logFileName).\(id.uuidString)\(suffix)"
    }

    // Decision 0042: **whether this name is one that this version made, and nothing else.**
    //
    // This runs inside the user's own folder, so the four conditions are all required, and a name
    // that fails any one of them is left alone:
    //
    // 1. it begins with `.`
    // 2. what follows is the log file name **in use right now** — an orphan from a differently
    //    named log file is somebody else's business, not this run's
    // 3. what follows that reads as a UUID — this is what keeps a name a person chose, such as
    //    `.MdoroLog.md.backup.tmp`, out of it
    // 4. it ends with `.tmp`
    //
    // `Task.md` and `MdoroLog.md` fail at the first condition and can never reach the rest.
    public static func isLeftoverName(_ name: String, forLogFileNamed logFileName: String) -> Bool {
        // A log file name that is empty, or that is a path rather than a name, never produced a
        // name here; matching against one would widen the pattern instead of narrowing it.
        guard !logFileName.isEmpty, !logFileName.contains("/") else { return false }

        let head = prefix + logFileName + "."
        guard name.hasPrefix(head), name.hasSuffix(suffix) else { return false }

        // Both indices are within bounds: the two checks above guarantee the length of each end.
        let idStart = name.index(name.startIndex, offsetBy: head.count)
        let idEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        // The two ends may overlap — `.MdoroLog.md.tmp` satisfies both of them with nothing left
        // in between — and there is no UUID in that.
        guard idStart <= idEnd else { return false }

        return UUID(uuidString: String(name[idStart..<idEnd])) != nil
    }

    // What a sweep did. **The counts are carried out so that the failure is not silent** — Decision
    // 0018 allows a number in the diagnostic log and nothing that came from the user, and Decision
    // 0042 says a sweep that failed stops neither the app nor the recording.
    public struct Sweep: Equatable, Sendable {
        public let removed: Int
        public let failed: Int

        public init(removed: Int, failed: Int) {
            self.removed = removed
            self.failed = failed
        }

        public var isEmpty: Bool { removed == 0 && failed == 0 }
    }

    // Decision 0042: clear the temporary files this version left in the log folder.
    //
    // **Nothing here throws.** A folder that cannot be listed and a file that cannot be removed are
    // both reported as numbers and otherwise passed over: tidying up comes after recording, and a
    // launch is not worth failing over a file that was going to be ignored anyway.
    //
    // The caller is responsible for the folder being reachable — under the sandbox that means
    // holding security-scoped access to it for the duration of this call (REQ-PLT-005).
    @discardableResult
    public static func removeLeftovers(inDirectory directory: URL, logFileName: String) -> Sweep {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return Sweep(removed: 0, failed: 0)
        }

        var removed = 0
        var failed = 0
        for name in names where isLeftoverName(name, forLogFileNamed: logFileName) {
            let url = directory.appendingPathComponent(name)
            // A write only ever makes a file. **A directory wearing the name is not ours**, and
            // `removeItem` would take everything inside it with no way back.
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                failed += 1
            }
        }
        return Sweep(removed: removed, failed: failed)
    }
}
