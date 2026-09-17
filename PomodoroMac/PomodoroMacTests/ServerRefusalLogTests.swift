import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// What the Mac writes when it turns a connection away.
//
// "It will not pair" is the report, and the diagnostic log is what answers it. Leave a refusal
// unwritten and five wrong codes, a pairing window that had closed, a token this Mac no longer
// knows and a request the user never answered all read as the same silence — refusals the reader
// cannot see, on a screen that is not theirs. No clause asks for these lines: the reader Decision
// 0018 wrote the log for is the whole of why they exist.
//
// REQ-ERR-010 / Decision 0018: that reader pastes the log into an issue, which is why a refusal is
// the one place the device name, the token and the pairing code must never reach — and all three
// are in hand at the moment one is written.

// One event per line: `timestamp LEVEL code key=value ...`.
private struct RefusalLine {
    let level: String
    let code: String
    let fields: [String: String]

    init?(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, !line.hasPrefix("#") else { return nil }
        level = parts[1]
        code = parts[2]
        fields = parts.dropFirst(3).reduce(into: [:]) { result, part in
            guard let separator = part.firstIndex(of: "=") else { return }
            result[String(part[part.startIndex..<separator])] = String(part[part.index(after: separator)...])
        }
    }
}

private struct ServerRecording {
    let text: String
    let lines: [RefusalLine]

    var refusals: [RefusalLine] { lines.filter { $0.code == "conn.refused" } }
}

// A server writing to a diagnostic log of its own, read back the way a reader on an issue sees
// it — the file, not the fields handed in.
@MainActor
private func recordRefusals(_ body: (MdoroServer) -> Void) throws -> ServerRecording {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroServerRefusals-\(UUID().uuidString)", isDirectory: true)
    let diagnostics = DiagnosticLog(directory: directory)
    diagnostics.open(preset: Preset.standard(), settings: AppSettings())
    // Never started, so nothing listens and nothing is advertised. Only the record is wanted.
    body(MdoroServer(diagnostics: diagnostics))

    let text = try String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )
    try? FileManager.default.removeItem(at: directory)
    return ServerRecording(text: text, lines: text.split(separator: "\n").compactMap { RefusalLine(String($0)) })
}

private func hello(deviceName: String = "iPhone") -> HelloPayload {
    HelloPayload(deviceName: deviceName)
}

@Suite("A refused connection leaves a line, and nothing of the device in it")
@MainActor
struct ServerRefusalLogTests {

    // Every one of them, because the whole point is telling them apart. Walking `allCases`
    // rather than a list here means a refusal cannot be added without this saying something
    // about it.
    @Test func everyRefusalIsWrittenAndTheyAllReadDifferently() throws {
        let recording = try recordRefusals { server in
            for code in AuthFailureCode.allCases {
                server.record(refusal: code, of: hello())
            }
        }

        #expect(recording.refusals.count == AuthFailureCode.allCases.count)
        let reasons = recording.refusals.compactMap { $0.fields["why"] }
        #expect(Set(reasons).count == AuthFailureCode.allCases.count,
                "two refusals read the same, so the log cannot tell them apart")
        for code in AuthFailureCode.allCases {
            #expect(reasons.contains(code.diagnosticSummary), "nothing is written for \(code.rawValue)")
        }
        // Decision 0034: a refusal is written the way every other failure in the app is.
        #expect(recording.refusals.allSatisfy { $0.level == "WARN" })
    }

    // REQ-ERR-010 / Decision 0018: **it is never put in, rather than masked on the way out.** The
    // device name, the token and the pairing code are all in hand at the moment of refusal, which
    // is exactly why this hands one of each in and then reads the whole file.
    @Test func nothingTheRefusedDeviceSentReachesTheFile() throws {
        let deviceName = "UNIQUEDEVICENAME"
        let deviceToken = "UNIQUETOKENVALUE"
        let pairingCode = "424242"

        let recording = try recordRefusals { server in
            server.record(
                refusal: .invalidPairingCode,
                of: HelloPayload(deviceToken: deviceToken, pairingCode: pairingCode, deviceName: deviceName)
            )
        }

        for secret in [deviceName, deviceToken, pairingCode] {
            #expect(!recording.text.contains(secret), "REQ-ERR-010: `\(secret)` appears in the diagnostic log")
        }
        // The scan must not have been looking at a file with no refusal in it.
        let refusal = try #require(recording.refusals.first)
        #expect(refusal.fields["why"] == AuthFailureCode.invalidPairingCode.diagnosticSummary)
    }
}
