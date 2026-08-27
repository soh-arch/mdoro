import Foundation
import Network
import PomodoroCore

// REQ-COM-002: Bonjour 発見後のサーバー情報取得。
//
// **認証を要さない代わりに、状態や設定を一切含めない。**
// LAN 内の誰でも叩けるため、ここに状態を載せると REQ-SEC-003 が意味を失う。
struct ServerInfo: Codable, Equatable, Sendable {
    var serverName: String
    var protocolVersion: Int
    var isPairingMode: Bool
    // 同期用 WebSocket の待ち受けポート。
    var websocketPort: UInt16
}

// 最小の HTTP サーバー。`GET /info` だけに応じる。
//
// WebSocket と同じポートに相乗りさせると、Network.framework の自動アップグレードを外して
// ハンドシェイクを手で実装することになる。得るものに対して割に合わないため、
// **HTTP は別ポートで待ち受け、Bonjour はこちらを広告する**。
// クライアントは `/info` で WebSocket のポートを知る。
final class InfoHTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "MdoroMac.InfoHTTP")

    // **応答はネットワーク側のキューで組み立てられる。**
    // ここから MainActor の状態を読むと `MainActor.assumeIsolated` が落ちる（実際に落とした）。
    // 値を押し込む形にして、応答側はロック越しに読むだけにする。
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

    @discardableResult
    func start() async throws -> UInt16 {
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

    // Bonjour で広告する。サービス型は `_mdoro._tcp`（REQ-COM-003）。
    func advertise(serviceName: String, websocketPort: UInt16) {
        listener?.service = NWListener.Service(
            name: serviceName,
            type: "_mdoro._tcp",
            txtRecord: NWTXTRecord(["ws": String(websocketPort),
                                    "v": String(PomodoroProtocol.version)])
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
