import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroMac

// POL-114 / REQ-COM-003: **a second start left the first listener up.**
//
// `self.listener = listener` replaced the property and nothing else. Network.framework keeps a
// started listener alive for its queue, so the old one went on holding its port and — for the
// `/info` server, which is the one carrying `.service` — its Bonjour registration. mDNSResponder
// renames a colliding registration instead of refusing it, so the reader saw `Lychee (2)` through
// `(5)` for two processes, and pairing kept landing on a registration whose process was not the one
// holding the code.
//
// `MdoroCoreTests` reads both files and checks the fold is written down, which is what CI runs.
// **This is the half that raises a listener and watches the previous one go**, and it is the only
// half that can tell a `cancel()` that happened from one that was written and never reached.
//
// What this puts on the machine, and what it does not: two ephemeral TCP listeners, for a few
// hundred milliseconds each, both cancelled before the test returns. **`advertise` is never
// called**, so nothing is registered with Bonjour and no name of the reader's goes on the LAN —
// which is the part POL-047 is about, and the reason `ServerRefusalLogTests` starts nothing at all.

// The connection callbacks. Nothing connects here — no client is pointed at these ports — so none
// of these is reached; they exist because `start` will not take fewer.
@MainActor
private func callbacksNothingReaches() -> MdoroServer.Callbacks {
    MdoroServer.Callbacks(
        authenticate: { _ in .reject(.connectionRejectedByUser) },
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

// Cancellation is asked for on one queue and settles on another, so it is waited for rather than
// read straight after. Two seconds is far longer than it takes and short enough to fail a run
// rather than hang it.
private func settlesAsCancelled(_ listener: NWListener) async -> Bool {
    for _ in 0..<100 {
        if case .cancelled = listener.state { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

// A log that is never opened writes nothing, so the server has somewhere to report to without a
// file of the reader's being touched.
@MainActor
private func unopenedLog() -> DiagnosticLog {
    DiagnosticLog(directory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroListenerFolding-\(UUID().uuidString)", isDirectory: true))
}

@Suite("A second start folds the first listener (POL-114 / REQ-COM-003)")
@MainActor
struct ListenerFoldingTests {

    @Test func theSyncServerCancelsTheListenerItReplaces() async throws {
        let server = MdoroServer(diagnostics: unopenedLog())
        defer { server.stop() }

        _ = try await server.start(callbacks: callbacksNothingReaches())
        let first = try #require(server.listener, "the first start raised no listener")

        let secondPort = try await server.start(callbacks: callbacksNothingReaches())
        let second = try #require(server.listener, "the second start raised no listener")

        #expect(second !== first, "POL-114: the second start kept the first listener")
        #expect(
            await settlesAsCancelled(first),
            "POL-114: the listener the first start raised is still up — the port it holds is never given back"
        )
        #expect(server.listenPort == secondPort, "the port on record is not the one that was returned")
    }

    // The `/info` server is the one that advertises, so this is the leak the reader actually saw.
    // It is started twice and never told to advertise: the fold is about the listener, and a
    // listener with no `.service` puts nothing on the network.
    @Test func theInfoServerCancelsTheListenerItReplaces() async throws {
        let info = InfoHTTPServer(
            info: ServerInfo(
                serverName: "not advertised",
                protocolVersion: PomodoroProtocol.version,
                isPairingMode: false,
                websocketPort: 0
            )
        )
        defer { info.stop() }

        _ = try await info.start()
        let first = try #require(info.listener, "the first start raised no listener")

        let secondPort = try await info.start()
        #expect(info.listener !== first, "POL-114: the second start kept the first listener")
        #expect(
            await settlesAsCancelled(first),
            "POL-114: the first /info listener is still up, and its Bonjour registration with it"
        )
        #expect(info.port == secondPort, "the port on record is not the one that was returned")
    }

    // `stop()` is what both starts now lean on. If it stopped taking the listener down, both folds
    // above would go quiet without either of them being edited.
    @Test func stoppingIsWhatTakesTheListenerDown() async throws {
        let server = MdoroServer(diagnostics: unopenedLog())
        _ = try await server.start(callbacks: callbacksNothingReaches())
        let listener = try #require(server.listener)

        server.stop()

        #expect(server.listener == nil, "stop() left the listener on record")
        #expect(server.listenPort == nil, "stop() left the port on record")
        #expect(await settlesAsCancelled(listener), "POL-114: stop() does not cancel the listener")
    }
}
