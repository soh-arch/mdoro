import Testing
import Foundation
// **No `NW` type is spelled out in this file, and it still needs this.** `discoveredMac()` builds a
// `DiscoveredServer` whose `endpoint` is an `NWEndpoint`, and `.service(name:type:domain:interface:)`
// is that enum's case — reached by leading dot, so the type's name never appears here. Searching
// this file for `NW` finds nothing and says nothing; the import is load-bearing anyway, and
// `@testable import MdoroiOS` does not re-export it.
import Network
import MdoroCore
@testable import MdoroiOS

// REQ-COM-004: **what this file keeps, and what it cannot.**
//
// **What it keeps**: which line's ending `MdoroClient` acts on, reached without a LAN through
// `ClientLinkMaking`.
//
// **What moved out**: the decision one read off the line carries. `LineRead.of` is shared with the
// Mac now (REQ-PRT-001), and `MdoroCoreTests/LineReadTests` asks it there — where `swift test` runs
// it on every pull request, which nothing in CI does for this suite (`docs/ORCHESTRATION.md` §8).
//
// **What it cannot keep**: anything inside `WebSocketLink` itself. `NWConnection` cannot be stood
// in for — it dials the moment it is started — so nothing here executes the read loop, and four
// things about it are **not** covered by any test below:
//
// - that `deliver(.ended)` cancels the connection rather than letting go of it,
// - that `deinit` does the same for a line that never ended,
// - that `receive()` stops re-arming once the line has ended,
// - that it also stops once the line has been hung up on but has not ended yet — the gap
//   `cancel()` opens when it is called from inside a read (REQ-ERR-009's tenth broken message,
//   `stopDialling` on a refusal), which is the one thing `hasEnded` cannot cover.
//
// **The loop turning is the one thing no assertion here can see.** `LineReadTests` says `.end` is
// the right answer; that the loop then stops asking is between `receive()` and the transport.
// Closing it would mean putting a seam under `NWConnection`, which is a larger change than the
// faults these were found in. Until then it rests on reading the function.

// A line that takes its cancel the way an `NWConnection` does: the cancel is *asked for* here, and
// the ending comes back later. **A double that ended the instant it was told to would be the one
// shape these tests must not assume**, because what is being checked is what the client does in
// the gap between letting a line go and hearing it finish.
@MainActor
private final class DeferredLine: MessageLink {
    private(set) var sent: [Data] = []
    private(set) var cancels = 0
    private(set) var endings = 0
    private var onEvent: ((MessageLinkEvent) -> Void)?

    func start(onEvent: @escaping (MessageLinkEvent) -> Void) { self.onEvent = onEvent }
    func send(_ data: Data) { sent.append(data) }
    func cancel() { cancels += 1 }

    // **The contract is kept**: `.ended` is said once and last. That is the point — the line about
    // to be ignored below is doing nothing wrong.
    func deliver(_ event: MessageLinkEvent) {
        guard endings == 0 else { return }
        if case .ended = event { endings += 1 }
        onEvent?(event)
    }
}

@MainActor
private final class DeferredLines: ClientLinkMaking {
    private(set) var opened: [DeferredLine] = []

    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        let line = DeferredLine()
        opened.append(line)
        return line
    }
}

// REQ-SEC-001: the device token lives in the Keychain, and this suite runs inside MdoroiOS.app
// under its bundle identifier — so the seam is taken, and nothing here reads or writes the
// reader's own.
private struct NoTokenHere: TokenStoring {
    func load(serverId: ServerID) -> String? { nil }
    func save(_ token: String, serverId: ServerID) {}
    func delete(serverId: ServerID) {}
}

// REQ-COM-004: **a client dials again when the line it is holding ends** — not when some line ends.
//
// A second line can be opened over the top of the first: `ClientModel.forgetPairedMac` starts the
// browser and dials straight back when one Mac is in sight, and "Choose a Mac" can be pressed while
// a dial is still in flight. The line that gets displaced is still alive, still keeping its own
// contract, and still going to report its ending. Read as this client's ending it clears the line
// that took its place and re-dials on a backoff nothing wound back.
@Suite("Only the line this client is holding is listened to (REQ-COM-004)")
@MainActor
struct HeldLineTests {

    private func discoveredMac() -> DiscoveredServer {
        DiscoveredServer(
            id: "Mdoro", name: "Mdoro",
            endpoint: .service(name: "Mdoro", type: BonjourService.type, domain: "local.", interface: nil),
            websocketPort: 51234, serverId: .generate()
        )
    }

    private func dial(_ client: MdoroClient) {
        client.connect(
            to: discoveredMac(),
            // With neither a token nor a code, the client stops to ask for one (REQ-SEC-001).
            pairingCode: "123456",
            callbacks: MdoroClient.Callbacks(
                statusChanged: { _ in }, receivedSnapshot: { _ in }, receivedTaskList: { _ in },
                receivedEvent: { _ in }, receivedError: { _ in }, issuedToken: { _, _ in }
            )
        )
    }

    // REQ-COM-004: the displaced line is hung up on rather than dropped. Nobody else is going to:
    // the client has stopped listening to it by the next statement, and an `NWConnection` that is
    // never cancelled keeps what it is holding.
    @Test func aDisplacedLineIsHungUpOn() throws {
        let links = DeferredLines()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }

        dial(client)
        let first = try #require(links.opened.first)
        first.deliver(.ready)

        dial(client)

        #expect(links.opened.count == 2, "the second dial did not open a line")
        #expect(first.cancels == 1, "the line that was displaced was let go of without being hung up on")
    }

    // The whole of it: the displaced line reports the ending it was asked for, and the line holding
    // its place is untouched — not cancelled, not replaced, and still the one being spoken on.
    @Test func anEndingFromADisplacedLineLeavesTheLineInItsPlaceAlone() async throws {
        let links = DeferredLines()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }

        dial(client)
        let first = try #require(links.opened.first)
        first.deliver(.ready)

        dial(client)
        let second = try #require(links.opened.last)
        second.deliver(.ready)
        let sentBeforeTheOrphanEnded = second.sent.count
        #expect(sentBeforeTheOrphanEnded == 1, "the hello did not go out on the line that was opened second")

        // The displaced line finishes — late, and correctly.
        first.deliver(.ended)

        #expect(second.cancels == 0, "an ending from a line the client had let go of hung up the line in its place")

        // **The client is still holding the second line.** Everything it sends goes out through
        // whatever `link` is, so a `link` cleared by somebody else's ending is silent rather than
        // wrong, and silence is what is asked about here.
        client.requestSnapshot()
        #expect(second.sent.count == sentBeforeTheOrphanEnded + 1,
                "the client stopped speaking on the line it was holding")

        // REQ-COM-004: and no backoff was started on the strength of that ending.
        try? await Task.sleep(for: .seconds(ReconnectPolicy.initialDelay + 0.5))
        #expect(links.opened.count == 2, "a third line was dialled because a displaced line ended")
    }

    // The ordinary ending still works. **A guard that let nothing through would pass every test
    // above**, so the line the client *is* holding has to be shown ending the way it always did.
    @Test func anEndingFromTheLineInHandStillDialsAgain() async throws {
        let links = DeferredLines()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }

        dial(client)
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        line.deliver(.ended)

        let deadline = Date().addingTimeInterval(ReconnectPolicy.initialDelay + 3)
        while Date() < deadline && links.opened.count < 2 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(links.opened.count == 2, "the line the client was holding ended and nothing was dialled")
    }
}
