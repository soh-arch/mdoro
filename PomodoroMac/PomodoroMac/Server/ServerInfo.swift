import Foundation
import Network
import MdoroCore

// REQ-COM-002: fetching the server information after Bonjour discovery.
// **It asks for no authentication, and in return carries no state and no settings at all.** Anyone on
// the LAN can hit it.
struct ServerInfo: Codable, Equatable, Sendable {
    var serverName: String
    var protocolVersion: Int
    var isPairingMode: Bool
    // The port the WebSocket used for syncing listens on.
    var websocketPort: UInt16
}

// The smallest possible HTTP server. It answers `GET /info` and nothing else.
// Riding on the same port as the WebSocket would mean writing the handshake by hand, so
// **HTTP listens on a port of its own, and that is the one Bonjour advertises.**
final class InfoHTTPServer: @unchecked Sendable {
    // POL-114: **this is the listener that carries the Bonjour registration** (`advertise` sets its
    // `.service`), so it is the one whose replacement was leaving duplicate names on the network.
    // Readable so a test can see the old one cancelled rather than merely dropped.
    private(set) var listener: NWListener?
    private let queue = DispatchQueue(label: "MdoroMac.InfoHTTP")

    // **The answer is assembled on the network side's queue.** The MainActor's state cannot be read
    // from there. Try to read it with `MainActor.assumeIsolated` and it traps and crashes (it did
    // crash). The values are pushed in instead, and the answering side only reads them through a lock.
    private let lock = NSLock()
    private var info: ServerInfo

    private(set) var port: UInt16?

    init(info: ServerInfo) {
        self.info = info
    }

    func update(_ info: ServerInfo) {
        lock.lock(); defer { lock.unlock() }
        self.info = info
    }

    private var currentInfo: ServerInfo {
        lock.lock(); defer { lock.unlock() }
        return info
    }

    // POL-114 / REQ-COM-003: **the previous listener is withdrawn before a new one goes up.** Cancelling
    // it is what takes the Bonjour name off the network; overwriting the property alone left the old
    // registration standing and mDNSResponder gave the new one a `(2)`. The tidying up is `stop()`'s.
    @discardableResult
    func start() async throws -> UInt16 {
        stop()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        self.listener = listener

        let port = try await ListenerReadiness.awaitReady(listener, on: queue)
        self.port = port
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    // Advertised over Bonjour (REQ-COM-003). The type and the TXT keys are `BonjourService`'s,
    // so the browsing side reads what this side wrote.
    //
    // Decision 0040: **the name and the identity are two arguments now.** The name is whatever
    // the user typed (`displayName`) and mDNSResponder may append ` (2)` to it; the `id` is what
    // the iPhone files its token under, and nothing rewrites that.
    func advertise(displayName: String, websocketPort: UInt16, serverId: ServerID) {
        listener?.service = NWListener.Service(
            name: displayName,
            type: BonjourService.type,
            txtRecord: NWTXTRecord(
                BonjourService.txtEntries(websocketPort: websocketPort, serverId: serverId)
            )
        )
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> Data {
        let requestLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        guard requestLine.hasPrefix("GET /info") else {
            return Self.httpResponse(status: "404 Not Found", body: Data())
        }
        let body = (try? MessageCoder.encoder.encode(currentInfo)) ?? Data()
        return Self.httpResponse(status: "200 OK", body: body, contentType: "application/json")
    }

    private static func httpResponse(status: String, body: Data, contentType: String = "text/plain") -> Data {
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        return Data(headers.utf8) + body
    }
}
