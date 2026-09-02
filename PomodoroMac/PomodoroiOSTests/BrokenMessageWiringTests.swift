import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroiOS

// A line the test holds both ends of. It records what went out and hands in what "arrived";
// nothing is dialled, so the run stays off the LAN entirely.
//
// **It keeps `MessageLink`'s contract about endings**, because that is what the client is entitled
// to expect: a cancelled line reports `.ended`, and `.ended` is delivered once and last. A double
// that took a cancel in silence would be a line no implementation of this protocol is allowed to
// be, and the wiring checked here would be somebody else's.
@MainActor
private final class RecordedLink: MessageLink {
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
private final class RecordedLinks: ClientLinkMaking {
    private(set) var opened: [RecordedLink] = []

    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        let link = RecordedLink()
        opened.append(link)
        return link
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

// REQ-ERR-009: one broken message is thrown away and the connection kept; **ten in a row** mean
// the line itself is no good, and it is made again.
//
// `BrokenMessageCounterTests` checks the counting. This checks that the counting is wired to
// anything at all: that a message which fails to decode is what advances the count, and that
// reaching ten ends the line and asks REQ-COM-004 for another.
@Suite("Ten broken messages remake the connection (REQ-ERR-009)")
@MainActor
struct BrokenMessageWiringTests {

    // MARK: - The client, on a line the test drives

    private func discoveredMac() -> DiscoveredServer {
        DiscoveredServer(
            id: "Mdoro", name: "Mdoro",
            endpoint: .service(name: "Mdoro", type: BonjourService.type, domain: "local.", interface: nil),
            websocketPort: 51234, serverId: .generate()
        )
    }

    private func connectedClient(over links: RecordedLinks) -> MdoroClient {
        let client = MdoroClient(tokens: NoTokenHere(), links: links)
        client.connect(
            to: discoveredMac(),
            // With neither a token nor a code, the client stops to ask for one (REQ-SEC-001).
            pairingCode: "123456",
            callbacks: MdoroClient.Callbacks(
                statusChanged: { _ in }, receivedSnapshot: { _ in }, receivedTaskList: { _ in },
                receivedEvent: { _ in }, receivedError: { _ in }, issuedToken: { _, _ in }
            )
        )
        return client
    }

    // MARK: - What arrives

    // Nothing a decoder can make sense of.
    private var brokenMessage: Data { Data("{ this is not a message".utf8) }

    // A pong with no t2 or t3 is read and then set aside (REQ-COM-007), so nothing but the count moves.
    private func wellFormedMessage() throws -> Data {
        try MessageCoder.encode(Envelope(body: ServerMessage.timeSyncPong(TimeSyncPayload(t1: Date()))))
    }

    // The Mac's answer to the hello (REQ-SEC-004). **The one message that proves the line carries
    // this protocol**, which is why REQ-COM-004 winds the backoff back on it and on nothing else.
    private func welcomeMessage() throws -> Data {
        try MessageCoder.encode(Envelope(body: ServerMessage.welcome(
            WelcomePayload(deviceToken: "a token this test throws away", serverName: "Mdoro")
        )))
    }

    // REQ-PRT-005: a type this version does not know. Well formed, and not corruption.
    private var messageNamingATypeThisVersionLacks: Data {
        Data("""
        {"type":"somethingThisVersionHasNeverHeardOf",\
        "messageId":"8B0E6C22-1F3A-4D55-9C77-000000000001",\
        "sentAt":"2026-09-02T10:00:00Z"}
        """.utf8)
    }

    // REQ-COM-004: the new connection is not immediate — the backoff is waited out first.
    private func opened(_ links: RecordedLinks, reaches count: Int, within seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if links.opened.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return links.opened.count >= count
    }

    // How long the client waited before opening line number `count`, or nil if it never did.
    //
    // REQ-COM-004 names the waits — one second, then two — so **the length of the wait is how many
    // steps the backoff took.** A disconnect counted twice shows up here as a doubled wait.
    private func waitBeforeLine(_ count: Int, on links: RecordedLinks, upTo seconds: TimeInterval) async -> TimeInterval? {
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

    // MARK: - The wiring

    @Test func theNinthBrokenMessageLeavesTheLineAlone() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }

        #expect(line.cancels == 0, "the connection is kept until the tenth")
        let another = await opened(links, reaches: 2, within: ReconnectPolicy.initialDelay + 0.5)
        #expect(another == false, "nine broken messages asked for a new connection")
    }

    @Test func theTenthBrokenMessageEndsTheLineAndOpensAnotherOneSecondLater() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1...BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }

        #expect(line.cancels == 1, "the tenth broken message left the line open")
        #expect(line.endings == 1, "one line ended once")
        let waited = try #require(
            await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4),
            "the line was ended and nothing was opened in its place"
        )
        // REQ-COM-004: one second the first time. **Hanging up and the line ending are one
        // disconnect**, and a disconnect counted twice would have waited two seconds.
        #expect(isAbout(waited, ReconnectPolicy.initialDelay),
                "the first retry after a disconnect is one second (waited \(waited))")
        // Read the moment the second line appeared: one reconnect, one line, not two at once.
        // **That there is no third line waiting a step further up is what the wait above says** —
        // a second step would have taken two seconds to arrive.
        #expect(links.opened.count == 2, "the reconnect opened more than one line at once")
    }

    // REQ-COM-004: the ladder itself is `ReconnectPolicy`'s (`ReconnectTests` in MdoroCore pins
    // 1, 2, 4 … 30). What is checked here is how far up it the client climbs: **one step per
    // disconnect**, so the second wait is two seconds and not four.
    @Test func eachDisconnectMovesTheBackoffOneStep() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let first = try #require(links.opened.first)
        first.deliver(.ready)

        for _ in 1...BrokenMessageCounter.limit { first.deliver(.message(brokenMessage)) }
        _ = try #require(await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4))

        let second = try #require(links.opened.last)
        second.deliver(.ready)
        for _ in 1...BrokenMessageCounter.limit { second.deliver(.message(brokenMessage)) }

        let waited = try #require(
            await waitBeforeLine(3, on: links, upTo: ReconnectPolicy.initialDelay * 2 + 4),
            "the second disconnect opened nothing in its place"
        )
        #expect(isAbout(waited, ReconnectPolicy.initialDelay * 2),
                "the second disconnect is one step up the backoff, not two (waited \(waited))")
    }

    // REQ-COM-004's other half: **a `welcome` puts the backoff back to the start.** `ReconnectTests`
    // in MdoroCore pins what `ReconnectPolicy.reset()` does; what is checked here is that the client
    // calls it when the Mac answers. Same disconnects as the test above, one `welcome` in between —
    // and the wait is a second again rather than two.
    @Test func aWelcomePutsTheBackoffBackToTheStart() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let first = try #require(links.opened.first)
        first.deliver(.ready)

        for _ in 1...BrokenMessageCounter.limit { first.deliver(.message(brokenMessage)) }
        _ = try #require(await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4))

        let second = try #require(links.opened.last)
        second.deliver(.ready)
        second.deliver(.message(try welcomeMessage()))
        for _ in 1...BrokenMessageCounter.limit { second.deliver(.message(brokenMessage)) }

        let waited = try #require(
            await waitBeforeLine(3, on: links, upTo: ReconnectPolicy.initialDelay * 2 + 4),
            "the second disconnect opened nothing in its place"
        )
        #expect(isAbout(waited, ReconnectPolicy.initialDelay),
                "a line that got as far as a welcome starts the backoff over (waited \(waited))")
    }

    // The other way a line ends: nobody hung up, the network went away. **The end of the line is
    // the whole of what starts a reconnect**, so this path carries the requirement on its own —
    // there is nothing else in it to fall back on if the event stops being acted upon.
    @Test func aLineThatSimplyDropsIsOpenedAgainAfterOneSecond() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        line.deliver(.ended)

        #expect(line.cancels == 0, "nobody hung up on this line")
        let waited = try #require(
            await waitBeforeLine(2, on: links, upTo: ReconnectPolicy.initialDelay + 4),
            "a dropped line was never opened again"
        )
        #expect(isAbout(waited, ReconnectPolicy.initialDelay),
                "REQ-COM-004: one second the first time (waited \(waited))")
        // Read the moment the second line appeared: one reconnect, one line, not two at once.
        // **That there is no third line waiting a step further up is what the wait above says** —
        // a second step would have taken two seconds to arrive.
        #expect(links.opened.count == 2, "the reconnect opened more than one line at once")
    }

    // REQ-ERR-009 says *in a row*. One message the client can read puts the count back to zero.
    @Test func oneMessageThatDecodesStartsTheRunOver() throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }
        line.deliver(.message(try wellFormedMessage()))
        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }

        #expect(line.cancels == 0, "nine and nine were added up as eighteen")
    }

    // REQ-PRT-005: forward compatibility is not corruption. A type this version does not know is
    // ignored, and the run starts over — the message arrived whole and was read, and there is
    // simply no case in this version's list to put it in.
    @Test func aTypeThisVersionDoesNotKnowIsNotABrokenOne() throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }
        line.deliver(.message(messageNamingATypeThisVersionLacks))
        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }

        #expect(line.cancels == 0, "a type this version does not know was counted as broken")
    }

    // What makes the rest of the suite mean anything: the client is speaking on the line it was
    // handed, so what the test delivers arrives where the LAN's bytes would.
    @Test func theClientSpeaksOnTheLineItWasGiven() throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)

        line.deliver(.ready)

        #expect(links.opened.count == 1)
        let first = try MessageCoder.decodeClient(try #require(line.sent.first))
        guard case .hello? = first?.body else {
            Issue.record("the first thing on a new line is not the hello (REQ-SEC-001)")
            return
        }
    }
}
