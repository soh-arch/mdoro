import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroiOS

// A line the test holds both ends of. It records what went out and hands in what "arrived";
// nothing is dialled, so the run stays off the LAN entirely.
@MainActor
private final class RecordedLink: MessageLink {
    private(set) var sent: [Data] = []
    private(set) var cancels = 0
    private var onEvent: ((MessageLinkEvent) -> Void)?

    func start(onEvent: @escaping (MessageLinkEvent) -> Void) { self.onEvent = onEvent }
    func send(_ data: Data) { sent.append(data) }
    func cancel() { cancels += 1 }

    func deliver(_ event: MessageLinkEvent) { onEvent?(event) }
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

// POL-047: the suite runs inside MdoroiOS.app, so a real Keychain read would be the reader's own.
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

    // REQ-PRT-005: a type this version does not know. Well formed, and not corruption.
    private var messageFromALaterVersion: Data {
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

    @Test func theTenthBrokenMessageEndsTheLineAndOpensAnother() async throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1...BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }

        #expect(line.cancels >= 1, "the tenth broken message left the line open")
        let another = await opened(links, reaches: 2, within: ReconnectPolicy.initialDelay + 4)
        #expect(another, "the line was ended and nothing was opened in its place")
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
    // ignored, and the run starts over — the peer is speaking this protocol, only a later one.
    @Test func aMessageFromALaterVersionIsNotABrokenOne() throws {
        let links = RecordedLinks()
        let client = connectedClient(over: links)
        defer { client.disconnect() }
        let line = try #require(links.opened.first)
        line.deliver(.ready)

        for _ in 1..<BrokenMessageCounter.limit { line.deliver(.message(brokenMessage)) }
        line.deliver(.message(messageFromALaterVersion))
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
