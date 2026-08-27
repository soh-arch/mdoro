import Foundation

// REQ-CFG: 9.2 プリセットに含まれる項目 / 10.3 Preset
// REQ-NTF-006: 通知音を数種類から選べ、無音（触覚のみ）も選べること。
//
// Decision 0017: 音源は macOS のシステムサウンドを流用する。
// 独自音源を作るほどの必然性がなく、ユーザーが既に聞き慣れた音のほうが用途に合う。
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
        // Tink は 0.56 秒の極めて小さなチック音で、通知音として実質聞こえない（実機で確認）。
        case .wood: return "Pop.aiff"
        case .silent: return nil
        }
    }

    public var isSilent: Bool { self == .silent }

    public var displayName: String {
        switch self {
        case .default: return "既定"
        case .chime: return "チャイム"
        case .bell: return "ベル"
        case .wood: return "ウッド"
        case .silent: return "無音"
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
            name: "標準",
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

    // REQ-CFG-018: プロトコル経由で範囲外の値を受信した場合は適用しないため、まず検証できるようにする。
    public func isWithinValidRanges() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmedName.count) else { return false }
        guard (60...(180 * 60)).contains(workSeconds) else { return false }
        guard (60...(60 * 60)).contains(shortBreakSeconds) else { return false }
        guard (60...(60 * 60)).contains(longBreakSeconds) else { return false }
        guard (2...12).contains(longBreakInterval) else { return false }
        guard (60...(30 * 60)).contains(extendSeconds) else { return false }
        // REQ-NTF-020: トリガは 0〜2 個。各トリガの値域は PreNotification 側で検証する。
        guard preNotifications.count <= 2 else { return false }
        guard preNotifications.allSatisfy({ $0.isWithinValidRanges }) else { return false }
        return true
    }
}
