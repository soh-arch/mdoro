import Foundation

// REQ-UIX-004: only the distinctions the connection display needs are shared.
//
// **The cases and their roles are shared; the words are not** (Decision 0022). The words each platform shows live
// in its own `Format`, so they reach a String Catalog; a package has no catalogue to reach, so
// wording kept here would have to be written a second time on the iPhone anyway.
public enum ConnectionStatus: String, Equatable, Sendable, Codable, CaseIterable {
    case connected
    case reconnecting
    case disconnected

    // REQ-COL-010: never colour alone. The normal screen adds an icon of a different shape to the colour.
    public var symbolName: String {
        switch self {
        case .connected: return "iphone.gen3"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "iphone.gen3.slash"
        }
    }

    // REQ-UIX-004: **the peer device, as seen from the side that shows it.** Using `symbolName` on
    // both ends points at the wrong device. `SymbolNameTests` checks that these names exist.
    public var peerSymbolName: String {
        #if os(macOS)
        switch self {
        case .connected: return "iphone.gen3"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "iphone.gen3.slash"
        }
        #else
        switch self {
        case .connected: return "laptopcomputer"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "laptopcomputer.slash"
        }
        #endif
    }

    public var colorRole: ColorRole {
        switch self {
        case .connected: return .success
        case .reconnecting: return .warning
        case .disconnected: return .danger
        }
    }
}
