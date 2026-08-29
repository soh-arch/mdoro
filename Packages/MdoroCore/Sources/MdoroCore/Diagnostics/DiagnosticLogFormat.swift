import Foundation

// REQ-ERR-010 / Decision 0018: how a log line looks, and when the file is rotated.
// The reader is a stranger seeing a log pasted into an issue for the first time, so: one event
// per line, a fixed-width level, and words that grep well.

public struct DiagnosticHeader: Sendable, Equatable {
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var architecture: String
    public var openedAt: Date
    // Only settings that change behaviour. No paths, no file names.
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

    // A log without a header cannot be reproduced.
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
            // No path is written. All a reader needs is whether the same setting is still in use.
            DiagnosticField("vault", DiagnosticRedaction.optionalDigest(settings.taskFilePath)),
            DiagnosticField("logDir", DiagnosticRedaction.optionalDigest(settings.logFolderPath)),
        ]
    }
}

public enum DiagnosticLogFormat {

    // Decision 0018: 2MB per file, two generations. Nothing deletes old lines.
    public static let maxFileBytes = 2 * 1024 * 1024

    public static let currentFileName = "mdoro.log"
    public static let previousFileName = "mdoro.1.log"

    public static func line(_ event: DiagnosticEvent) -> String {
        var parts = [timestamp(event.timestamp), event.level.padded, event.code]
        parts.append(contentsOf: event.fields.map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " ")
    }

    // What was decided not to record is stated **in the file itself.**
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

    // An empty file is never rotated. Even a line that exceeds the limit on its own is written somewhere.
    public static func shouldRotate(currentBytes: Int, incomingBytes: Int, maxBytes: Int = maxFileBytes) -> Bool {
        currentBytes > 0 && currentBytes + incomingBytes > maxBytes
    }

    public static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter = TimestampFormatter()
}

// `ISO8601DateFormatter` is not Sendable, so it is wrapped here. A predictable output comes first.
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
        // Follows a time zone change while running. The offset shows in the line.
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
