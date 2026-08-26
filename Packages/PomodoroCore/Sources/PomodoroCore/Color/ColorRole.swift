import Foundation

// 8.5.4 役割マッピング。REQ-COL-002: ビューはこの役割名で色を参照し、
// 色相名トークン (ink-solid 等) を直接参照しない。色相の変更がコード変更にならないようにするため。
public enum ColorRole: String, CaseIterable, Sendable {
    case sessionFocus
    case sessionShortBreak
    case sessionLongBreak
    case accentPrimary
    case success
    case warning
    case danger

    public var hue: ColorHue {
        switch self {
        case .sessionFocus, .accentPrimary: return .ink
        case .sessionShortBreak, .success: return .sage
        case .sessionLongBreak, .warning: return .ochre
        case .danger: return .clay
        }
    }

    // REQ-COL-012: danger (Clay) をセッション種別の表示に使ってはならない。
    public var isSessionRole: Bool {
        switch self {
        case .sessionFocus, .sessionShortBreak, .sessionLongBreak: return true
        default: return false
        }
    }

    // REQ-COL-011: sessionLongBreak と warning は同じ Ochre を共有するため treatment で区別する。
    // セッション状態に使ってよいのは -graphic と -text だけ。
    // -subtle の地に -line の枠を組んだバナー表現は warning に予約する。
    public var permittedRoles: Set<HueRole> {
        isSessionRole ? [.graphic, .text] : Set(HueRole.allCases)
    }

    public var allowsBannerTreatment: Bool { !isSessionRole }

    public func color(_ role: HueRole, in palette: ColorPalette) -> SRGBColor {
        precondition(
            permittedRoles.contains(role),
            "REQ-COL-011/012: \(rawValue) に \(role.rawValue) は使えない。許可されるのは \(permittedRoles.map(\.rawValue).sorted())"
        )
        return palette.color(hue, role)
    }
}

public extension SessionType {
    // 進行リング・種別ラベルの色役割。
    var colorRole: ColorRole {
        switch self {
        case .work: return .sessionFocus
        case .shortBreak: return .sessionShortBreak
        case .longBreak: return .sessionLongBreak
        }
    }

    // REQ-COL-013: 色に加えて進行リングの線種でも区別する。色だけに頼らせない (REQ-COL-010)。
    var progressRingStyle: ProgressRingStyle {
        switch self {
        case .work: return .solid
        case .shortBreak: return .thin
        case .longBreak: return .double
        }
    }
}

public enum ProgressRingStyle: String, Sendable, Hashable, CaseIterable {
    case solid
    case thin
    case double
}
