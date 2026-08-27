import Foundation
import Network
import PomodoroCore

// REQ-COM-003 / REQ-ERR-005: Bonjour で Mac を探す。
// 複数見つかった場合は一覧を提示してユーザーに選ばせるため、結果は配列で保持する。
struct DiscoveredServer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    // TXT レコードに載っている同期用ポート（REQ-COM-002）。
    let websocketPort: UInt16?

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ServerBrowser {
    private var browser: NWBrowser?
    private(set) var servers: [DiscoveredServer] = []

    var onChange: (([DiscoveredServer]) -> Void)?
    // REQ-PLT-008 / REQ-ERR-014: ローカルネットワーク許可を問い合わせる API は無い。
    // NWBrowser の -65570 で検出する。
    var onLocalNetworkDenied: (() -> Void)?

    func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_pomodoro._tcp", domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard case let .failed(error) = state else { return }
            // -65570 (NoAuth) はローカルネットワークが許可されていない徴候。
            if case let .dns(code) = error, code == -65570 {
                Task { @MainActor in self?.onLocalNetworkDenied?() }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { Self.server(from: $0) }
            Task { @MainActor in
                self?.servers = found
                self?.onChange?(found)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    nonisolated private static func server(from result: NWBrowser.Result) -> DiscoveredServer? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        var websocketPort: UInt16?
        if case let .bonjour(txt) = result.metadata, let raw = txt.getEntry(for: "ws") {
            if case let .string(value) = raw { websocketPort = UInt16(value) }
        }
        return DiscoveredServer(id: name, name: name, endpoint: result.endpoint, websocketPort: websocketPort)
    }
}
