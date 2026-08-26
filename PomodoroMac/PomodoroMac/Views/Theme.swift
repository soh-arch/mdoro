import SwiftUI
import PomodoroCore

// REQ-COL-001 / 002: ビューは色リテラルを書かず、役割名で色を引く。
// 実際の値は PomodoroCore の ColorPalette（仕様書 8.5.3）が唯一の出典。
struct Theme {
    let palette: ColorPalette

    // REQ-COL-003: システム追従・ライト固定・ダーク固定の3択。
    init(appearance: AppearancePreference, systemScheme: SwiftUI.ColorScheme) {
        let mode: ColorMode
        switch appearance {
        case .system: mode = ColorMode(systemScheme)
        case .light: mode = .light
        case .dark: mode = .dark
        }
        self.palette = .palette(for: mode)
    }

    func color(_ role: ColorRole, _ hueRole: HueRole) -> Color {
        palette.color(role, hueRole)
    }

    var background: Color { Color(palette.bg) }
    var surface: Color { Color(palette.surface) }
    var surfaceRaised: Color { Color(palette.surfaceRaised) }
    var borderSubtle: Color { Color(palette.borderSubtle) }
    var border: Color { Color(palette.border) }
    var textPrimary: Color { Color(palette.textPrimary) }
    var textSecondary: Color { Color(palette.textSecondary) }
    var textTertiary: Color { Color(palette.textTertiary) }
    var focusRing: Color { Color(palette.focusRing) }
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

// 表示用の書式。
enum Format {
    // REQ-UIX-006: VoiceOver では「残り12分30秒」のように読み上げる。
    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func spokenRemaining(_ seconds: Int) -> String {
        seconds >= 60 ? "残り\(seconds / 60)分\(seconds % 60)秒" : "残り\(seconds)秒"
    }

    static func sessionLabel(_ type: SessionType) -> String {
        NotificationScheduler.label(for: type)
    }

    // REQ-UIX-008: プリセットの時間構成を併記する。
    static func presetShape(_ preset: Preset) -> String {
        "\(preset.workSeconds / 60) / \(preset.shortBreakSeconds / 60) / \(preset.longBreakSeconds / 60)"
    }
}
