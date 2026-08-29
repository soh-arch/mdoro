import SwiftUI
import MdoroCore

// REQ-COL-001 / 002: no colour literals; looked up by role name. The same source as the Mac side (8.5.3).
struct Theme {
    let palette: ColorPalette

    init(appearance: AppearancePreference, systemScheme: SwiftUI.ColorScheme) {
        let mode: ColorMode
        switch appearance {
        case .system: mode = ColorMode(systemScheme)
        case .light: mode = .light
        case .dark: mode = .dark
        }
        self.palette = .palette(for: mode)
    }

    // REQ-UIX-014 / 8.5.6: the focus view is fixed to a low-luminance dark palette.
    init(focusView: Bool) {
        self.palette = .dark
    }

    func color(_ role: ColorRole, _ hueRole: HueRole) -> Color { palette.color(role, hueRole) }

    var background: Color { Color(palette.bg) }
    var surface: Color { Color(palette.surface) }
    var borderSubtle: Color { Color(palette.borderSubtle) }
    var textPrimary: Color { Color(palette.textPrimary) }
    var textSecondary: Color { Color(palette.textSecondary) }
    var textTertiary: Color { Color(palette.textTertiary) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(appearance: .system, systemScheme: .light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Format {
    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // REQ-UIX-006: VoiceOver reads the remaining time out as "12 minutes 30 seconds left" and the like.
    static func spokenRemaining(_ seconds: Int) -> LocalizedStringKey {
        seconds >= 60
            ? "\(seconds / 60) minutes \(seconds % 60) seconds left"
            : "\(seconds) seconds left"
    }

    static func sessionLabel(_ type: SessionType) -> LocalizedStringKey {
        switch type {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    static func presetShape(_ preset: Preset) -> String {
        "\(preset.workSeconds / 60) / \(preset.shortBreakSeconds / 60) / \(preset.longBreakSeconds / 60)"
    }

    static func connectionLabel(_ status: ConnectionStatus) -> LocalizedStringKey {
        switch status {
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Not connected"
        }
    }
}
