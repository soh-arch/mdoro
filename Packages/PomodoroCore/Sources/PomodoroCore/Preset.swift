import Foundation

// REQ-CFG: 9.2 プリセットに含まれる項目 / 10.3 Preset
public enum NotificationSound: String, Equatable, Sendable, Codable {
    case `default`
    case chime
    case bell
    case wood
    case silent
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
    public var preNotifySeconds: Int
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
        preNotifySeconds: Int = 0,
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
        self.preNotifySeconds = preNotifySeconds
        self.isBuiltInDefault = isBuiltInDefault
    }

    // REQ-PRS-010: 初回起動時に作成する既定プリセット「標準」
    public static func standard(id: String = UUID().uuidString) -> Preset {
        Preset(
            id: id,
            name: "標準",
            workSeconds: 25 * 60,
            shortBreakSeconds: 5 * 60,
            longBreakSeconds: 15 * 60,
            longBreakInterval: 4,
            extendSeconds: 5 * 60,
            autoAdvance: false,
            preNotifySeconds: 0,
            isBuiltInDefault: true
        )
    }

    // REQ-CFG-018: プロトコル経由で範囲外の値を受信した場合は適用しないため、まず検証できるようにする。
    public func isWithinValidRanges() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmedName.count) else { return false }
        guard (60...(180 * 60)).contains(workSeconds) else { return false }
        guard (60...(60 * 60)).contains(shortBreakSeconds) else { return false }
        guard (60...(60 * 60)).contains(longBreakSeconds) else { return false }
        guard (2...12).contains(longBreakInterval) else { return false }
        guard (60...(30 * 60)).contains(extendSeconds) else { return false }
        guard (0...(5 * 60)).contains(preNotifySeconds) else { return false }
        return true
    }
}
