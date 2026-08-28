import Foundation
import CryptoKit

// REQ-TSK-022: 正規化は決められた順序で行う。**順序を変えると装飾だけが違う同一タスクが別物になる。**
public enum TaskTextNormalizer {

    // 行末のブロック ID (^abc123)。本文の一部ではないので表示・正規化の前に外す。
    static let blockIdPattern = try! NSRegularExpression(pattern: #"\s+\^([A-Za-z0-9-]+)\s*$"#)
    // REQ-TSK-010: タスク行の判定。リストマーカーとチェックボックス。
    static let taskLinePattern = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+]\s+\[(.)\]\s+"#)
    static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)

    private static let wikiLinkPattern = try! NSRegularExpression(pattern: #"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]"#)
    private static let markdownLinkPattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![^\s])#[^\s#]+"#)
    // **対になっている強調だけを外す。** 無条件に記号を落とすと `snake_case_name` や `2*3` が壊れ、
    // その本文がそのままログへ書かれる。
    private static let pairedEmphasisPatterns = [
        try! NSRegularExpression(pattern: #"\*\*\*([^*\n]+)\*\*\*"#),
        try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#),
        try! NSRegularExpression(pattern: #"\*([^*\n]+)\*"#),
        try! NSRegularExpression(pattern: #"___([^_\n]+)___"#),
        try! NSRegularExpression(pattern: #"__([^_\n]+)__"#),
        try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])"#),
        try! NSRegularExpression(pattern: #"~~([^~\n]+)~~"#),
        try! NSRegularExpression(pattern: #"`([^`\n]+)`"#),
    ]
    private static let whitespacePattern = try! NSRegularExpression(pattern: #"\s+"#)

    static func replacing(_ text: String, _ regex: NSRegularExpression, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    // `[[ノート|表示名]]` は表示名を、`[[ノート]]` はノート名を残す。
    // テンプレート置換では「別名があればそちら」が書けないので手で組み立てる。
    static func replacingWikiLinks(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = text
        for match in wikiLinkPattern.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: text) else { continue }
            let aliasRange = Range(match.range(at: 2), in: text)
            let targetRange = Range(match.range(at: 1), in: text)
            let replacement = aliasRange.map { String(text[$0]) } ?? targetRange.map { String(text[$0]) } ?? ""
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    // 行末のブロック ID を取り出し、本文から取り除く。
    public static func extractBlockId(from line: String) -> (body: String, blockId: String?) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = blockIdPattern.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line),
              let wholeRange = Range(match.range, in: line) else {
            return (line, nil)
        }
        var body = line
        body.removeSubrange(wholeRange)
        return (body, String(line[idRange]))
    }

    // REQ-TSK-015: 生の記法をそのまま表示しない。
    // タグも落とす。残すとログ行に入り、md 側でタグとして解釈される。
    public static func displayText(fromBody body: String) -> String {
        var text = body
        text = replacingWikiLinks(text)
        text = replacing(text, markdownLinkPattern, with: "$1")
        text = replacing(text, tagPattern, with: "")
        text = strippingPairedEmphasis(text)
        text = replacing(text, whitespacePattern, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // REQ-TSK-015: 生の記法をそのまま表示しない。対になった強調のみ中身を残して記号を外す。
    static func strippingPairedEmphasis(_ text: String) -> String {
        var result = text
        for pattern in pairedEmphasisPatterns {
            result = replacing(result, pattern, with: "$1")
        }
        return result
    }

    // REQ-TSK-022: (2) 前後の空白除去 → (3) リンクを表示テキストへ → (4) タグ・絵文字・強調記号の除去
    // → (5) 連続空白の統合 → (6) NFKC。(1) マーカーの除去は呼び出し側で済ませてある。
    public static func normalize(body: String) -> String {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        text = replacingWikiLinks(text)
        text = replacing(text, markdownLinkPattern, with: "$1")
        text = replacing(text, tagPattern, with: "")
        text = removingEmoji(text)
        text = strippingPairedEmphasis(text)
        text = replacing(text, whitespacePattern, with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.precomposedStringWithCompatibilityMapping
    }

    static func removingEmoji(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            // キーキャップ列 (1️⃣ = "1" + VS16 + U+20E3)。数字は本文に残したいので、列のときだけ落とす。
            if isKeycapBase(scalar), let end = keycapSequenceEnd(scalars, from: index) {
                index = end
                continue
            }
            if isEmojiScalar(scalar) {
                index += 1
                continue
            }
            result.append(scalar)
            index += 1
        }
        return String(result)
    }

    private static func isKeycapBase(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x23 || scalar.value == 0x2A || (0x30...0x39).contains(scalar.value)
    }

    // 土台の次に U+20E3 が (異体字セレクタを挟んで) 続くなら、その列の終端を返す。
    private static func keycapSequenceEnd(_ scalars: [Unicode.Scalar], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < scalars.count, (0xFE00...0xFE0F).contains(scalars[cursor].value) {
            cursor += 1
        }
        guard cursor < scalars.count, scalars[cursor].value == 0x20E3 else { return nil }
        return cursor + 1
    }

    static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        // 異体字セレクタ・ZWJ・結合文字。単体では見えないが残すと本文が揺れる。
        if (0xFE00...0xFE0F).contains(scalar.value) || scalar.value == 0x200D || scalar.value == 0x20E3 {
            return true
        }
        let properties = scalar.properties
        if properties.isEmojiModifier || properties.isEmojiModifierBase || properties.isEmojiPresentation {
            return true
        }
        // `isEmoji` は ASCII の数字・#・* にも真になるので、記号領域に限って拾う。
        return properties.isEmoji && scalar.value >= 0x2000
    }

    // REQ-TSK-021: 正規化本文の SHA-256 先頭16桁。
    public static func contentHash(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // REQ-TSK-032 / 035: 追従判定に使う編集距離。
    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let lhs = Array(a), rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
