import Testing
import Foundation
@testable import MdoroCore

// REQ-ERR-010 / REQ-COM-009: a pasted log shows the end time the iPhone was counting toward,
// including after an extension, a preset switch and a confirmed restore.

@Suite("The diagnostic log carries sessionEndAt (REQ-ERR-010)")
struct SessionEndDiagnosticsTests {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func running(endAt: Date) -> TimerContext {
        var context = TimerContext.idle(now: now)
        context.runState = .running
        context.sessionStartedAt = now
        context.sessionEndAt = endAt
        return context
    }

    @Test func runningCarriesTheEndTimeInTheLogTimestampFormat() {
        let endAt = now.addingTimeInterval(1500)
        let fields = SessionEndDiagnostics.fields(after: running(endAt: endAt))
        #expect(fields == [DiagnosticField("endAt", DiagnosticLogFormat.timestamp(endAt))])
    }

    // What is broadcast outside RUNNING is no end time, and the log says the same.
    @Test func notRunningCarriesNone() {
        var paused = running(endAt: now.addingTimeInterval(1500))
        paused.runState = .paused
        #expect(SessionEndDiagnostics.fields(after: paused) == [DiagnosticField("endAt", "none")])
        #expect(SessionEndDiagnostics.fields(after: .idle(now: now)) == [DiagnosticField("endAt", "none")])
    }

    @Test func anExtensionCarriesItsSeconds() {
        let endAt = now.addingTimeInterval(1800)
        let fields = SessionEndDiagnostics.fields(after: running(endAt: endAt), extendedBy: 300)
        #expect(fields == [
            DiagnosticField("by", 300),
            DiagnosticField("endAt", DiagnosticLogFormat.timestamp(endAt)),
        ])
    }

    // The app target does not run under `swift test`, so the Mac's `action` line is checked in its
    // source: every accepted action — `extend`, `selectPreset`, `confirmRestoredSession` among them —
    // goes through this one line.
    @Test func theMacActionLineCarriesTheEndTime() throws {
        let path = "PomodoroMac/PomodoroMac/AppModel.swift"
        let body = withoutComments(try source(path))
        let anchor = "diagnostics.write(\"action\", ["
        guard let start = body.range(of: anchor) else { throw MissingAnchor(path: path, anchor: anchor) }
        guard let end = body[start.upperBound...].range(of: "return nil") else {
            throw MissingAnchor(path: path, anchor: "return nil after \(anchor)")
        }
        let line = body[start.lowerBound..<end.lowerBound]
        #expect(line.contains("SessionEndDiagnostics.fields("))
        #expect(line.contains("action == .extend"))
    }
}
