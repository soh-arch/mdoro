import Foundation

// REQ-CFG: 9.2 what a preset holds / 10.3 Preset
// REQ-NTF-006 / Decision 0017: the notification sounds are macOS system sounds, and silence is a choice.
public enum NotificationSound: String, Equatable, Sendable, Codable, CaseIterable {
    case `default`
    case chime
    case bell
    case wood
    case silent

    // A file name under `/System/Library/Sounds`. `default` is the OS default sound; `silent` plays nothing.
    public var systemSoundFileName: String? {
        switch self {
        case .default: return nil
        case .chime: return "Glass.aiff"
        case .bell: return "Submarine.aiff"
        case .wood: return "Pop.aiff"
        case .silent: return nil
        }
    }

    public var isSilent: Bool { self == .silent }

    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .chime: return "Glass"
        case .bell: return "Submarine"
        case .wood: return "Pop"
        case .silent: return "Silent"
        }
    }

    // REQ-ERR-010 / Decision 0018: the log is read by a stranger on an issue, who has no table
    // mapping the raw value (kept for compatibility by 10.3) to the name shown in settings.
    public var diagnosticValue: String { "\(rawValue)(\(displayName))" }
}

public struct Preset: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var symbol: String?
    public var workSeconds: Int
    public var shortBreakSeconds: Int
    public var longBreakSeconds: Int
    public var longBreakInterval: Int
    public var extendSeconds: Int
    public var autoAdvance: Bool
    public var notificationSound: NotificationSound
    public var timeSensitiveNotifications: Bool
    public var preNotifications: [PreNotification]
    public var isBuiltInDefault: Bool

    public init(
        id: String,
        name: String,
        symbol: String? = nil,
        workSeconds: Int,
        shortBreakSeconds: Int,
        longBreakSeconds: Int,
        longBreakInterval: Int,
        extendSeconds: Int,
        autoAdvance: Bool = false,
        notificationSound: NotificationSound = .default,
        timeSensitiveNotifications: Bool = false,
        preNotifications: [PreNotification] = [],
        isBuiltInDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.workSeconds = workSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakSeconds = longBreakSeconds
        self.longBreakInterval = longBreakInterval
        self.extendSeconds = extendSeconds
        self.autoAdvance = autoAdvance
        self.notificationSound = notificationSound
        self.timeSensitiveNotifications = timeSensitiveNotifications
        self.preNotifications = preNotifications
        self.isBuiltInDefault = isBuiltInDefault
    }

    // REQ-PRS-010: the default preset, "Standard", created on first launch.
    public static func standard(id: String = UUID().uuidString) -> Preset {
        Preset(
            id: id,
            name: "Standard",
            workSeconds: 25 * 60,
            shortBreakSeconds: 5 * 60,
            longBreakSeconds: 15 * 60,
            longBreakInterval: 4,
            extendSeconds: 5 * 60,
            autoAdvance: false,
            preNotifications: [],
            isBuiltInDefault: true
        )
    }

    // REQ-CFG-018: an out-of-range value is not applied.
    public func isWithinValidRanges() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmedName.count) else { return false }
        guard (60...(180 * 60)).contains(workSeconds) else { return false }
        guard (60...(60 * 60)).contains(shortBreakSeconds) else { return false }
        guard (60...(60 * 60)).contains(longBreakSeconds) else { return false }
        guard (2...12).contains(longBreakInterval) else { return false }
        guard (60...(30 * 60)).contains(extendSeconds) else { return false }
        // REQ-NTF-020: zero to two triggers. PreNotification checks their ranges.
        guard preNotifications.count <= 2 else { return false }
        guard preNotifications.allSatisfy({ $0.isWithinValidRanges }) else { return false }
        return true
    }
}
