import Foundation

// REQ-COL-002 / 8.5.4: views reference colour by role name, never a hue token (ink-solid and
// the like) directly.
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

    // REQ-COL-012: danger (Clay) must never stand for a session type.
    public var isSessionRole: Bool {
        switch self {
        case .sessionFocus, .sessionShortBreak, .sessionLongBreak: return true
        default: return false
        }
    }

    // REQ-COL-011: only -graphic and -text may be used for a session state.
    // The banner treatment (a -subtle ground inside a -line border) is reserved for warning.
    public var permittedRoles: Set<HueRole> {
        isSessionRole ? [.graphic, .text] : Set(HueRole.allCases)
    }

    public var allowsBannerTreatment: Bool { !isSessionRole }

    public func color(_ role: HueRole, in palette: ColorPalette) -> SRGBColor {
        precondition(
            permittedRoles.contains(role),
            "REQ-COL-011/012: \(role.rawValue) is not allowed for \(rawValue). Allowed: \(permittedRoles.map(\.rawValue).sorted())"
        )
        return palette.color(hue, role)
    }
}

public extension SessionType {
    var colorRole: ColorRole {
        switch self {
        case .work: return .sessionFocus
        case .shortBreak: return .sessionShortBreak
        case .longBreak: return .sessionLongBreak
        }
    }

    // REQ-COL-010 / 013: never colour alone. The stroke style tells them apart too.
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
