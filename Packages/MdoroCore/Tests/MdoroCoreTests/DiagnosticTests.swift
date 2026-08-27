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

@Suite("診断ログの整形 (REQ-ERR-010)")
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

    // 値に改行が紛れても1行1イベントが崩れない。
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

    // ヘッダに載るのは「挙動に効く設定」だけで、パスもファイル名も載らない。
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
}

@Suite("診断ログの伏字 (Decision 0018)")
struct DiagnosticRedactionTests {

    // 起動をまたいでも同じ値になること。`Hasher` は種が変わるので使えない。
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

@Suite("診断ログのローテーション (Decision 0018)")
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

    // 上限は 2 世代ぶん。放っておいても増え続けない。
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

    // 書き出しは「前の世代 → いまの世代」の順に1本へ。
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
        // 書けない場所を指す。**黙って捨てない**ことを確かめる（CONTEXT「失敗を黙らせない」）。
        let file = DiagnosticLogFile(directory: URL(fileURLWithPath: "/dev/null/nope"), header: header)
        file.write(DiagnosticEvent(code: "tick"))
        #expect(file.lastFailure != nil)
    }
}
