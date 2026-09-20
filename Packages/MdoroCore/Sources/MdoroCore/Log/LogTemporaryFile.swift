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

    // Decision 0042 / `docs/CONTEXT.md` §2: **how many launches in a row the sweep left something
    // behind**, and whether the user has been told about the run standing now.
    //
    // 0042 keeps the sweep off the screen for a single failure, and that reasoning holds: the user
    // asked for none of this tidying, and a folder that has really gone away is reported by the
    // write that follows the sweep. **What it does not cover is a failure that never goes away** —
    // one file whose owner or permissions are not what they were, refused every launch while every
    // write succeeds. `CONTEXT.md` §2 asks that an operation touching the outside world fail where
    // it can be seen, and a line in a diagnostic log nobody opens is not that place. Left as it
    // was, everything 0042 promises quietly stops being true.
    //
    // So this takes the balance REQ-ERR-004 / Decision 0039 already strike for a failed write and
    // applies it here: **say it once the failure has held, and then not again until it clears.**
    // The threshold is three because three is the number the write side uses
    // (`LogWriteQueue.failureThreshold`); nothing about this failure argues for a different one.
    //
    // ⚠ **The two threes do not measure the same thing, and being equal hides it.** A write is
    // attempted whenever a session is recorded, so three of them are minutes or hours apart. **The
    // sweep runs once per launch** and nowhere else (`AppModel.start()`), so three of these are
    // three launches of the app — which for someone who leaves it running is days. That is
    // deliberate, and it is the slow end of the scale on purpose: what this reports is a file that
    // will not go away on its own, and nothing about it is urgent. It is **not** a way of saying
    // "three failures" in the sense REQ-ERR-004 says it.
    public struct FailureRun: Equatable, Sendable, Codable {
        // Decision 0042: three launches, matching `LogWriteQueue.failureThreshold`. Held here
        // rather than read from there, because the two are free to move apart — one counts write
        // attempts and this one counts launches.
        public static let launchThreshold = 3

        // Launches in a row whose sweep could not remove something. **This has to be persisted**
        // (REQ-PER-001): the sweep runs once per launch, so a count living in this process could
        // never reach two.
        public var launches: Int
        // Whether the run standing now has already been reported. Persisted for the same reason —
        // without it the fourth launch, and every launch after it, would report the same trouble
        // again.
        public var didNotify: Bool

        public init(launches: Int = 0, didNotify: Bool = false) {
            self.launches = launches
            self.didNotify = didNotify
        }

        // REQ-PER-002: a state file saved before this existed reads as no run at all, the way every
        // other added field does. A count below zero could only come from a file edited by hand,
        // and reading it as written would park the run under the threshold for good.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let saved = try c.decodeIfPresent(Int.self, forKey: .launches) ?? 0
            launches = max(0, saved)
            didNotify = try c.decodeIfPresent(Bool.self, forKey: .didNotify) ?? false
        }

        // Take in what one sweep did, and answer whether **this launch** is the one that says so.
        //
        // A sweep that failed at nothing ends the run, **including one that found nothing to do**:
        // a file that cannot be removed is listed and refused again, so nothing failing means
        // nothing is stuck.
        //
        // ⚠ **A sweep that never ran must not be handed to this at all.** With no folder chosen, or
        // the folder out of reach, there is no answer either way — and calling it would clear the
        // launches before it, which is how a folder that comes and goes would keep the run from ever
        // reaching three. The caller decides (`AppModel.removeLeftoverLogTemporaryFiles`); an
        // unreachable folder is already reported by the write that follows it.
        @discardableResult
        public mutating func record(_ sweep: Sweep) -> Bool {
            guard sweep.failed > 0 else {
                self = FailureRun()
                return false
            }
            launches += 1
            let reachedThreshold = launches >= Self.launchThreshold
            // Saying it once is enough while the same trouble stands. A sweep that fails at
            // nothing is what arms this again, through the reset above.
            let shouldNotify = reachedThreshold && !didNotify
            didNotify = reachedThreshold
            return shouldNotify
        }
    }
}
