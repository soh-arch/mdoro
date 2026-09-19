import Testing
import Foundation
// **No `NW` type is spelled out in this file, and it still needs this.** `discoveredMac()` builds a
// `DiscoveredServer` whose `endpoint` is an `NWEndpoint`, and `.service(name:type:domain:interface:)`
// is that enum's case — reached by leading dot, so the type's name never appears here.
import Network
import MdoroCore
@testable import MdoroiOS

// REQ-COM-004 / REQ-PRT-004: **what the user gets for pressing something.**
//
// Two faults, one place. The user enters six digits or presses "Try again", and either
//
// - the dial fails on the network and the next one is up to thirty seconds away, because the
//   backoff was only ever wound back by a `welcome` and a connection somebody asked for inherited
//   however far the last run of failures had climbed; or
// - there was nothing to put in the `hello`, so none was sent — and the client answered for the Mac
//   by asking for a pairing code, over the top of the "update both devices" the Mac had actually
//   said (REQ-PRT-004).
//
// **Neither is about what the Mac did**, which is why both are read here rather than through the
// Mac's own suite: what is checked is which line the client opens when, and what it makes of the
// answer that comes back. `PairingTests` in MdoroCore has the other half — what
// `Authenticator.authenticate` answers a `hello` that carries nothing at all.

// A line the test drives both ends of. `cancel()` reports the ending an `NWConnection` would,
// because a double that took a cancel in silence is a line no implementation of this protocol is
// allowed to be — and the client's reading of *whose* ending it was would go unchecked.
@MainActor
private final class DrivenLine: MessageLink {
    private(set) var sent: [Data] = []
    private(set) var cancels = 0
    private(set) var endings = 0
    private var onEvent: ((MessageLinkEvent) -> Void)?

    func start(onEvent: @escaping (MessageLinkEvent) -> Void) { self.onEvent = onEvent }
    func send(_ data: Data) { sent.append(data) }

    func cancel() {
        cancels += 1
        deliver(.ended)
    }

    // `.ended` once, and last.
    func deliver(_ event: MessageLinkEvent) {
        guard endings == 0 else { return }
        if case .ended = event { endings += 1 }
        onEvent?(event)
    }
}

@MainActor
private final class DrivenLines: ClientLinkMaking {
    private(set) var opened: [DrivenLine] = []

    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        let line = DrivenLine()
        opened.append(line)
        return line
    }
}

// REQ-SEC-001: the device token lives in the Keychain, and this suite runs inside MdoroiOS.app
// under its bundle identifier — so the seam is taken, and nothing here reads or writes the
// reader's own. **An iPhone that has never been paired**, which is the one that reaches both
// faults above.
private struct NoTokenHere: TokenStoring {
    func load(serverId: ServerID) -> String? { nil }
    func save(_ token: String, serverId: ServerID) {}
    func delete(serverId: ServerID) {}
}

// Every state the client reported, in order. **What the screen was shown**, rather than only where
// it came to rest: a wrong sentence that is replaced a moment later was still put in front of the
// user, and `status` read at the end cannot see it.
@MainActor
private final class ReportedStates {
    private(set) var seen: [MdoroClient.Status] = []
    func record(_ status: MdoroClient.Status) { seen.append(status) }
}

@MainActor
private func discoveredMac() -> DiscoveredServer {
    DiscoveredServer(
        id: "Mdoro", name: "Mdoro",
        endpoint: .service(name: "Mdoro", type: BonjourService.type, domain: "local.", interface: nil),
        websocketPort: 51234, serverId: .generate()
    )
}

// A dial the user asked for: six digits entered, or "Try again" pressed with none in hand.
// **The one door `ClientModel` goes through either way** (`submitPairingCode` / `redial`).
@MainActor
private func dial(_ client: MdoroClient, code: String? = nil, reportingTo states: ReportedStates? = nil) {
    client.connect(
        to: discoveredMac(),
        pairingCode: code,
        callbacks: MdoroClient.Callbacks(
            statusChanged: { states?.record($0) },
            receivedSnapshot: { _ in }, receivedTaskList: { _ in },
            receivedEvent: { _ in }, receivedError: { _ in }, issuedToken: { _, _ in }
        )
    )
}

// How long the client waited before opening line number `count`, or nil if it never did.
//
// REQ-COM-004 names the waits — one second, then two — so **the length of the wait is how far up
// the backoff the client was.** This is the same measurement `BrokenMessageWiringTests` takes, and
// it is taken again here because the doubling is what the reset must not cost.
@MainActor
private func waitBeforeLine(_ count: Int, on links: DrivenLines, upTo seconds: TimeInterval) async -> TimeInterval? {
    let started = Date()
    while Date().timeIntervalSince(started) < seconds {
        if links.opened.count >= count { return Date().timeIntervalSince(started) }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}

// Sleeping is never exact, and one step of the backoff is a doubling, so half a step either way
// separates "one second" from anything else it could have been.
private func isAbout(_ measured: TimeInterval, _ expected: TimeInterval) -> Bool {
    measured >= expected * 0.9 && measured < expected * 1.5
}

// REQ-COM-004: **the wait belongs to the network, not to the user.** The ladder is there because a
// line that keeps dropping should not be knocked on every second; a user who presses something has
// told this client that the conditions changed, and the ladder has nothing to say about that.
@Suite("A dial the user asked for starts the backoff over (REQ-COM-004)")
@MainActor
struct AskedForDialTests {

    // The failure the user sees: press, watch nothing happen, and wait out a ladder they never saw
    // being climbed. **Measured as the wait before the next line**, because that is the silence.
    @Test func afterADialTheUserAskedForTheNextRetryIsOneSecondRatherThanTwo() async throws {
        let links = DrivenLines()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }

        // One failure, so the client is one rung up: the next wait would be two seconds.
        // **No `.ready` anywhere here** — a dial that got as far as the network and no further is
        // the whole of the case, and nothing about it depends on a `hello`.
        dial(client)
        let dropped = try #require(links.opened.first)
        dropped.deliver(.ended)
        _ = try #require(await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4),
                         "the first failure opened nothing in its place")

        // The user presses "Try again" (or enters a code — the same door).
        dial(client)
        #expect(links.opened.count == 3, "the dial the user asked for opened no line")
        let asked = try #require(links.opened.last)
        asked.deliver(.ended)

        let waited = try #require(
            await waitBeforeLine(4, on: links, upTo: ReconnectPolicy.initialDelay * 2 + 4),
            "the failure after the user's dial opened nothing in its place"
        )
        #expect(isAbout(waited, ReconnectPolicy.initialDelay),
                "REQ-COM-004: a dial the user asked for kept its place in the queue (waited \(waited))")
    }

    // **The other half, and it is the one the fix could have taken out.** Wind the backoff back in
    // `openConnection` instead — the door every retry comes in through — and the ladder never
    // leaves its first rung: a Mac that is off knocks once a second for as long as the app is open.
    //
    // So: one dial the user asked for, then two failures of its own. The waits are one second and
    // then two, counted from the reset.
    @Test func theRetriesTheBackoffMakesItselfStillDouble() async throws {
        let links = DrivenLines()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }

        dial(client)
        let dropped = try #require(links.opened.first)
        dropped.deliver(.ended)

        let first = try #require(
            await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4),
            "the first failure opened nothing in its place"
        )
        #expect(isAbout(first, ReconnectPolicy.initialDelay),
                "REQ-COM-004: one second the first time (waited \(first))")

        let retried = try #require(links.opened.last)
        retried.deliver(.ended)
        let second = try #require(
            await waitBeforeLine(3, on: links, upTo: ReconnectPolicy.initialDelay * 2 + 4),
            "the second failure opened nothing in its place"
        )
        #expect(isAbout(second, ReconnectPolicy.initialDelay * 2),
                "REQ-COM-004: the backoff no longer doubles between its own retries (waited \(second))")
    }
}

// REQ-PRT-004 / REQ-COM-004: **the Mac is asked, whatever this end has to offer.**
//
// `Authenticator.authenticate` reads the version before it reads a token or a code, so an empty
// `hello` is answered with the truth: `protocolVersionMismatch` when that is what is wrong,
// `pairingModeNotActive` when the Mac is not pairing, and `invalidPairingCode` — for a hello that
// carried no code — when it is. Deciding here that six digits are wanted gets the first of those
// three wrong, and that is the one the user is least able to work out for themselves.
@Suite("A hello goes out with nothing to carry (REQ-PRT-004 / REQ-COM-004)")
@MainActor
struct HelloWithNothingToCarryTests {

    private func refusal(_ code: AuthFailureCode) throws -> Data {
        try MessageCoder.encode(Envelope(body: ServerMessage.authFailed(AuthFailedPayload(code: code))))
    }

    // 10.2 / REQ-PRT-004: the version refusal travels on `error`, not on `authFailed`.
    private func versionRefusal() throws -> Data {
        let mismatch = ProtocolRefusal.protocolVersionMismatch
        return try MessageCoder.encode(Envelope(body: ServerMessage.error(ProtocolErrorPayload(
            code: mismatch.protocolErrorCode, message: mismatch.diagnosticSummary
        ))))
    }

    // A client with nothing at all: no token in the Keychain, no code from the user.
    private func dialledWithNothing(over links: DrivenLines, reportingTo states: ReportedStates) -> MdoroClient {
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        dial(client, code: nil, reportingTo: states)
        return client
    }

    // The hello used not to be sent at all. **The Mac was never asked**, and everything below rests
    // on it being asked.
    @Test func aHelloGoesOutWithNeitherATokenNorAPairingCodeInIt() throws {
        let links = DrivenLines()
        let states = ReportedStates()
        let client = dialledWithNothing(over: links, reportingTo: states)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        line.deliver(.ready)

        let sent = try #require(line.sent.first,
                                "REQ-PRT-004: nothing went out, so the Mac was never asked what is wrong")
        guard case let .hello(payload)? = try MessageCoder.decodeClient(sent)?.body else {
            Issue.record("the first thing on a new line is not the hello (REQ-SEC-001)")
            return
        }
        #expect(payload.deviceToken == nil, "a token this iPhone does not hold went out")
        #expect(payload.pairingCode == nil, "a code the user was never asked for went out")
        #expect(states.seen == [.connecting],
                "REQ-PRT-004: the client answered for the Mac rather than asking it (\(states.seen))")
    }

    // The user this was found through: refused over a version during a first pairing, told to
    // update both devices, presses "Try again". **The code went with `stopDialling`**, so this is a
    // client with nothing to send — and the sentence it is left showing has to be the same one.
    @Test func theVersionRefusalStillArrivesWhenTheHelloCarriedNothing() throws {
        let links = DrivenLines()
        let states = ReportedStates()
        let client = dialledWithNothing(over: links, reportingTo: states)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        line.deliver(.ready)
        line.deliver(.message(try versionRefusal()))

        #expect(client.status == .refused(.protocolVersionMismatch),
                "REQ-PRT-004: the refusal that asks for an update is not the state the user is left in")
        #expect(!states.seen.contains(.needsPairing),
                "REQ-PRT-004: the user was asked for six digits on the way to a version mismatch")
    }

    // A Mac that is not pairing says so, and **it is the Mac saying it now** rather than this end
    // guessing. The wording ("Start pairing on your Mac") is the same as before; what changed is
    // that it is no longer given to the two cases it is wrong for.
    @Test func aMacWithNoPairingWindowOpenIsReportedAsThatAndNotAsACodeToEnter() throws {
        let links = DrivenLines()
        let states = ReportedStates()
        let client = dialledWithNothing(over: links, reportingTo: states)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        line.deliver(.ready)
        line.deliver(.message(try refusal(.pairingModeNotActive)))

        #expect(client.status == .failed(.pairingModeNotActive))
        #expect(states.seen == [.connecting, .failed(.pairingModeNotActive)], "\(states.seen)")
    }

    // REQ-SEC-001: **the one answer that needs translating.** A Mac whose pairing window is open
    // refuses a hello carrying no code as `invalidPairingCode` — there is no other word for it in
    // 10.2 — and shown as it arrived it reads "That code is not correct" to a user who has not
    // typed a digit. What it means is that the Mac is waiting for the six.
    @Test func aRefusalOverACodeTheHelloNeverCarriedDoesNotCallTheCodeWrong() throws {
        let links = DrivenLines()
        let states = ReportedStates()
        let client = dialledWithNothing(over: links, reportingTo: states)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        line.deliver(.ready)
        line.deliver(.message(try refusal(.invalidPairingCode)))

        #expect(client.status == .needsPairing,
                "REQ-SEC-001: the Mac is waiting for a code, and the user is not being asked for one")
        #expect(!states.seen.contains(.failed(.invalidPairingCode)),
                "REQ-SEC-001: the user was told their code was wrong without having entered one (\(states.seen))")
    }

    // **And the translation does not swallow the real thing.** Six digits that were entered and
    // refused still read as wrong; a client that called every `invalidPairingCode` a request for a
    // code would pass the test above and leave the user retyping without being told anything.
    @Test func aRefusalOverACodeTheHelloDidCarryStillCallsTheCodeWrong() throws {
        let links = DrivenLines()
        let states = ReportedStates()
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        defer { client.disconnect() }
        dial(client, code: "123456", reportingTo: states)
        let line = try #require(links.opened.first)

        line.deliver(.ready)
        line.deliver(.message(try refusal(.invalidPairingCode)))

        #expect(client.status == .failed(.invalidPairingCode),
                "REQ-SEC-001: a code that was entered and refused is not reported as wrong")
        #expect(!states.seen.contains(.needsPairing), "\(states.seen)")
    }
}
