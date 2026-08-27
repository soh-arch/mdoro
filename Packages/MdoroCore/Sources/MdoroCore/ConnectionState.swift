import Foundation

// REQ-UIX-004: 接続状態を両端末で常時視認できること。表示に必要な区分のみを共有する。
// 実際の接続管理は第3章・第12章（工程5）が担う。
public enum ConnectionStatus: String, Equatable, Sendable, Codable, CaseIterable {
    case connected
    case reconnecting
    case disconnected

    public var label: String {
        switch self {
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Not connected"
        }
    }

    // REQ-UIX-035 / REQ-COL-022: メニューバーでは色を使えないため、**形状**で区別する。
    //
    // 名前は必ず `ConnectionStatusTests` で存在を検証すること。
    // **存在しない SF Symbol 名を渡すと、何も描かれないまま静かに失敗する。**
    // 実際に `timer.slash`（存在しない）を指定してメニューバー項目が丸ごと消えた。
    public var menuBarSymbolName: String {
        switch self {
        case .connected: return "timer"
        case .reconnecting: return "clock.badge.questionmark"
        case .disconnected: return "clock.badge.xmark"
        }
    }

    // 繋がっているときだけ、メニューバーにアプリの印（`MenuBarIcon`）を出す。
    // 問題があるときは OS の警告記号に譲る。**不調は製品の顔ではなく、システムの語彙で伝える。**
    // 形の差は保たれるので REQ-UIX-035 を満たす。
    public var menuBarUsesAppMark: Bool { self == .connected }

    // REQ-COL-010: 色のみで区別しない。通常画面では色に加えて形の違うアイコンを添える。
    public var symbolName: String {
        switch self {
        case .connected: return "iphone.gen3"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "iphone.gen3.slash"
        }
    }

    // REQ-UIX-004: **表示する側から見た「相手の端末」**を表す記号。
    // `symbolName` を両端から使うと、指す相手が逆になる
    // （iPhone の画面に iPhone のアイコンが出て「Mac につながっている」を意味していた。
    // 2026-08-28、実機で確認）。
    //
    // 名前は必ず `SymbolNameTests` で存在を検証すること。
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
