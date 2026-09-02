import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroiOS

// A line the test holds both ends of: it records what went out and hands in what "arrived", so
// nothing is dialled and the run stays off the LAN.
//
// **It keeps `MessageLink`'s contract about endings** — a cancelled line reports `.ended`, and
// `.ended` is said once and last — because that contract is what the client hangs its reconnect on.
@MainActor
private final class SilentLine: MessageLink {
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

    func deliver(_ event: MessageLinkEvent) {
        guard endings == 0 else { return }
        if case .ended = event { endings += 1 }
        onEvent?(event)
    }
}

@MainActor
private final class SilentLines: ClientLinkMaking {
    private(set) var opened: [SilentLine] = []

    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        let line = SilentLine()
        opened.append(line)
        return line
    }
}

// The clock REQ-COM-005's fifteen seconds are measured on, with the test holding the hands.
// **Nothing here waits fifteen seconds**; the silence is made to have happened.
private final class MovableClock {
    private var instant = Date(timeIntervalSince1970: 1_000_000_000)

    func advance(by seconds: TimeInterval) { instant += seconds }
    func read() -> Date { instant }
}

// REQ-SEC-001: the device token lives in the Keychain, and this suite runs inside MdoroiOS.app
// under its bundle identifier — so the seam is taken, and nothing here reads or writes the
// reader's own.
private struct NoTokenHere: TokenStoring {
    func load(serverId: ServerID) -> String? { nil }
    func save(_ token: String, serverId: ServerID) {}
    func delete(serverId: ServerID) {}
}

// REQ-COM-005: **both ends** watch for silence, and fifteen seconds of it is a disconnect.
//
// The phone cannot watch for heartbeats: 10.2 gives the Mac none to send. What it watches is
// receipt itself — anything arriving is proof the Mac is still on the other end — and what it does
// about the silence is hang up, so the reconnect REQ-COM-004 already hangs off `.ended` carries it.
@Suite("Fifteen seconds of silence is a disconnect (REQ-COM-005)")
@MainActor
struct SilenceDetectionTests {

    // MARK: - The client, on a line and a clock the test drives

    private func discoveredMac() -> DiscoveredServer {
        DiscoveredServer(
            id: "Mdoro", name: "Mdoro",
            endpoint: .service(name: "Mdoro", type: BonjourService.type, domain: "local.", interface: nil),
            websocketPort: 51234, serverId: .generate()
        )
    }

    // The heartbeat goes out every five seconds in production (REQ-COM-005) and the silence is
    // looked at on the same beat. Shortening the beat is what lets the wiring — the loop, the
    // decision, the hang-up — run inside a test; **the fifteen seconds themselves are untouched,
    // because they come from `Heartbeat.timeout`.**
    private static let quickBeat: TimeInterval = 0.01

    private func connectedClient(over links: SilentLines, on clock: MovableClock) throws -> MdoroClient {
        let client = MdoroClient(
            tokens: NoTokenHere(), links: links,
            clock: { clock.read() }, heartbeatInterval: Self.quickBeat
        )
        client.connect(
            to: discoveredMac(),
            // With neither a token nor a code, the client stops to ask for one (REQ-SEC-001).
            pairingCode: "123456",
            callbacks: MdoroClient.Callbacks(
                statusChanged: { _ in }, receivedSnapshot: { _ in }, receivedTaskList: { _ in },
                receivedEvent: { _ in }, receivedError: { _ in }, issuedToken: { _, _ in }
            )
        )
        let line = try #require(links.opened.first)
        line.deliver(.ready)
        // REQ-SEC-001: the Mac's answer to the hello, carrying the device token. The connection
        // stands from here, and so does the watch.
        line.deliver(try welcomeMessage())
        return client
    }

    private func welcomeMessage() throws -> MessageLinkEvent {
        .message(try MessageCoder.encode(Envelope(body: ServerMessage.welcome(
            WelcomePayload(deviceToken: "a token this test throws away", serverName: "Mdoro")
        ))))
    }

    // A pong with no t2 or t3 is read and then set aside (REQ-COM-007): it moves nothing except
    // the fact that something arrived.
    private func wellFormedMessage() throws -> MessageLinkEvent {
        .message(try MessageCoder.encode(Envelope(body: ServerMessage.timeSyncPong(TimeSyncPayload(t1: Date())))))
    }

    // Nothing a decoder can make sense of. REQ-ERR-009 throws it away; nine in a row keep the line.
    private var brokenMessage: MessageLinkEvent { .message(Data("{ this is not a message".utf8)) }

    // MARK: - Letting the beat run

    // Long enough for many beats of `quickBeat` to have passed, which is what makes "it did not
    // happen" mean anything.
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    // The same wait, with the beat counted on either side of it. **A watch that never ran would
    // also cut nothing**, so every "it was not cut" below is measured against a loop that came
    // round, looked at the silence, and let the line stand.
    private func letTheBeatRun(of client: MdoroClient) async {
        let before = client.beats
        await pause()
        #expect(await waitUntil({ client.beats > before }, upTo: 2),
                "the keepalive never came round, so nothing that did not happen proves anything")
    }

    private func waitUntil(_ condition: () -> Bool, upTo seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - The watch

    @Test func fifteenSecondsWithNothingArrivingEndsTheLineAndOpensAnother() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        clock.advance(by: Heartbeat.timeout + 0.1)

        #expect(await waitUntil({ line.cancels == 1 }, upTo: 2),
                "fifteen seconds of silence left the line open")
        #expect(line.endings == 1, "one line ended once")
        // REQ-COM-004: the reconnect is the one that hangs off `.ended`. **Silence adds no second
        // way in** — it hangs up, and the ending does the rest.
        #expect(await waitUntil({ links.opened.count == 2 }, upTo: ReconnectPolicy.initialDelay + 3),
                "the line was ended and nothing was opened in its place")
    }

    @Test func fourteenSecondsIsNotSilenceEnough() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        clock.advance(by: Heartbeat.timeout - 1)
        await letTheBeatRun(of: client)

        #expect(line.cancels == 0, "a connection was cut a second before the requirement says to")
        #expect(links.opened.count == 1, "a live connection was replaced")
    }

    // **What arrives is what is counted, not what it says.** The Mac sends no heartbeat back
    // (10.2), so the phone's proof of life is receipt itself.
    @Test func anythingThatArrivesPutsTheFifteenSecondsBack() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        clock.advance(by: Heartbeat.timeout - 1)
        line.deliver(try wellFormedMessage())
        clock.advance(by: Heartbeat.timeout - 1)
        await letTheBeatRun(of: client)

        #expect(line.cancels == 0, "twenty-eight seconds with a message in the middle were added up as silence")

        // And from that message, the fifteen seconds run again.
        clock.advance(by: 2)
        #expect(await waitUntil({ line.cancels == 1 }, upTo: 2),
                "the silence after the last message never ended the line")
    }

    // REQ-ERR-009 decides what to do with rubbish — one is thrown away, ten in a row remake the
    // line. **For REQ-COM-005 it still counts**: a peer emitting rubbish is a peer that is there.
    @Test func evenAMessageThatCannotBeReadIsProofTheMacIsThere() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        clock.advance(by: Heartbeat.timeout - 1)
        line.deliver(brokenMessage)
        clock.advance(by: Heartbeat.timeout - 1)
        await letTheBeatRun(of: client)

        #expect(line.cancels == 0, "a message that could not be read was counted as silence")
    }

    // `Heartbeat.isStale(lastReceivedAt: nil, …)` is true, and it should be: to the Mac's monitor
    // a client that has never spoken is not there. **On this side the watch starts from a message
    // that arrived**, so a connection is never cut at the first look after it stands.
    @Test func aConnectionThatHasJustStoodIsNotCutAtOnce() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        // The clock is not moved: the watch runs many times over a connection no older than the
        // milliseconds this test takes, and finds nothing to act on every time.
        await letTheBeatRun(of: client)

        #expect(line.cancels == 0, "the connection was ended before a second of it had passed")
        #expect(links.opened.count == 1, "the connection was ended before a second of it had passed")
    }

    // The watch has the keepalive's lifetime: no connection, no watch.
    //
    // **The loop is watched here, not only what it would have done.** Everything the loop reaches
    // for goes through `link`, which a disconnect clears in the same breath, so a loop left turning
    // for the life of the app sends nothing and cancels nothing — and is invisible except in the
    // count of its own rounds.
    @Test func nothingIsWatchedAfterDisconnect() async throws {
        let links = SilentLines()
        let clock = MovableClock()
        let client = try connectedClient(over: links, on: clock)
        let line = try #require(links.opened.first)
        await letTheBeatRun(of: client)

        client.disconnect()
        let beatsAtDisconnect = client.beats
        let cancelsAtDisconnect = line.cancels
        let sentAtDisconnect = line.sent.count
        clock.advance(by: Heartbeat.timeout * 4)
        await pause()

        #expect(client.beats == beatsAtDisconnect, "the keepalive went on turning after disconnect")
        #expect(line.cancels == cancelsAtDisconnect, "a line nobody is holding was hung up on again")
        #expect(line.sent.count == sentAtDisconnect, "the keepalive went on beating after disconnect")
        #expect(links.opened.count == 1, "disconnect was followed by a reconnect")
    }

    // MARK: - The beat nobody sets

    // REQ-COM-005: five seconds, wherever the beat is not being driven by a test. Every test above
    // passes `heartbeatInterval` in, so this is the one place the production default is read.
    // **The five seconds themselves are pinned on `Heartbeat.interval`**, which the Mac beats to
    // as well (REQ-PRT-001).
    @Test func theBeatIsFiveSecondsWhereNobodyHasShortenedIt() {
        let client = MdoroClient(tokens: NoTokenHere(), links: SilentLines())

        #expect(client.heartbeatInterval == Heartbeat.interval,
                "the phone beats to something other than the interval the requirement names")
    }
}
