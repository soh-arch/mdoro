import Foundation

// REQ-UIX-004: 接続状態の表示に必要な区分だけを共有する。
//
// **区分と役は共有し、言葉は共有しない**（Decision 0022）。The words each platform shows live
// in its own `Format`, so they reach a String Catalog; a package has no catalogue to reach,
// and the three words here were already written a second time on the iPhone.
public enum ConnectionStatus: String, Equatable, Sendable, Codable, CaseIterable {
    case connected
    case reconnecting
    case disconnected

    // REQ-COL-010: 色のみで区別しない。通常画面では色に加えて形の違うアイコンを添える。
    public var symbolName: String {
        switch self {
        case .connected: return "iphone.gen3"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "iphone.gen3.slash"
        }
    }

    // REQ-UIX-004: **表示する側から見た「相手の端末」**。`symbolName` を両端で使うと指す相手が逆になる。
    // 名前は `SymbolNameTests` で実在を検証する。
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
