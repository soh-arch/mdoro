import Testing
import Foundation
@testable import MdoroCore

// Decision 0042: the temporary files an atomic log write goes through are cleared at the next
// launch, because the run that left one behind is no longer around to do it.
//
// **These tests exist for the deletions that must not happen.** The code under them runs inside a
// folder of the user's — their vault, their notes, whatever they chose — and removes files from it.
// A pattern that
// is one condition short takes the user's notes with it. So the sweep is asserted twice over: once
// for what it clears, and once, at greater length, for everything standing next to it that it must
// walk past. `Task.md` is the first principle (`CLAUDE.md`), and `MdoroLog.md` is the record the
// whole app exists to keep.

private let logFileName = "MdoroLog.md"

private func temporaryDirectory() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroLeftovers-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func write(_ name: String, in directory: URL, contents: String = "x") -> URL {
    let url = directory.appendingPathComponent(name)
    try? Data(contents.utf8).write(to: url)
    return url
}

private func names(in directory: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
}

@Suite("Recognising a temporary file of ours (Decision 0042)")
struct LogTemporaryFileNameTests {

    // Decision 0042: "the side that makes the name and the side that recognises it are derived from
    // one place". **This is that sentence as a test** — it fails the moment either half moves.
    @Test func everyNameAWriteMakesIsRecognisedAsOne() {
        for _ in 0 ..< 100 {
            let name = LogTemporaryFile.name(forLogFileNamed: logFileName)
            #expect(LogTemporaryFile.isLeftoverName(name, forLogFileNamed: logFileName),
                    "a name this version makes must be one this version clears: \(name)")
        }
    }

    // **The files that must never match.** Each of these sits in the folder the sweep runs in.
    @Test func theFilesThatBelongToTheUserAreNeverLeftovers() {
        let id = UUID().uuidString
        let safe = [
            // The first principle: the task file is never written to and never removed.
            "Task.md",
            ".Task.md",
            ".Task.md.\(id).tmp",   // the task file is not the log file, whatever it is called
            // The record itself.
            logFileName,
            ".\(logFileName)",
            "\(logFileName).tmp",
            // A name a person chose. This is why Decision 0042 asks for the UUID at all.
            ".\(logFileName).backup.tmp",
            ".\(logFileName).1.tmp",
            ".\(logFileName).old.tmp",
            "\(logFileName).backup",
            // Ordinary notes, and the dotfiles that live in a vault.
            "Daily.md",
            ".obsidian",
            ".DS_Store",
            ".gitignore",
            "\(logFileName).\(id).tmp",     // no leading dot
            ".\(logFileName).\(id).tmp.md", // does not end there
            ".\(logFileName).\(id)",        // no suffix
        ]
        for name in safe {
            #expect(!LogTemporaryFile.isLeftoverName(name, forLogFileNamed: logFileName),
                    "this is not ours to delete: \(name)")
        }
    }

    // Decision 0042: the middle has to read as a UUID, or a name somebody typed gets swept up.
    @Test func whatIsNotAUUIDInTheMiddleIsNotOne() {
        let id = UUID()
        let notUUIDs = [
            "",                                         // .MdoroLog.md..tmp
            "not-a-uuid",
            id.uuidString.replacingOccurrences(of: "-", with: ""),  // the hex without the dashes
            String(id.uuidString.dropLast()),                       // one character short
            id.uuidString + "0",                                    // one character long
            "{\(id.uuidString)}",
            "\(id.uuidString).\(UUID().uuidString)",
            "GGGGGGGG-GGGG-GGGG-GGGG-GGGGGGGGGGGG",                 // the shape, not the alphabet
        ]
        for middle in notUUIDs {
            let name = ".\(logFileName).\(middle).tmp"
            #expect(!LogTemporaryFile.isLeftoverName(name, forLogFileNamed: logFileName),
                    "the middle of this is not a UUID: \(name)")
        }
        // And with nothing at all where the middle goes, the two ends overlap.
        #expect(!LogTemporaryFile.isLeftoverName(".\(logFileName).tmp", forLogFileNamed: logFileName))
    }

    // Decision 0042: the log file name it has to match is **the one in use right now.** An orphan
    // from a name the user has since changed belongs to no run this app can account for.
    @Test func anOrphanOfADifferentLogFileNameIsLeftAlone() {
        let id = UUID().uuidString
        #expect(!LogTemporaryFile.isLeftoverName(".OtherLog.md.\(id).tmp", forLogFileNamed: logFileName))
        #expect(!LogTemporaryFile.isLeftoverName(".Mdoro.md.\(id).tmp", forLogFileNamed: logFileName))
        // A prefix of the name in use is not the name in use.
        #expect(!LogTemporaryFile.isLeftoverName(".MdoroLog.\(id).tmp", forLogFileNamed: logFileName))
        // Nor is the name in use with something in front of it.
        #expect(!LogTemporaryFile.isLeftoverName(".My\(logFileName).\(id).tmp", forLogFileNamed: logFileName))
        // The one it does belong to still matches.
        #expect(LogTemporaryFile.isLeftoverName(".OtherLog.md.\(id).tmp", forLogFileNamed: "OtherLog.md"))
    }

    // A log file name this app would never hold. `AppSettings.isValidLogFileName` refuses an empty
    // name, a leading dot and a slash — but the sweep is given a stored value, and **a pattern
    // built out of a bad one matches more than it should, not less.** So it matches nothing.
    @Test func aLogFileNameThatCouldNotHaveMadeAnythingMatchesNothing() {
        let id = UUID().uuidString
        #expect(!LogTemporaryFile.isLeftoverName("..\(id).tmp", forLogFileNamed: ""))
        #expect(!LogTemporaryFile.isLeftoverName(".\(id).tmp", forLogFileNamed: ""))
        #expect(!LogTemporaryFile.isLeftoverName(".notes/\(logFileName).\(id).tmp",
                                                 forLogFileNamed: "notes/\(logFileName)"))
    }
}

@Suite("Clearing what a run left in the log folder (Decision 0042)")
struct LogLeftoverSweepTests {

    // Everything in the folder, and only the two that are ours.
    @Test func onlyOurOwnTemporaryFilesAreRemoved() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ours = [
            LogTemporaryFile.name(forLogFileNamed: logFileName),
            LogTemporaryFile.name(forLogFileNamed: logFileName),
        ]
        let theirs = [
            "Task.md",
            logFileName,
            ".\(logFileName).backup.tmp",
            ".OtherLog.md.\(UUID().uuidString).tmp",
            ".\(logFileName).tmp",
            "Daily.md",
            ".obsidian",
        ]
        for name in ours + theirs { write(name, in: directory) }

        let sweep = LogTemporaryFile.removeLeftovers(inDirectory: directory, logFileName: logFileName)

        #expect(sweep == LogTemporaryFile.Sweep(removed: 2, failed: 0))
        #expect(names(in: directory) == Set(theirs), "nothing but our own two may have gone")
    }

    // REQ-LOG-021 / the first principle, said once more where it is cheapest to say: whatever the
    // task file is called, the sweep does not touch it.
    @Test func theTaskFileAndTheLogSurviveASweepUnderEveryNameTheyTake() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let kept = ["Task.md", "Tasks.md", "Inbox.md", logFileName, "\(logFileName).tmp"]
        for name in kept { write(name, in: directory, contents: "the user's") }

        for name in [logFileName, "Task.md", "Inbox.md"] {
            LogTemporaryFile.removeLeftovers(inDirectory: directory, logFileName: name)
        }

        #expect(names(in: directory) == Set(kept))
        #expect((try? String(contentsOf: directory.appendingPathComponent("Task.md"), encoding: .utf8))
                == "the user's", "the first principle: Task.md is neither written nor removed")
    }

    // A write only ever makes a file. Something else made this, whatever it is named.
    @Test func aDirectoryWearingTheNameIsLeftWhereItIs() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let impostor = directory.appendingPathComponent(LogTemporaryFile.name(forLogFileNamed: logFileName))
        try? FileManager.default.createDirectory(at: impostor, withIntermediateDirectories: true)
        write("keep.md", in: impostor, contents: "not to be swept away")

        let sweep = LogTemporaryFile.removeLeftovers(inDirectory: directory, logFileName: logFileName)

        #expect(sweep.removed == 0)
        #expect(FileManager.default.fileExists(atPath: impostor.appendingPathComponent("keep.md").path))
    }

    // Decision 0042: tidying up stops nothing. A folder that is not there reports no failure
    // because nothing was attempted — the write that follows is what reports a folder gone away.
    @Test func aFolderThatIsNotThereIsNotAFailure() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let sweep = LogTemporaryFile.removeLeftovers(inDirectory: missing, logFileName: logFileName)

        #expect(sweep.isEmpty)
    }

    // The normal path leaves nothing to sweep: this is what makes a leftover evidence of a run that
    // ended badly, rather than an ordinary state of the folder.
    @Test func anOrdinaryWriteLeavesNothingBehind() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(logFileName)
        let writer = LogWriter(fileURL: url)
        let day = Date()

        for _ in 0 ..< 3 {
            try writer.append(LogEntry(
                sessionType: .work, startedAt: day, endedAt: day.addingTimeInterval(1500),
                elapsedSeconds: 1500, outcome: .completed, presetName: "Standard",
                presetEditedDuringSession: false, taskSnapshot: nil, extendedSeconds: 0,
                loopCountAfterCompletion: 1, longBreakInterval: 4, logicalDate: day
            ))
        }

        #expect(names(in: directory) == [logFileName])
        #expect(LogTemporaryFile.removeLeftovers(inDirectory: directory, logFileName: logFileName).isEmpty)
    }

    // The sweep runs before the first write of a launch, so what it leaves has to still be writable.
    @Test func aSweepDoesNotDisturbTheLogItRanBeside() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(logFileName)
        try Data("## 2026-09-14 (Mon)\n\n- kept\n".utf8).write(to: url)
        write(LogTemporaryFile.name(forLogFileNamed: logFileName), in: directory, contents: "half a write")

        let sweep = LogTemporaryFile.removeLeftovers(inDirectory: directory, logFileName: logFileName)
        try LogWriter(fileURL: url).append(LogEntry(
            sessionType: .work, startedAt: Date(), endedAt: Date(), elapsedSeconds: 1500,
            outcome: .completed, presetName: "Standard", presetEditedDuringSession: false,
            taskSnapshot: nil, extendedSeconds: 0, loopCountAfterCompletion: 1,
            longBreakInterval: 4, logicalDate: Date()
        ))

        #expect(sweep.removed == 1)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("- kept"), "REQ-LOG-003: the line that was already there stays")
        #expect(names(in: directory) == [logFileName])
    }
}

// **When the files disappear is the one part of this the user can see**, so Decision 0042 fixed it:
// at launch, and nowhere else. `AppModel` is in the Mac target and cannot be imported here, so this
// reads the source, the way `StartingTwiceTests` does.
@Suite("The sweep happens at launch and nowhere else (Decision 0042)")
struct LogSweepWiringTests {

    private static let appModelPath = "PomodoroMac/PomodoroMac/AppModel.swift"
    private static let call = "removeLeftoverLogTemporaryFiles()"

    @Test func startClearsTheLastRunsLeftoversBeforeThisRunWritesAnything() throws {
        let body = withoutComments(try source(Self.appModelPath))
        let start = try #require(body.range(of: "func start() {"),
                                 "\(Self.appModelPath) no longer has start()")
        let rest = body[start.upperBound...]

        let sweep = try #require(
            rest.range(of: Self.call),
            "Decision 0042: start() no longer clears what an earlier run left in the reader's folder"
        )
        let flush = try #require(rest.range(of: "flushLogQueue()"),
                                 "\(Self.appModelPath) no longer flushes the log queue at launch")
        #expect(
            sweep.lowerBound < flush.lowerBound,
            "Decision 0042: the sweep runs after this launch has already staged temporary files of its own"
        )
    }

    // A sweep on a timer, or one on every write, would take files away at moments the reader has no
    // account of — and would meet a temporary file a write of ours is in the middle of using.
    @Test func nothingButTheLaunchAsksForASweep() throws {
        for (name, text) in try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true)
        where name != "AppModel.swift" {
            #expect(!text.contains(Self.call),
                    "Decision 0042: \(name) sweeps the reader's folder somewhere other than at launch")
        }
    }
}
