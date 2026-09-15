import Foundation
import Network
import MdoroCore

// REQ-COM-003: how the iPhone opens a line to a Mac it discovered.
//
// **The same seam as `TokenStoring`:** a protocol, a real implementation that is the default, and
// a substitute chosen where the client is built. Here it buys the one thing an `NWConnection`
// cannot give — a line that carries bytes without a LAN under it — so that what the client does
// with what arrives can be driven from a test.
protocol ClientLinkMaking: Sendable {
    // nil when this server cannot be dialled at all.
    @MainActor func makeLink(to server: DiscoveredServer) -> (any MessageLink)?
}

// Nothing is held here, and it is built where the client is built — off the main actor as
// readily as on it.
nonisolated struct WebSocketLinks: ClientLinkMaking {

    // REQ-COM-003: **the dial is the discovered `.service` endpoint itself, never a name built
    // from it.** A Bonjour instance name and an mDNS host name are separate name spaces, so an
    // instance name with `.local` appended names nobody except where the two happen to coincide.
    // Network.framework resolves the service by instance name at connect time, which is what makes
    // the address and port the ones the Mac is advertising at that moment; and since the
    // advertisement rides on the ws listener, the service resolves to the ws port.
    static func dialEndpoint(for server: DiscoveredServer) -> NWEndpoint? {
        guard case .service = server.endpoint else { return nil }
        return server.endpoint
    }

    @MainActor
    func makeLink(to server: DiscoveredServer) -> (any MessageLink)? {
        guard let endpoint = Self.dialEndpoint(for: server) else { return nil }
        return WebSocketLink(endpoint: endpoint)
    }
}

// REQ-COM-004: what one read off the line means, decided apart from the reading itself.
//
// **It is separated so it can be answered without a LAN.** An `NWConnection` dials the moment it
// is started, so while this decision lived inside the read callback there was nowhere to stand and
// ask it — the same reason `MessageLink` exists at all.
enum LineRead: Equatable {
    // A protocol message arrived. Hand it up, then read again.
    case message(Data)
    // Something arrived that this layer has nothing to say about: a ping the transport answered by
    // itself, a frame carrying no payload. Read again.
    case skip
    // Nothing more will arrive on this line. **Do not read again.**
    case end

    // REQ-COM-004: **a line that is over has to say so here as well.** The reconnect hangs off
    // `.ended` and nothing else reaches it, and the state handler does not see every ending: a peer
    // that closes politely leaves the connection `.ready`, so no `.failed` and no `.cancelled`
    // follow and the read is the only place the ending is told.
    //
    // Three endings, asked in this order:
    //
    // 1. **A read that failed.** Whatever it was, nothing more is coming.
    // 2. **A close frame.** The polite ending above. It ends the line whether or not it carries a
    //    status code as its payload.
    // 3. **A completed read with no frame on it and no bytes** — the end of the line as the
    //    transport reports it when there was no close frame to hand over.
    //
    // **The third asks for the read to be empty and unframed on purpose.** On a message-oriented
    // protocol `isComplete` is true of every whole message, so taken on its own it would end the
    // line at the first thing the Mac ever said. What marks an ending is that nothing came with it,
    // and a read carrying bytes is never read as one.
    //
    // The Mac's own test harness reads a line the same way and says why it must
    // (`ServerUnderARealConnectionTests.receive`): a read that completes with nothing on it re-arms
    // into another that completes with nothing at once, so a loop with no ending to stop it spins
    // for as long as the process lives.
    static func of(
        data: Data?, opcode: NWProtocolWebSocket.Opcode?, isComplete: Bool, failed: Bool
    ) -> LineRead {
        if failed { return .end }
        if opcode == .close { return .end }
        if let data, !data.isEmpty, opcode == .text || opcode == .binary { return .message(data) }
        if isComplete, opcode == nil, data?.isEmpty ?? true { return .end }
        return .skip
    }
}

// REQ-COM-001: the client's end of the WebSocket, over Network.framework.
@MainActor
final class WebSocketLink: MessageLink {

    private let connection: NWConnection
    private var onEvent: ((MessageLinkEvent) -> Void)?
    // The line holds itself while it is open and lets go once it has ended, so a caller that has
    // already moved on to the next line still hears this one finish.
    private var openLine: WebSocketLink?
    private var hasEnded = false

    init(endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        connection = NWConnection(to: endpoint, using: parameters)
    }

    func start(onEvent: @escaping (MessageLinkEvent) -> Void) {
        self.onEvent = onEvent
        openLine = self
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready: self?.deliver(.ready)
                case .failed, .cancelled: self?.deliver(.ended)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        // **A line that is over does not ask for more.** A read on a finished connection comes back
        // immediately and with nothing on it, so a loop that re-armed regardless would turn on the
        // main actor for as long as the app lived, next to the watch that shares it
        // (`MdoroClient.endLineIfSilent`).
        guard !hasEnded else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata
                switch LineRead.of(
                    data: data, opcode: metadata?.opcode, isComplete: isComplete, failed: error != nil
                ) {
                case let .message(message):
                    self.deliver(.message(message))
                case .skip:
                    break
                case .end:
                    self.deliver(.ended)
                    return
                }
                self.receive()
            }
        }
    }

    // `MessageLinkEvent.ended` is delivered once and is the last thing said. One ending reaches
    // here by more than one road — a read that fails, `.failed` or `.cancelled` from the state
    // handler, both at once when the line is cancelled while a read is outstanding — and the
    // contract is one event per ending.
    private func deliver(_ event: MessageLinkEvent) {
        guard !hasEnded else { return }
        if case .ended = event {
            hasEnded = true
            openLine = nil
            // REQ-COM-004: **the connection is handed back, not merely let go of.** Two of the
            // endings above reach here without anyone having cancelled anything — a read that
            // failed, and a peer that closed politely — and an `NWConnection` nobody cancels keeps
            // its endpoint and its path monitor for as long as it is held. Cancelling one that is
            // already cancelled does nothing, so the ending that arrives by way of `cancel()`
            // costs a second call and no more. The `.cancelled` this raises finds `hasEnded`
            // already set and is not told twice.
            connection.cancel()
        }
        onEvent?(event)
    }

    // REQ-COM-004: the same hand-back for a line that is let go without ever having ended — one
    // made and never started, or one dropped while it was still dialling.
    //
    // **It is not the main defence, because an open line holds itself** (`openLine`), so this runs
    // only after the ending has already cancelled the connection, or for a line that never began.
    deinit {
        connection.cancel()
    }
}
