import Foundation

// REQ-ERR-010 / Decision 0018: ログの見た目と、ファイルを切り替える判断。
// 読み手は issue に貼られたログを初めて見る第三者。1行1イベント・固定幅のレベル・grep しやすい語で組む。

public struct DiagnosticHeader: Sendable, Equatable {
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var architecture: String
    public var openedAt: Date
    // 挙動に影響する設定だけ。パス・ファイル名は入れない。
    public var settings: [DiagnosticField]

    public init(
        appVersion: String,
        build: String,
        osVersion: String,
        architecture: String,
        openedAt: Date = Date(),
        settings: [DiagnosticField] = []
    ) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.architecture = architecture
        self.openedAt = openedAt
        self.settings = settings
    }

    // ヘッダが無いログは再現できない。
    public static func settingsFields(preset: Preset, settings: AppSettings) -> [DiagnosticField] {
        [
            DiagnosticField("work", preset.workSeconds),
            DiagnosticField("short", preset.shortBreakSeconds),
            DiagnosticField("long", preset.longBreakSeconds),
            DiagnosticField("interval", preset.longBreakInterval),
            DiagnosticField("extend", preset.extendSeconds),
            DiagnosticField("auto", preset.autoAdvance),
            DiagnosticField("sound", preset.notificationSound.diagnosticValue),
            DiagnosticField("timeSensitive", preset.timeSensitiveNotifications),
            DiagnosticField("pre", preset.preNotifications.count),
            DiagnosticField("dayStart", settings.logicalDayStartHour),
            DiagnosticField("idleReset", settings.idleResetHours),
            DiagnosticField("appearance", settings.appearance.rawValue),
            DiagnosticField("menuBar", settings.menuBarDisplayMode.rawValue),
            DiagnosticField("taskAsLink", settings.logTaskAsLink),
            // パスは書かない。同じ設定を使い続けているかだけが分かればよい。
            DiagnosticField("vault", DiagnosticRedaction.optionalDigest(settings.taskFilePath)),
            DiagnosticField("logDir", DiagnosticRedaction.optionalDigest(settings.logFolderPath)),
        ]
    }
}

public enum DiagnosticLogFormat {

    // Decision 0018: 1ファイル 2MB・2世代。古い行を削除する処理は持たない。
    public static let maxFileBytes = 2 * 1024 * 1024

    public static let currentFileName = "mdoro.log"
    public static let previousFileName = "mdoro.1.log"

    public static func line(_ event: DiagnosticEvent) -> String {
        var parts = [timestamp(event.timestamp), event.level.padded, event.code]
        parts.append(contentsOf: event.fields.map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " ")
    }

    // 記録しないと決めたことを、**ファイル自身に書く。**
    public static func header(_ header: DiagnosticHeader) -> String {
        var lines = [
            "# Mdoro diagnostic log",
            "# no task names, note contents, file paths, host names or IP addresses are recorded",
            "# app=\(header.appVersion) (\(header.build)) os=\(header.osVersion) arch=\(header.architecture)",
        ]
        if !header.settings.isEmpty {
            lines.append("# " + header.settings.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        lines.append("# opened=\(timestamp(header.openedAt))")
        return lines.joined(separator: "\n") + "\n"
    }

    // 空のファイルは切り替えない。1行が上限を超えていても、必ずどこかへは書く。
    public static func shouldRotate(currentBytes: Int, incomingBytes: Int, maxBytes: Int = maxFileBytes) -> Bool {
        currentBytes > 0 && currentBytes + incomingBytes > maxBytes
    }

    public static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter = TimestampFormatter()
}

// `ISO8601DateFormatter` は Sendable ではないので自分で囲う。出力を予測できることを優先する。
private final class TimestampFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter

    init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        // 稼働中の時間帯変更に追随する。行にオフセットが出る。
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
