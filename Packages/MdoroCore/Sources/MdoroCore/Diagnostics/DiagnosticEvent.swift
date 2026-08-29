import Foundation

// REQ-ERR-010 / Decision 0018: one entry of the diagnostic log.
//
// **No string that came from the user goes in here.** Task names, headings, note bodies,
// paths, service names, device names and IP addresses are dropped **as the line is written**,
// not when the log is exported.

public enum DiagnosticLevel: String, Sendable, Equatable, CaseIterable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    // Fixed width, so the columns line up under `tail -f`.
    var padded: String { rawValue.count >= 5 ? rawValue : rawValue + String(repeating: " ", count: 5 - rawValue.count) }
}

public struct DiagnosticField: Sendable, Equatable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = DiagnosticRedaction.token(key)
        self.value = DiagnosticRedaction.token(value)
    }

    public init(_ key: String, _ value: Int) {
        self.init(key, String(value))
    }

    public init(_ key: String, _ value: Bool) {
        self.init(key, value ? "yes" : "no")
    }
}

public struct DiagnosticEvent: Sendable, Equatable {
    public let timestamp: Date
    public let level: DiagnosticLevel
    // A fixed word that greps well, such as "session.start" or "log.write".
    public let code: String
    public let fields: [DiagnosticField]

    public init(
        timestamp: Date = Date(),
        level: DiagnosticLevel = .info,
        code: String,
        fields: [DiagnosticField] = []
    ) {
        self.timestamp = timestamp
        self.level = level
        self.code = DiagnosticRedaction.token(code)
        self.fields = fields
    }
}

// Decision 0018: reduced to a form that identifies without letting the content be recovered.
public enum DiagnosticRedaction {

    // A task is followed by the last four digits of its `stableId`. The name is never written.
    public static func taskId(_ stableId: String) -> String {
        String(stableId.suffix(4))
    }

    // A file is followed by a digest of its path. FNV-1a, so the value is stable across processes
    // (Swift's `Hasher` is seeded afresh on every launch).
    public static func digest(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in Array(value.utf8) {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return "#" + String(format: "%04x", hash & 0xFFFF)
    }

    public static func optionalDigest(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "unset" }
        return digest(value)
    }

    // The minimum defence for one event per line: a newline or space inside a value cannot split it.
    static func token(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return "_" }
            if CharacterSet.controlCharacters.contains(scalar) { return "_" }
            return Character(scalar)
        }
        return cleaned.isEmpty ? "_" : String(cleaned)
    }
}
