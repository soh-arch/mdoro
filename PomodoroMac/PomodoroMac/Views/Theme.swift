import SwiftUI
import MdoroCore

// REQ-COL-001 / 002: views write no colour literal and look colour up by role name. The values come
// from ColorPalette (8.5.3).
struct Theme {
    let palette: ColorPalette

    // REQ-COL-003: three choices — follow the system, fixed light, fixed dark.
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

// The formats used for display.
enum Format {
    // REQ-UIX-006: VoiceOver reads it out as "12 minutes 30 seconds left" and the like.
    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func spokenRemaining(_ seconds: Int) -> String {
        seconds >= 60
            ? String(localized: "\(seconds / 60) minutes \(seconds % 60) seconds left")
            : String(localized: "\(seconds) seconds left")
    }

    static func sessionLabel(_ type: SessionType) -> String {
        NotificationScheduler.label(for: type)
    }

    // For reading out. The run state the mark shows by its shape is said in words too.
    static func runStateLabel(_ state: RunState) -> String {
        switch state {
        case .idle: return String(localized: "Not running")
        case .running: return String(localized: "Running")
        case .paused: return String(localized: "Paused")
        case .finished: return String(localized: "Ended")
        case .pendingDecision: return String(localized: "Needs a decision")
        }
    }

    // REQ-UIX-004: the words for the connection state. **The cases and their roles are
    // `ConnectionStatus`; the words are here.**
    // The `Format` on the iPhone side holds the same three words of its own.
    static func connectionLabel(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected: return String(localized: "Connected")
        case .reconnecting: return String(localized: "Reconnecting")
        case .disconnected: return String(localized: "Not connected")
        }
    }

    // REQ-CFG-018 / 9.3: the words for the settings a launch can put back to their defaults.
    // **The cases and their ranges are `AppSettings.RangedField`; the words are here**, the same
    // split `connectionLabel` above keeps (Decision 0022: MdoroCore has no catalogue to reach).
    //
    // Each is worded as the settings window words it, because that is where the reader is being
    // sent to look: "File name" under the log, "Name" under the connection, and the four shortcuts
    // by the action they carry out.
    static func settingLabel(_ field: AppSettings.RangedField) -> String {
        switch field {
        case .logicalDayStartHour: return String(localized: "Day start hour")
        case .idleResetHours: return String(localized: "Idle reset hours")
        case .logFileName: return String(localized: "Log file name")
        case .displayName: return String(localized: "The name your iPhone sees")
        case .pauseResumeHotKey: return String(localized: "Pause / Resume shortcut")
        case .showWindowHotKey: return String(localized: "Bring the window to the front shortcut")
        case .startNextHotKey: return String(localized: "Start the next session shortcut")
        case .skipHotKey: return String(localized: "Skip shortcut")
        }
    }

    // The ones a band lists, in one line. The separator is not localised: the app has one language
    // (Decision 0022), and a `Text` given a `String` is verbatim, so no key is asked for either.
    static func settingLabels(_ fields: [AppSettings.RangedField]) -> String {
        fields.map { settingLabel($0) }.joined(separator: ", ")
    }

    // REQ-UIX-008: the shape of a preset's times is written alongside.
    static func presetShape(_ preset: Preset) -> String {
        "\(preset.workSeconds / 60) / \(preset.shortBreakSeconds / 60) / \(preset.longBreakSeconds / 60)"
    }
}
