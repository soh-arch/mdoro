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

// REQ-COM-001: the client's end of the WebSocket, over Network.framework.
@MainActor
final class WebSocketLink: MessageLink {

    private let connection: NWConnection
    private var onEvent: ((MessageLinkEvent) -> Void)?
    // The line holds itself while it is open and lets go once it has ended, so a caller that has
    // already moved on to the next line still hears this one finish.
    private var openLine: WebSocketLink?
    private var hasEnded = false
    // REQ-ERR-009: **set the moment someone hangs up, which is before the line has ended.**
    // `cancel()` is a request; the ending comes back later and by another road. Between the two,
    // `hasEnded` is still false and the read loop would re-arm on a line nobody means to read from
    // again — see `receive()`.
    private var isHungUp = false

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
        isHungUp = true
        connection.cancel()
    }

    private func receive() {
        // **A line that is over does not ask for more.** A read on a finished connection comes back
        // immediately and with nothing on it, so a loop that re-armed regardless would turn on the
        // main actor for as long as the app lived, next to the watch that shares it
        // (`MdoroClient.endLineIfSilent`).
        //
        // REQ-ERR-009: **and neither does a line that has just been hung up on.** The tenth broken
        // message in a row is answered with `cancel()` from inside `MdoroClient.handle`, which runs
        // inside the read below — so control comes back here with the cancel merely asked for and
        // the ending not yet delivered. `hasEnded` cannot cover that gap; it is set when `.ended`
        // goes out, and the whole point is that `.ended` has not gone out yet.
        //
        // **It is the hang-up that is guarded on, not the reason for it.** The same gap belongs to
        // every caller of `cancel()` reached from inside a read — `stopDialling` on a refusal
        // (REQ-COM-004), `disconnect` — and the Mac answers the same question in the same place
        // (`MdoroServer.receive(on:counting:)`, "a line that has just been hung up on is not read
        // from again").
        guard !hasEnded, !isHungUp else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // REQ-PRT-001: what this read means is decided in `MdoroCore`, by the same function
                // the Mac's read loop calls.
                switch LineRead.of(
                    data: data, frame: context?.webSocketFrame, isComplete: isComplete,
                    failed: error != nil
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
