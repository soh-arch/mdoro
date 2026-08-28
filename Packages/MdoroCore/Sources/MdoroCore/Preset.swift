import Foundation

// REQ-CFG: 9.2 プリセットに含まれる項目 / 10.3 Preset
// REQ-NTF-006 / Decision 0017: 通知音は macOS のシステムサウンドを流用し、無音も選べる。
public enum NotificationSound: String, Equatable, Sendable, Codable, CaseIterable {
    case `default`
    case chime
    case bell
    case wood
    case silent

    // `/System/Library/Sounds` にあるファイル名。`default` は OS の既定音、`silent` は鳴らさない。
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

    // REQ-PRS-010: 初回起動時に作成する既定プリセット「標準」
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

    // REQ-CFG-018: 範囲外の値は適用しない。
    public func isWithinValidRanges() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmedName.count) else { return false }
        guard (60...(180 * 60)).contains(workSeconds) else { return false }
        guard (60...(60 * 60)).contains(shortBreakSeconds) else { return false }
        guard (60...(60 * 60)).contains(longBreakSeconds) else { return false }
        guard (2...12).contains(longBreakInterval) else { return false }
        guard (60...(30 * 60)).contains(extendSeconds) else { return false }
        // REQ-NTF-020: トリガは 0〜2 個。値域は PreNotification が見る。
        guard preNotifications.count <= 2 else { return false }
        guard preNotifications.allSatisfy({ $0.isWithinValidRanges }) else { return false }
        return true
    }
}
