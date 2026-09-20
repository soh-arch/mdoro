import Testing
import Foundation
@testable import MdoroCore

// Decision 0042: the temporary files an atomic log write goes through are cleared at the next
// launch, because the run that left one behind is no longer around to do it.
//
// **These tests exist for the deletions that must not happen.** The code under them runs inside a
// folder of the user's — their vault, their notes, whatever they chose — and removes files from it.
// A pattern one condition short takes their notes with it. So the sweep is asserted twice over:
// once for what it clears, and once, at greater length, for everything standing next to it that it
// must walk past. `Task.md` is the first principle (`CLAUDE.md`), and `MdoroLog.md` is the record
// the whole app exists to keep.

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

// A source scan that matched line by line would go red at a reformat and say nothing about it, so
// the whitespace comes out first and the shapes below are written with none.
private func withoutWhitespace(_ text: String) -> String {
    text.filter { !$0.isWhitespace }
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

// Decision 0042: "the side that makes the name and the side that recognises it are derived from one
// place. Written apart, one of them will change on its own one day." **`everyNameAWriteMakesIsRecognisedAsOne`
// does not see that day arrive.** It asks `LogTemporaryFile.name` itself, so a `LogWriter` that goes
// back to spelling the name inline — which is what it did before Decision 0042 — passes every test
// above while staging files the sweep no longer knows. That is the whole of what 0042 protects, and
// nothing was watching it.
//
// **What this suite guarantees, and what it does not.**
//
// It reads the letters. `LogWriter` cannot spell a temporary name of its own, and it has to name the
// file after the one it is replacing. Nothing in the log sources may carry the pieces a temporary
// name is made of, except the one file that owns them. That is enough to catch the drift 0042 names,
// because drift has to be written down before it can happen.
//
// It is **not** proof that the call is reached, that the staged file is really named that, or that
// the two halves agree — a scan matches text and does not run anything. The agreement is
// `everyNameAWriteMakesIsRecognisedAsOne`, which is a real round trip, and what a launch does with
// it is `LogSweepWiringTests`. **Each of the three is blind where the others look**; none of them
// stands on its own.
//
// What would replace all three is a seam on `LogWriter`'s `FileManager`, so that a write could be
// stopped after staging and the leftover it really made handed to the sweep. **That is a change to
// the type that carries the first principle**, and a larger thing than the sweep it would be
// checking, so it is not taken here.
@Suite("The writer takes its temporary name from the one place (Decision 0042)")
struct LogTemporaryNameHasOneAuthorTests {

    private static let logSources = "Packages/MdoroCore/Sources/MdoroCore/Log"
    private static let owner = "LogTemporaryFile.swift"
    // The pieces a temporary name is made of. Spelled anywhere but in `owner`, they are a second
    // author for the name. `FileStateStore` also stages and swaps, and Decision 0042 leaves it
    // alone on purpose — it writes inside the sandbox container, where the user never looks — so
    // the scan stays inside the log sources rather than going out over the repository.
    // The suffix is looked for bare rather than as a whole literal: written back inline it reads
    // `".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"`, where `".tmp"` never appears.
    private static let piecesOfAName = [".tmp", "uuidString"]

    // The call, as it has to read. Whitespace is already gone from both sides.
    private static let theCall = withoutWhitespace(
        "LogTemporaryFile.name(forLogFileNamed: fileURL.lastPathComponent)"
    )

    @Test func theWriterAsksForTheNameRatherThanSpellingOne() throws {
        let body = withoutWhitespace(withoutComments(try source("\(Self.logSources)/LogWriter.swift")))
        #expect(
            body.contains(Self.theCall),
            """
            Decision 0042: LogWriter no longer stages its temporary file under \
            `LogTemporaryFile.name(forLogFileNamed: fileURL.lastPathComponent)`, so the name it \
            writes and the name the startup sweep looks for are two things now. Whichever one \
            changes next, the other will not — and the two ways that ends are leftovers piling up \
            in the reader's folder, or a file of theirs being deleted.
            """
        )
    }

    @Test func nothingElseInTheLogSourcesKnowsHowToSpellOne() throws {
        let files = try swiftFiles(under: Self.logSources, recursive: true)
        for (name, text) in files where name != Self.owner {
            for piece in Self.piecesOfAName {
                #expect(
                    !withoutWhitespace(text).contains(withoutWhitespace(piece)),
                    "Decision 0042: \(name) carries `\(piece)`, which is a second author for a name that may have only one"
                )
            }
        }
    }

    // **A scan that cannot see is a scan that passes.** The directory moving is already an error
    // (`swiftFiles` throws), so what is left to check is that the two files are in it and that the
    // pieces above are still what a name is spelled out of — otherwise the test above forbids a
    // spelling nobody uses, and says nothing at all.
    @Test func theScanIsLookingAtSomething() throws {
        let files = try swiftFiles(under: Self.logSources, recursive: true)
        #expect(files["LogWriter.swift"] != nil, "\(Self.logSources) no longer holds LogWriter.swift")
        let ownerSource = try #require(files[Self.owner], "\(Self.logSources) no longer holds \(Self.owner)")
        for piece in Self.piecesOfAName {
            #expect(
                withoutWhitespace(ownerSource).contains(withoutWhitespace(piece)),
                "\(Self.owner) no longer spells `\(piece)`, so forbidding it elsewhere forbids nothing"
            )
        }
    }

    // The whitespace has to come out for the shapes above to survive a reformat, and it has to
    // come out of both sides or they never meet.
    @Test func theScanSurvivesAReformat() {
        #expect(withoutWhitespace("a( b :\n    c )") == "a(b:c)")
        #expect(withoutWhitespace("LogTemporaryFile.name(\n  forLogFileNamed: fileURL.lastPathComponent\n)")
                .contains(Self.theCall))
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

    // MARK: - Where the failure goes (Decision 0042 / `docs/CONTEXT.md` §2)

    private static let sweepFunction = "func removeLeftoverLogTemporaryFiles() {"

    // The two halves of `removeLeftoverLogTemporaryFiles`: **the launch that swept, and the launch
    // that could not reach the folder to sweep.** They answer differently, and a scan that read them
    // as one would pass whichever way round they were written.
    private static func sweepParts(of body: String) -> (swept: String, couldNotReach: String)? {
        guard let start = body.range(of: sweepFunction),
              let end = body.range(of: "func flushLogQueue()", range: start.upperBound..<body.endIndex),
              let handler = body.range(of: "} catch {", range: start.upperBound..<end.lowerBound)
        else { return nil }
        return (
            String(body[start.upperBound..<handler.lowerBound]),
            String(body[handler.upperBound..<end.lowerBound])
        )
    }

    // `docs/CONTEXT.md` §2: **an operation that touches the outside world does not fail in silence.**
    // The sweep deletes files in a folder of the reader's, and for one launch a failure stays in the
    // diagnostic log — but a file that is refused at every launch is reported by nothing else at all,
    // because the log itself writes perfectly well. The count has to be saved to be a count of
    // launches, so all three belong to this one path: count it, save it, and say it.
    @Test func aSweepThatKeepsFailingIsCountedSavedAndTold() throws {
        let body = withoutComments(try source(Self.appModelPath))
        let parts = try #require(Self.sweepParts(of: body),
                                 "\(Self.appModelPath) no longer sweeps in a do/catch of its own")

        let counted = try #require(
            parts.swept.range(of: "logSweepFailures.record(sweep)"),
            "Decision 0042 / CONTEXT §2: what the sweep failed at is no longer counted across launches"
        )
        let saved = try #require(
            parts.swept.range(of: "persist()"),
            "the run is not saved, so it can never reach two — the sweep runs once per launch"
        )
        let told = try #require(
            parts.swept.range(of: "notifications.notifyLogSweepFailure()"),
            "CONTEXT §2: a sweep that keeps failing reaches nobody but the diagnostic log again"
        )
        #expect(counted.lowerBound < saved.lowerBound, "what is saved is the run this launch just added to")
        #expect(counted.lowerBound < told.lowerBound, "what is told is decided by the count, not by one sweep")
    }

    // ⚠ **A launch that could not reach the folder swept nothing**, so it neither adds to the run
    // nor clears it. Counting it would report the folder twice over — the write that follows says it
    // already — and clearing it would let a folder that comes and goes wipe out the launches that did
    // fail, so the one file that can never be removed would never reach three.
    @Test func aLaunchThatCouldNotReachTheFolderNeitherCountsNorClears() throws {
        let body = withoutComments(try source(Self.appModelPath))
        let parts = try #require(Self.sweepParts(of: body))

        #expect(!parts.couldNotReach.contains("logSweepFailures"),
                "Decision 0042: a folder out of reach is not a sweep, and must not touch the run")
        #expect(!parts.couldNotReach.contains("notifyLogSweepFailure"),
                "Decision 0042: the write that follows reports a folder gone away; this must not report it too")
    }

    // REQ-PER-001: the run is carried across launches by the state file, and **a launch that does not
    // read it back starts from zero every time**, which is the same as never counting at all.
    @Test func theRunIsReadBackAtLaunchAndSavedWithEverythingElse() throws {
        let body = withoutComments(try source(Self.appModelPath))
        #expect(body.contains("saved?.logSweepFailures"),
                "Decision 0042: the run from the last launches is no longer restored, so it restarts at zero")
        #expect(body.contains("logSweepFailures: logSweepFailures"),
                "Decision 0042: the run is no longer written into the state that is saved")
    }

    // **A scan that cannot see is a scan that passes.** The two above name a notification and a
    // field; if either stops existing under that name, they would go on asking for a call nobody
    // could make and finding nothing to object to in the handler.
    @Test func theScanForTheNotificationIsLookingAtSomething() throws {
        let files = try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true)
        let scheduler = try #require(files["NotificationScheduler.swift"],
                                    "PomodoroMac/PomodoroMac no longer holds NotificationScheduler.swift")
        #expect(scheduler.contains("func notifyLogSweepFailure()"),
                "nothing is named notifyLogSweepFailure any more, so looking for that call looks for nothing")

        let body = withoutComments(try source(Self.appModelPath))
        #expect(body.contains("private var logSweepFailures"),
                "nothing is named logSweepFailures any more, so the checks above check nothing")
        let parts = try #require(Self.sweepParts(of: body))
        #expect(!parts.couldNotReach.isEmpty, "the handler half came out empty, so nothing was examined")
    }
}

// Decision 0042 / `docs/CONTEXT.md` §2: **when the sweep cannot clear something, and that keeps
// happening, the user is told.**
//
// §2 asks that an operation touching the outside world fail somewhere it can be seen. One failed
// sweep is not that — the user asked for none of this tidying, and a folder that has gone away is
// reported by the write that follows. The case nothing else reports is the other one: **a file
// refused every single launch, while the log writes perfectly well.**
//
// The shape is REQ-ERR-004 / Decision 0039's, borrowed: say it once the failure has held for three,
// then not again until it clears. ⚠ **The three is not the same three.** A write is attempted per
// session; the sweep runs once per launch, so this one counts launches — far longer, for the same
// number.

private func failing(_ count: Int = 1) -> LogTemporaryFile.Sweep {
    LogTemporaryFile.Sweep(removed: 0, failed: count)
}

// One launch at a time, as the app does it: the sweep goes in and the answer — whether **this**
// launch is the one that says so — comes out. `record` is mutating, so the run is threaded here
// rather than inside an assertion.
private func launches(
    _ sweeps: [LogTemporaryFile.Sweep],
    from start: LogTemporaryFile.FailureRun = LogTemporaryFile.FailureRun()
) -> (said: [Bool], run: LogTemporaryFile.FailureRun) {
    var run = start
    let said = sweeps.map { run.record($0) }
    return (said, run)
}

@Suite("Saying that the leftovers could not be cleared (Decision 0042)")
struct LogSweepFailureRunTests {

    // One launch is not worth a notification, and neither are two. **The third is.**
    @Test func nothingIsSaidUntilTheFailureHasHeldForThreeLaunches() {
        #expect(LogTemporaryFile.FailureRun().launches == 0, "nothing has failed yet")

        let three = launches([failing(), failing(), failing()])
        #expect(three.said == [false, false, true],
                "Decision 0042 / CONTEXT §2: a failure that has held for three launches is told, and not before")
        #expect(three.run.launches == LogTemporaryFile.FailureRun.launchThreshold)
        #expect(three.run.didNotify)
    }

    // The same trouble is told once. Otherwise every launch from the third on says it again — the
    // reading Decision 0042 turned down ((c) in the ledger), because a notification that arrives at
    // every launch is read a few times and then never again.
    @Test func theSameTroubleIsToldOnce() {
        let ten = launches(Array(repeating: failing(), count: 10))
        #expect(ten.said == [false, false, true, false, false, false, false, false, false, false])
        #expect(ten.run.launches == 10, "it is still counted: the diagnostic log says how long it has held")
    }

    // A sweep that failed at nothing ends the run **and arms it again**. This is the only way back,
    // and without it one stretch of trouble would silence the next one for good.
    @Test func aSweepThatFailedAtNothingEndsTheRunAndArmsItAgain() {
        let told = launches([failing(), failing(), failing()])
        #expect(told.run.didNotify)

        let cleared = launches([LogTemporaryFile.Sweep(removed: 1, failed: 0)], from: told.run)
        #expect(cleared.said == [false])
        #expect(cleared.run == LogTemporaryFile.FailureRun(), "the run is over, and nothing is outstanding")

        let again = launches([failing(), failing(), failing()], from: cleared.run)
        #expect(again.said == [false, false, true], "trouble that starts again after it cleared is told again")
    }

    // A sweep with nothing to do ends it too. **A file that cannot be removed is listed and refused
    // again**, so a sweep that failed at nothing means nothing is stuck — whether it cleared
    // something, or found the folder with nothing of ours in it at all.
    @Test func everySweepThatFailedAtNothingEndsTheRunWhateverElseItDid() {
        let clean = [
            LogTemporaryFile.Sweep(removed: 0, failed: 0),
            LogTemporaryFile.Sweep(removed: 1, failed: 0),
            LogTemporaryFile.Sweep(removed: 9, failed: 0),
        ]
        for sweep in clean {
            let result = launches([sweep], from: LogTemporaryFile.FailureRun(launches: 2))
            #expect(result.said == [false])
            #expect(result.run == LogTemporaryFile.FailureRun(),
                    "\(sweep) failed at nothing, so the run ends: \(result.run)")
        }
    }

    // How many files were refused does not decide when it is said. **One file refused at every
    // launch is the case this exists for**, and it is the quietest one there is.
    @Test func oneFileRefusedEveryLaunchIsEnough() {
        let result = launches([
            LogTemporaryFile.Sweep(removed: 4, failed: 1),
            LogTemporaryFile.Sweep(removed: 0, failed: 1),
            LogTemporaryFile.Sweep(removed: 2, failed: 1),
        ])
        #expect(result.said == [false, false, true])
    }

    // REQ-PER-001: **the count is worth nothing unless it crosses launches.** The sweep runs once
    // per launch, so a count that did not survive a restart could never reach two, and "three
    // launches in a row" would never arrive at all.
    @Test func theRunSurvivesARestart() throws {
        let run = launches([failing(), failing()]).run
        #expect(run.launches == 2)

        let saved = PersistedState(
            timer: .idle(now: sweepReference), presets: .initial(),
            logSweepFailures: run, savedAt: sweepReference
        )
        let written = try JSONEncoder.sweepISO.encode(saved)
        let reloaded = try JSONDecoder.sweepISO.decode(PersistedState.self, from: written)

        #expect(reloaded.logSweepFailures == run)
        let next = launches([failing()], from: reloaded.logSweepFailures)
        #expect(next.said == [true], "the third launch after a restart is still the third")
    }

    // REQ-PER-002: a state file saved before this field existed reads as no run at all. **Every
    // reader is in that state the first time they update into this**, and a missing field read as
    // anything else would report on the launch right after the update.
    @Test func aStateFileFromBeforeThisFieldReadsAsNoRun() throws {
        let json = """
        {"schemaVersion":1,
         "timer":\(String(decoding: try JSONEncoder.sweepISO.encode(TimerContext.idle(now: sweepReference)), as: UTF8.self)),
         "presets":\(String(decoding: try JSONEncoder.sweepISO.encode(PresetContext.initial()), as: UTF8.self)),
         "savedAt":"2023-11-14T22:13:20Z"}
        """
        let decoded = try JSONDecoder.sweepISO.decode(PersistedState.self, from: Data(json.utf8))

        #expect(decoded.logSweepFailures == LogTemporaryFile.FailureRun())
        #expect(decoded.logSweepFailures.launches == 0)
        let first = launches([failing()], from: decoded.logSweepFailures)
        #expect(first.said == [false], "the first launch after the update says nothing")
    }

    // A file somebody edited by hand. A count below zero sits under the threshold for good, and a
    // failure held there by one absurd number is a failure nobody is ever told about.
    @Test func aCountThatCouldNotHaveBeenWrittenHereReadsAsNone() throws {
        let bare = try JSONDecoder.sweepISO.decode(LogTemporaryFile.FailureRun.self, from: Data("{}".utf8))
        #expect(bare == LogTemporaryFile.FailureRun())

        let negative = try JSONDecoder.sweepISO.decode(
            LogTemporaryFile.FailureRun.self,
            from: Data(#"{"launches":-40,"didNotify":false}"#.utf8)
        )
        #expect(negative.launches == 0)
        let result = launches([failing(), failing(), failing()], from: negative)
        #expect(result.said == [false, false, true], "three launches from zero, not from minus forty")
    }
}

private let sweepReference = Date(timeIntervalSince1970: 1_700_000_000)

// The coders `FileStateStore` uses, so that what these tests read back is what a restart reads.
private extension JSONEncoder {
    static var sweepISO: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var sweepISO: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
