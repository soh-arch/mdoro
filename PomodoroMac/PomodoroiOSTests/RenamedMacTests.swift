import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroiOS

// REQ-COM-003 / REQ-COM-004: **a Mac renamed while connected is dialled under its new name.**
// The old registration resolves to nothing once the Mac has re-registered, so a client that kept
// it would retry on the backoff for ever. The TXT `id` is what identifies the Mac.

@MainActor
private final class Line: MessageLink {
    private var onEvent: ((MessageLinkEvent) -> Void)?
    private var ended = false
    func start(onEvent: @escaping (MessageLinkEvent) -> Void) { self.onEvent = onEvent }
    func send(_ data: Data) {}
    func cancel() { end() }
    func end() {
        guard !ended else { return }
        ended = true
        onEvent?(.ended)
    }
}

@MainActor
private final class Lines: ClientLinkMaking {
    private(set) var dialled: [DiscoveredServer] = []
    private(set) var opened: [Line] = []
    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        dialled.append(server)
        let line = Line()
        opened.append(line)
        return line
    }
}

private struct NoTokens: TokenStoring {
    func load(serverId: ServerID) -> String? { nil }
    func save(_ token: String, serverId: ServerID) {}
    func delete(serverId: ServerID) {}
}

private func mac(_ name: String, _ serverId: ServerID?) -> DiscoveredServer {
    DiscoveredServer(
        id: name, name: name,
        endpoint: .service(name: name, type: BonjourService.type, domain: "local.", interface: nil),
        websocketPort: nil,
        serverId: serverId
    )
}

private let noCallbacks = MdoroClient.Callbacks(
    statusChanged: { _ in }, receivedSnapshot: { _ in }, receivedTaskList: { _ in },
    receivedEvent: { _ in }, receivedError: { _ in }, issuedToken: { _, _ in }
)

@Suite("A renamed Mac is followed by its id (REQ-COM-003 / REQ-COM-004)")
@MainActor
struct RenamedMacTests {

    @Test func theRetryAfterARenameDialsTheNewName() async throws {
        let id = ServerID.generate()
        let lines = Lines()
        let client = MdoroClient(tokens: NoTokens(), links: lines)
        client.connect(to: mac("Guava", id), callbacks: noCallbacks)
        lines.opened[0].end()                                // the old registration goes away

        client.follow([mac("Guava (2)", id)])
        #expect(client.target?.id == "Guava (2)")

        // The backoff's first rung is one second (REQ-COM-004).
        try await Task.sleep(for: .milliseconds(1500))
        #expect(lines.dialled.map(\.id) == ["Guava", "Guava (2)"])
        client.disconnect()
    }

    @Test func anotherMacIsNotFollowed() {
        let client = MdoroClient(tokens: NoTokens(), links: Lines())
        client.connect(to: mac("Guava", .generate()), callbacks: noCallbacks)
        client.follow([mac("Mango", .generate())])
        #expect(client.target?.id == "Guava")
        client.disconnect()
    }

    @Test func theTargetStaysWhileItIsStillListed() {
        let id = ServerID.generate()
        #expect(MdoroClient.successor(of: mac("Guava", id), in: [mac("Guava (2)", id), mac("Guava", id)]) == nil)
    }

    @Test func aMacWithNoIdIsNotFollowed() {
        #expect(MdoroClient.successor(of: mac("Guava", nil), in: [mac("Guava (2)", nil)]) == nil)
    }

    @Test func aClientThatWasToldToStopDoesNotMove() {
        let id = ServerID.generate()
        let client = MdoroClient(tokens: NoTokens(), links: Lines())
        client.connect(to: mac("Guava", id), callbacks: noCallbacks)
        client.disconnect()
        client.follow([mac("Guava (2)", id)])
        #expect(client.target?.id == "Guava")
    }
}
