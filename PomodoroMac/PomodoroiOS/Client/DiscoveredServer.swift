import Foundation
import Network
import MdoroCore

// REQ-COM-003 / REQ-ERR-005: the Mac is found over Bonjour. More than one can be found and chosen
// between, so they are held in an array.
struct DiscoveredServer: Identifiable, Equatable, Sendable {
    // The Bonjour instance name. **It identifies a registration, not a Mac** — mDNSResponder
    // rewrites it on a collision — so it is what tells two rows of the list apart and nothing more.
    let id: String
    let name: String
    let endpoint: NWEndpoint
    // The ws port carried in the TXT record (REQ-COM-002). **Kept on the wire for protocol
    // compatibility, and no longer used to dial** (POL-143): the connection goes to the
    // `.service` endpoint, which resolves to the port the advertisement rides on.
    let websocketPort: UInt16?
    // REQ-COM-003 / Decision 0040: **what identifies the Mac.** nil when the advertisement carries
    // no `id`, which means a version that predates this one — such a Mac is still listed, and
    // refuses the connection itself on the version check (REQ-PRT-004), rather than vanishing
    // from the list with nothing said.
    let serverId: ServerID?

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
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: BonjourService.type, domain: nil), using: parameters)

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
    // The number stays on screen because it is what tells two rows apart to the eye. **What tells
    // them apart to the app is the TXT `id`** (Decision 0040), which is why a rename by
    // mDNSResponder no longer costs a pairing — but nobody can read an id off a list, so the
    // name, number and all, is still what is shown.
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
        var details: (websocketPort: UInt16?, serverId: ServerID?) = (nil, nil)
        if case let .bonjour(record) = result.metadata { details = read(record) }
        return DiscoveredServer(
            id: name, name: name, endpoint: result.endpoint,
            websocketPort: details.websocketPort, serverId: details.serverId
        )
    }

    // Apart from `server(from:)` because an `NWBrowser.Result` cannot be built by hand and an
    // `NWTXTRecord` can. What a Mac put on the air is the half worth checking.
    nonisolated static func read(_ record: NWTXTRecord) -> (websocketPort: UInt16?, serverId: ServerID?) {
        (
            text(record, BonjourService.websocketPortKey).flatMap(UInt16.init),
            // Decision 0040: anything that is not a UUID is not an id. What arrives here was
            // written by whoever is on the LAN, and it ends up as a Keychain account name.
            text(record, BonjourService.identityKey).flatMap(ServerID.init)
        )
    }

    nonisolated private static func text(_ record: NWTXTRecord, _ key: String) -> String? {
        guard let entry = record.getEntry(for: key), case let .string(value) = entry else { return nil }
        return value
    }
}
