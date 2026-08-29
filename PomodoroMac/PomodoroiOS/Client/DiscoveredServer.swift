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
    // REQ-PLT-008 / REQ-ERR-014: no public API answers whether the permission was granted
    // (`docs/PLATFORM.md`). It is detected from NWBrowser's -65570.
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
            let found = Self.inDisplayOrder(results.compactMap { Self.server(from: $0) })
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

    // REQ-ERR-005 / REQ-COM-003: **every registration the browser reported is offered, number
    // and all.** Nothing is folded together and no name is rewritten.
    //
    // One Mac can appear as "Name" and "Name (2)" at the same time: mDNSResponder renames a
    // colliding registration, and auto-rename is on by default (`docs/PLATFORM.md`). What used
    // to stand here bundled those under the bare name and kept the highest number, on the
    // belief that the older registration holds the smaller one. **It does not.** A number is
    // never handed back, so the survivor of a collision keeps its "(2)" and the next
    // registration takes the free "Name" — measured, not reasoned. Keeping the highest number
    // dropped the newest arrival, and dropped one of two Macs that were both answering.
    //
    // **A Mac that answers and is not offered is worse than a ghost that lingers.** An
    // abandoned registration is withdrawn about 1.7 seconds after its process is killed; how
    // long a stale one survives across the LAN has never been measured (`docs/PLATFORM.md`).
    // The number stays on screen because it is the only thing that tells two of them apart —
    // the advertisement carries no identifier of its own.
    //
    // The order is settled here because the browser hands back a Set. Without it the same
    // entries change places between callbacks, and a list that reorders itself under the
    // thumb cannot be chosen from.
    nonisolated static func inDisplayOrder(_ servers: [DiscoveredServer]) -> [DiscoveredServer] {
        servers.sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            // Finder's comparison sets case aside, so the instance name settles the rest.
            case .orderedSame: return lhs.id < rhs.id
            }
        }
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
