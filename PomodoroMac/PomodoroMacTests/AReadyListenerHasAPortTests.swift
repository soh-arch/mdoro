import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroMac

// REQ-COM-002 / 003: **the port the Mac hands upward is the one it goes on the air with, so a
// number that is not a port must not be one of the answers.**
//
// `MdoroServer.start` returns what `ListenerReadiness.awaitReady` read off the listener, and
// `advertise` writes that number into the Bonjour TXT record as `ws`. **0 is not a refusal there.**
// `NWEndpoint.Port(rawValue: 0)` returns a port — `.any`, the request to be given whichever port is
// free — and `DiscoveredServer.read` parses `"0"` back with `UInt16.init` and no complaint, so a 0
// would travel the whole way and the iPhone would dial a port nothing listens on. The one symptom
// is silence: no refusal, no line in any log, nothing on either screen to read.
//
// **What this suite reaches and what it does not.** Nothing can make a real `NWListener` go ready
// without a port — `NWListener.port`'s own documentation says the port is available once the
// listener is in the ready state (read 2026-09-19) — so the branch that refuses one cannot be
// produced from a listener, and the last test here cannot exercise it. That is why the decision
// sits in `ListenerReadiness.settledPort`, away from the listener, where it can be asked directly.
// The three tests that ask it would all pass against `listener.port?.rawValue ?? 0` being written
// back into `awaitReady` — **they hold the decision, not the call site.** The last test is the half
// that stands at the call site, and it is the one `ListenerFoldingTests` leaves out: that suite
// compares the port with itself, so it says nothing about the port being a port.
//
// What this puts on the machine: one ephemeral TCP listener, cancelled before the test returns.
// **`advertise` is never called**, so nothing is registered with Bonjour and no name of the
// reader's goes on the LAN — the same footing `ListenerFoldingTests` runs on (Decision 0047: this
// suite is hosted by the real app).

// The connection callbacks. Nothing connects here — no client is pointed at this port — so none of
// these is reached; they exist because `start` will not take fewer.
@MainActor
private func callbacksNothingReaches() -> MdoroServer.Callbacks {
    MdoroServer.Callbacks(
        authenticate: { _ in .reject(.connectionRejectedByUser) },
        resolveApproval: { _ in nil },
        handleCommand: { _ in },
        provideSnapshot: {
            StateSnapshot(
                timer: .idle(now: Date()),
                task: TaskContext(),
                settings: .default,
                presets: .initial(),
                connection: ConnectionState(isConnected: false)
            )
        },
        provideTaskList: { nil },
        provideDisplayName: { AppSettings.defaultDisplayName },
        connectionChanged: { _ in }
    )
}

// A log that is never opened writes nothing, so the server has somewhere to report to without a
// file of the reader's being touched.
@MainActor
private func unopenedLog() -> DiagnosticLog {
    DiagnosticLog(directory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroListenerPort-\(UUID().uuidString)", isDirectory: true))
}

@Suite("A ready listener hands back a port, or nothing (REQ-COM-002 / REQ-COM-003)")
@MainActor
struct AReadyListenerHasAPortTests {

    // The line this suite exists for. A listener with no port used to be answered with 0, and 0
    // reads as a port everywhere downstream — so the failure arrived as an iPhone that could not
    // reach a Mac that was, as far as every screen and every log could say, listening.
    @Test func aListenerWithNoPortIsRefusedInsteadOfAnsweredWithZero() {
        #expect(throws: ListenerReadiness.NoPortOnAReadyListener.self) {
            try ListenerReadiness.settledPort(nil)
        }
    }

    // And a listener that reported 0 outright is refused for the same reason, not passed on for
    // being a `UInt16`: `.any` is a request made before binding, never an answer after it.
    @Test func aPortOfZeroIsRefusedForTheSameReason() {
        #expect(throws: ListenerReadiness.NoPortOnAReadyListener.self) {
            try ListenerReadiness.settledPort(0)
        }
    }

    // The other half, which is what keeps the two above from being satisfied by a function that
    // refuses everything. 1 and 65535 are here because a guard written as a range is the plausible
    // way to get this wrong, and both ends are real ports.
    @Test func aPortThatIsAPortComesStraightBack() throws {
        #expect(try ListenerReadiness.settledPort(51234) == 51234)
        #expect(try ListenerReadiness.settledPort(1) == 1)
        #expect(try ListenerReadiness.settledPort(65535) == 65535)
    }

    // At the call site: what `start` returns is the port the listener it raised is actually on.
    // **The comparison is made against a port that was required to exist first**, so a listener
    // with no port fails here rather than matching a nil against a nil.
    //
    // **Turning the number back into an `NWEndpoint.Port` is not asserted, because that cannot
    // fail**: `Port(rawValue:)` accepts every `UInt16`, 0 included — that is the whole reason 0
    // travels so far. `raw != 0` is the check that stands in its place.
    @Test func theStartedServerReturnsThePortItsListenerIsOn() async throws {
        let server = MdoroServer(diagnostics: unopenedLog())
        defer { server.stop() }

        let raw = try await server.start(callbacks: callbacksNothingReaches())
        let listener = try #require(server.listener, "the start raised no listener")
        let bound = try #require(listener.port, "the listener is ready and has no port")

        #expect(raw != 0, "0 is `.any`; nothing listens there and every dial to it is silence")
        #expect(raw == bound.rawValue, "the port that was returned is not the port that was bound")
    }
}
