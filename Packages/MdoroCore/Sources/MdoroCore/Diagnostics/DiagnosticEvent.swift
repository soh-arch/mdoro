import Foundation

// REQ-ERR-010 / Decision 0018: 診断ログに載せる1件。
//
// **利用者由来の文字列をここへ入れないこと。** タスク名・見出し・本文・パス・サーバー名・
// 端末名・IP アドレスは、書き出しのときではなく**書き込みの時点で**落とす。

public enum DiagnosticLevel: String, Sendable, Equatable, CaseIterable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    // `tail -f` で桁を揃えるための固定幅。
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
    // 「session.start」「log.write」のような、grep しやすい固定語。
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

// Decision 0018: 同定はできるが、内容は復元できない形に落とす。
public enum DiagnosticRedaction {

    // タスクは `stableId` の下4桁だけで追う。名前は書かない。
    public static func taskId(_ stableId: String) -> String {
        String(stableId.suffix(4))
    }

    // ファイルはパスのダイジェストで追う。プロセスをまたいで安定させるため FNV-1a を使う
    // （Swift の `Hasher` は起動ごとに種が変わる）。
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

    // 1行1イベントを崩さないための最低限の防御。改行や空白が値に紛れても行が割れない。
    static func token(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return "_" }
            if CharacterSet.controlCharacters.contains(scalar) { return "_" }
            return Character(scalar)
        }
        return cleaned.isEmpty ? "_" : String(cleaned)
    }
}
