import Foundation
import Network
import MdoroCore

// REQ-COM-003 / REQ-ERR-005: the Mac is found over Bonjour. More than one can be found and chosen
// between, so they are held in an array.
struct DiscoveredServer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    // The sync port carried in the TXT record (REQ-COM-002).
    let websocketPort: UInt16?

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ServerBrowser {
    private var browser: NWBrowser?
    private(set) var servers: [DiscoveredServer] = []

    var onChange: (([DiscoveredServer]) -> Void)?
    // REQ-PLT-008 / REQ-ERR-014: there is no API to ask about the permission. It is detected from
    // NWBrowser's -65570.
    var onLocalNetworkDenied: (() -> Void)?

    func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_mdoro._tcp", domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard case let .failed(error) = state else { return }
            // -65570 (NoAuth) is a sign that the local network is not allowed.
            if case let .dns(code) = error, code == -65570 {
                Task { @MainActor in self?.onLocalNetworkDenied?() }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = Self.deduplicated(results.compactMap { Self.server(from: $0) })
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

    // **The same Mac can be seen more than once, as "Name", "Name (2)", "Name (3)".**
    // When the process ends unexpectedly the Bonjour registration does not go away at once, and macOS
    // numbers it afresh. **The older one has the smaller number.** They are bundled under the name with
    // the number taken off, and only the newest is kept.
    nonisolated static func deduplicated(_ servers: [DiscoveredServer]) -> [DiscoveredServer] {
        var newest: [String: (suffix: Int, server: DiscoveredServer)] = [:]
        var order: [String] = []
        for server in servers {
            let (base, suffix) = splitDuplicateSuffix(server.name)
            if newest[base] == nil { order.append(base) }
            if let existing = newest[base], existing.suffix >= suffix { continue }
            newest[base] = (suffix, DiscoveredServer(
                id: server.id, name: base, endpoint: server.endpoint, websocketPort: server.websocketPort
            ))
        }
        return order.compactMap { newest[$0]?.server }
    }

    // "Name (3)" -> ("Name", 3), "Name" -> ("Name", 1)
    nonisolated static func splitDuplicateSuffix(_ name: String) -> (base: String, suffix: Int) {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return (name, 1) }
        let inside = name[name.index(after: open)..<name.index(before: name.endIndex)]
        guard let number = Int(inside), number > 1 else { return (name, 1) }
        let base = name[name.startIndex..<open].trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? name : base, number)
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
