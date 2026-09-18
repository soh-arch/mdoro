import Testing
import Foundation
@testable import MdoroCore

// REQ-ERR-010 / Decision 0018

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("diagnostics-\(UUID().uuidString)")
    return url
}

private let header = DiagnosticHeader(
    appVersion: "1.0.0",
    build: "1",
    osVersion: "macOS 26.0",
    architecture: "arm64",
    openedAt: Date(timeIntervalSince1970: 1_756_000_000)
)

@Suite("Diagnostic log formatting (REQ-ERR-010)")
struct DiagnosticFormatTests {

    @Test func lineIsOneEventWithAlignedLevel() {
        let event = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_756_000_000),
            level: .info,
            code: "session.start",
            fields: [DiagnosticField("type", "work"), DiagnosticField("dur", 1500)]
        )
        let line = DiagnosticLogFormat.line(event)
        #expect(line.contains("INFO  session.start type=work dur=1500"))
        #expect(!line.contains("\n"))
    }

    @Test func warnAndErrorKeepTheSameColumnWidth() {
        #expect(DiagnosticLevel.info.padded.count == 5)
        #expect(DiagnosticLevel.warn.padded.count == 5)
        #expect(DiagnosticLevel.error.padded.count == 5)
    }

    // A newline slipping into a value does not break one event per line.
    @Test func fieldValuesCannotBreakTheLine() {
        let event = DiagnosticEvent(code: "x", fields: [DiagnosticField("k", "a\nb c")])
        #expect(DiagnosticLogFormat.line(event).contains("k=a_b_c"))
    }

    @Test func headerStatesWhatIsNotRecorded() {
        let text = DiagnosticLogFormat.header(header)
        #expect(text.contains("no task names"))
        #expect(text.contains("app=1.0.0 (1)"))
        #expect(text.contains("arch=arm64"))
    }

    // The header carries only the settings that affect behaviour. No paths, and no file names.
    @Test func headerSettingsCarryNoPaths() {
        var settings = AppSettings()
        settings.taskFilePath = "/Users/someone/Vault/秘密の計画/Task.md"
        settings.logFolderPath = "/Users/someone/Vault/Logs"
        settings.logFileName = "私のログ.md"

        let fields = DiagnosticHeader.settingsFields(preset: Preset.standard(), settings: settings)
        let rendered = fields.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        #expect(!rendered.contains("someone"))
        #expect(!rendered.contains("秘密の計画"))
        #expect(!rendered.contains("私のログ"))
        #expect(!rendered.contains("/"))
        #expect(rendered.contains("vault=#"))
        #expect(rendered.contains("work=1500"))
    }

    // REQ-NTF-006 / Decision 0017: the reader of an issue has no table mapping chime to the Glass
    // the settings screen offered, so the log carries both halves. The left half is the value 10.3
    // keeps for compatibility, and pinning the pair means renaming either one fails here first.
    // Every case is listed, including the two that repeat themselves: the form is uniform by choice.
    @Test func soundIsLoggedAsTheStoredValueAndTheNameSettingsShows() {
        let expected: [NotificationSound: String] = [
            .default: "default(Default)",
            .chime: "chime(Glass)",
            .bell: "bell(Submarine)",
            .wood: "wood(Pop)",
            .silent: "silent(Silent)",
        ]
        for sound in NotificationSound.allCases {
            #expect(expected[sound] == sound.diagnosticValue, "\(sound) is logged as \(sound.diagnosticValue)")
        }
        #expect(expected.count == NotificationSound.allCases.count, "a new sound needs a row above")

        var preset = Preset.standard()
        preset.notificationSound = .chime
        let fields = DiagnosticHeader.settingsFields(preset: preset, settings: AppSettings())
        #expect(fields.first { $0.key == "sound" }?.value == "chime(Glass)", "the header still logs the raw value alone")
    }
}

@Suite("Diagnostic log redaction (Decision 0018)")
struct DiagnosticRedactionTests {

    // The value has to come out the same across launches. `Hasher` cannot be used: its seed changes.
    @Test func digestIsStableAndShort() {
        let a = DiagnosticRedaction.digest("/Users/x/Vault/Task.md")
        let b = DiagnosticRedaction.digest("/Users/x/Vault/Task.md")
        #expect(a == b)
        #expect(a.count == 5)
        #expect(a.hasPrefix("#"))
        #expect(a != DiagnosticRedaction.digest("/Users/x/Vault/Other.md"))
    }

    @Test func unsetPathsSaySoInsteadOfHashingEmptiness() {
        #expect(DiagnosticRedaction.optionalDigest(nil) == "unset")
        #expect(DiagnosticRedaction.optionalDigest("") == "unset")
    }

    @Test func taskIsIdentifiedByTheLastFourCharactersOnly() {
        #expect(DiagnosticRedaction.taskId("abcdef123456a4f1") == "a4f1")
    }
}

@Suite("Diagnostic log rotation (Decision 0018)")
struct DiagnosticRotationTests {

    @Test func doesNotRotateAnEmptyFile() {
        #expect(DiagnosticLogFormat.shouldRotate(currentBytes: 0, incomingBytes: 999_999, maxBytes: 10) == false)
    }

    @Test func rotatesOnlyWhenTheLimitWouldBeExceeded() {
        #expect(DiagnosticLogFormat.shouldRotate(currentBytes: 5, incomingBytes: 4, maxBytes: 10) == false)
        #expect(DiagnosticLogFormat.shouldRotate(currentBytes: 5, incomingBytes: 6, maxBytes: 10) == true)
    }

    @Test func secondGenerationIsCreatedAndTheNewFileStartsWithAHeader() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DiagnosticLogFile(directory: directory, header: header, maxBytes: 400)

        for index in 0..<40 {
            file.write(DiagnosticEvent(code: "tick", fields: [DiagnosticField("n", index)]))
        }

        #expect(file.lastFailure == nil)
        #expect(FileManager.default.fileExists(atPath: file.previousURL.path))
        let current = try String(contentsOf: file.currentURL, encoding: .utf8)
        #expect(current.hasPrefix("# Mdoro diagnostic log"))
    }

    // The cap is two generations. Left alone, it does not keep growing.
    @Test func neverKeepsMoreThanTwoFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DiagnosticLogFile(directory: directory, header: header, maxBytes: 300)

        for index in 0..<200 {
            file.write(DiagnosticEvent(code: "tick", fields: [DiagnosticField("n", index)]))
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.count == 2)
    }

    // The export joins them into one, previous generation then current.
    @Test func exportJoinsBothGenerationsInOrder() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DiagnosticLogFile(directory: directory, header: header, maxBytes: 400)

        for index in 0..<40 {
            file.write(DiagnosticEvent(code: "tick", fields: [DiagnosticField("n", index)]))
        }
        let previous = try String(contentsOf: file.previousURL, encoding: .utf8)
        let current = try String(contentsOf: file.currentURL, encoding: .utf8)
        #expect(file.exportedText() == previous + current)
        #expect(current.contains("n=39"))
    }

    @Test func writingWhenTheDirectoryIsUnavailableIsReportedNotSwallowed() {
        // Point at a place that cannot be written. Confirms it **is not dropped in silence**
        // (CONTEXT, 「失敗を黙らせない」 — the heading is Japanese, and so is the document).
        let file = DiagnosticLogFile(directory: URL(fileURLWithPath: "/dev/null/nope"), header: header)
        file.write(DiagnosticEvent(code: "tick"))
        #expect(file.lastFailure != nil)
    }
}

// How many times a string occurs. The count is what separates "a header per launch" from
// "a header per line" and from "a header once, in August".
private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

@Suite("Diagnostic log header per launch (REQ-ERR-010)")
struct DiagnosticHeaderPerLaunchTests {

    // The header is the only place the OS version and the settings appear. A file that was created
    // weeks ago must not go on describing the machine of the day it was created.
    @Test func aLaterLaunchWritesItsOwnHeaderIntoTheFileThatIsAlreadyThere() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DiagnosticLogFile(directory: directory, header: header)
        first.write(DiagnosticEvent(code: "app.start"))
        first.write(DiagnosticEvent(code: "session.start"))

        // The machine moved on between the two launches: a newer OS, and a task file now chosen.
        var later = header
        later.osVersion = "macOS 26.7.0"
        later.openedAt = Date(timeIntervalSince1970: 1_758_000_000)
        later.settings = [DiagnosticField("vault", "#3f9a")]
        let second = DiagnosticLogFile(directory: directory, header: later)
        second.write(DiagnosticEvent(code: "app.start"))
        second.write(DiagnosticEvent(code: "session.start"))

        #expect(second.lastFailure == nil)
        let text = try String(contentsOf: second.currentURL, encoding: .utf8)
        #expect(text.contains("os=macOS 26.7.0"), "the OS this launch is running on never reached the file")
        #expect(text.contains("vault=#3f9a"), "the settings this launch is running under never reached the file")
        // One header per launch: not one per line, and not one per file.
        #expect(occurrences(of: "# opened=", in: text) == 2)
        #expect(occurrences(of: "os=macOS 26.0", in: text) == 1)

        // The new header stands ahead of the lines it accounts for.
        let lines = text.split(separator: "\n").map(String.init)
        let newestHeader = try #require(lines.lastIndex(where: { $0.hasPrefix("# opened=") }))
        let newestEvent = try #require(lines.lastIndex(where: { !$0.hasPrefix("#") }))
        #expect(newestHeader < newestEvent)
        #expect(lines.filter({ !$0.hasPrefix("#") }).count == 4, "every event written is still one line")
    }

    // Decision 0018: nothing here deletes old lines. The header of a new launch is one more append,
    // so what was on disk stays on disk, byte for byte, in the place it already had.
    @Test func theLinesOfEarlierLaunchesAreKeptByteForByte() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DiagnosticLogFile(directory: directory, header: header)
        for index in 0..<5 {
            first.write(DiagnosticEvent(code: "tick", fields: [DiagnosticField("n", index)]))
        }
        // Read as bytes: what has to hold is that the file grows at its end and nowhere else.
        let before = try Data(contentsOf: first.currentURL)

        var later = header
        later.osVersion = "macOS 26.7.0"
        let second = DiagnosticLogFile(directory: directory, header: later)
        second.write(DiagnosticEvent(code: "tick", fields: [DiagnosticField("n", 5)]))

        let afterBytes = try Data(contentsOf: second.currentURL)
        #expect(afterBytes.starts(with: before), "an earlier launch's bytes were rewritten rather than appended to")
        #expect(afterBytes.count > before.count)
        #expect(before.count > 0, "the comparison above proves nothing against an empty file")
        let after = try String(contentsOf: second.currentURL, encoding: .utf8)
        #expect(after.contains("n=0"))
        #expect(after.contains("n=5"))
        // The file still opens with the header of the launch that created it. The new one is below.
        #expect(after.hasPrefix("# Mdoro diagnostic log"))
        #expect(occurrences(of: "os=macOS 26.0", in: after) == 1)
        #expect(occurrences(of: "os=macOS 26.7.0", in: after) == 1)
    }

    // A launch that never writes an event leaves no header behind: the header rides on the first line.
    @Test func aLaunchThatWritesNothingLeavesNoHeader() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DiagnosticLogFile(directory: directory, header: header)
        first.write(DiagnosticEvent(code: "app.start"))
        _ = DiagnosticLogFile(directory: directory, header: header)
        let third = DiagnosticLogFile(directory: directory, header: header)
        third.write(DiagnosticEvent(code: "app.start"))
        third.write(DiagnosticEvent(code: "app.stop"))

        let text = try String(contentsOf: third.currentURL, encoding: .utf8)
        #expect(occurrences(of: "# opened=", in: text) == 2)
    }

    // The header of a launch that has already been written must not stop a rotation from heading the
    // new generation. That is the path this walks: one instance, its header paid for by the first
    // line, and a second line that has to rotate.
    //
    // The limit is **measured, not guessed** — exactly the size the file has after the first write.
    // The first write cannot rotate (an empty file never does) and the second cannot avoid it
    // (anything at all added to a file already at the limit exceeds it).
    @Test func aRotationAfterTheHeaderIsPaidForStillHeadsTheNewFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstEvent = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_756_000_000),
            code: "tick",
            fields: [DiagnosticField("n", 0)]
        )
        let secondEvent = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_756_000_001),
            code: "tick",
            fields: [DiagnosticField("n", 1)]
        )
        let limit = Data(DiagnosticLogFormat.header(header).utf8).count
            + Data((DiagnosticLogFormat.line(firstEvent) + "\n").utf8).count

        let file = DiagnosticLogFile(directory: directory, header: header, maxBytes: limit)
        file.write(firstEvent)

        let afterFirst = try Data(contentsOf: file.currentURL)
        #expect(afterFirst.count == limit, "the limit has to be the size the file now has, or the rest proves nothing")
        #expect(
            !FileManager.default.fileExists(atPath: file.previousURL.path),
            "the first write must not rotate: the second one is the one under test"
        )

        // Same instance, so the header is already written. This line rotates.
        file.write(secondEvent)

        #expect(file.lastFailure == nil)
        let current = try String(contentsOf: file.currentURL, encoding: .utf8)
        #expect(current.hasPrefix("# Mdoro diagnostic log"), "the new generation was started without a header")
        #expect(occurrences(of: "# opened=", in: current) == 1)
        #expect(current.contains("n=1"))
        let previous = try String(contentsOf: file.previousURL, encoding: .utf8)
        #expect(previous.hasPrefix("# Mdoro diagnostic log"))
        #expect(previous.contains("n=0"))
    }

    // And the other order: a launch whose very first line rotates the file owes a header and gets
    // exactly one — from the rotation, not one from the rotation and one of its own.
    @Test func aLaunchWhoseFirstLineRotatesGetsExactlyOneHeader() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let event = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_756_000_000),
            code: "tick",
            fields: [DiagnosticField("n", 0)]
        )
        let limit = Data(DiagnosticLogFormat.header(header).utf8).count
            + Data((DiagnosticLogFormat.line(event) + "\n").utf8).count

        let first = DiagnosticLogFile(directory: directory, header: header, maxBytes: limit)
        first.write(event)
        let afterFirst = try Data(contentsOf: first.currentURL)
        #expect(afterFirst.count == limit, "the limit has to be the size the file now has")

        var later = header
        later.osVersion = "macOS 26.7.0"
        let second = DiagnosticLogFile(directory: directory, header: later, maxBytes: limit)
        second.write(DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_756_000_001),
            code: "tick",
            fields: [DiagnosticField("n", 1)]
        ))

        #expect(second.lastFailure == nil)
        let current = try String(contentsOf: second.currentURL, encoding: .utf8)
        #expect(occurrences(of: "# opened=", in: current) == 1, "this launch's header went in twice")
        #expect(current.contains("os=macOS 26.7.0"), "the header at the top is the older launch's")
        #expect(current.contains("n=1"))
        let previous = try String(contentsOf: second.previousURL, encoding: .utf8)
        #expect(occurrences(of: "os=macOS 26.0", in: previous) == 1)
        #expect(previous.contains("n=0"))
    }

    // A refused write leaves the header still owed — and does not leave half of one behind. The
    // header and the line go to the file in one call, so there is no state in between.
    @Test func aRefusedWriteLeavesTheHeaderOwedAndNothingHalfWritten() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName).path
            )
            try? FileManager.default.removeItem(at: directory)
        }

        let first = DiagnosticLogFile(directory: directory, header: header)
        first.write(DiagnosticEvent(code: "app.start"))
        let afterFirst = try Data(contentsOf: first.currentURL)

        // A second launch that cannot write: the file itself is refused.
        let second = DiagnosticLogFile(directory: directory, header: header)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: second.currentURL.path
        )
        second.write(DiagnosticEvent(code: "app.start"))

        #expect(second.lastFailure != nil, "the file system must actually refuse, or this proves nothing")
        let afterRefusal = try Data(contentsOf: second.currentURL)
        #expect(afterRefusal == afterFirst, "a refused write left something behind")

        // Allowed again: the header this launch still owes goes in, once, with the line.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: second.currentURL.path
        )
        second.write(DiagnosticEvent(code: "app.stop"))

        #expect(second.lastFailure == nil)
        let text = try String(contentsOf: second.currentURL, encoding: .utf8)
        #expect(occurrences(of: "# opened=", in: text) == 2, "the second launch is owed exactly one header")
        #expect(text.contains("app.stop"))
    }
}
