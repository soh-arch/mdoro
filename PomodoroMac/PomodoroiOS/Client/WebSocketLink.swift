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

    // REQ-COM-003 / POL-143: dial the discovered service itself. Network.framework resolves a
    // `.service` endpoint by instance name at connect time, so the address and port are whatever
    // the Mac is advertising right now — and since the advertisement rides on the ws listener,
    // the service resolves to the ws port. What stood here dialled "\(instanceName).local": an
    // mDNS host name and an instance name are unrelated, and the two matched only while the
    // instance name happened to be the computer's name. Once the default became "Mdoro", the
    // guess pointed at a host that does not exist.
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
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil { self.deliver(.ended); return }
                // A ping or a close frame is not a protocol message.
                if let data, !data.isEmpty,
                   let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .text || metadata.opcode == .binary {
                    self.deliver(.message(data))
                }
                self.receive()
            }
        }
    }

    private func deliver(_ event: MessageLinkEvent) {
        if case .ended = event { openLine = nil }
        onEvent?(event)
    }
}
