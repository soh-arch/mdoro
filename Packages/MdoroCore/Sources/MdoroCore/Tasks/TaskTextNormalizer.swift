import Foundation
import CryptoKit

// REQ-TSK-022: normalisation runs in a fixed order. **Change the order and one task, differing
// only in its decoration, becomes two.**
public enum TaskTextNormalizer {

    // The block id at the end of a line (^abc123). Not part of the text, so it comes off before
    // display and before normalisation.
    static let blockIdPattern = try! NSRegularExpression(pattern: #"\s+\^([A-Za-z0-9-]+)\s*$"#)
    // REQ-TSK-010: what makes a line a task — a list marker and a checkbox.
    static let taskLinePattern = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+]\s+\[(.)\]\s+"#)
    static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)

    private static let wikiLinkPattern = try! NSRegularExpression(pattern: #"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]"#)
    private static let markdownLinkPattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![^\s])#[^\s#]+"#)
    // **Only paired emphasis comes off.** Dropping the marks unconditionally would break
    // `snake_case_name` and `2*3`, and that text goes into the log exactly as it stands.
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

    // `[[note|alias]]` keeps the alias, `[[note]]` keeps the note name.
    // Template replacement cannot say "the alias if there is one", so this is assembled by hand.
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

    // Take the block id off the end of the line and out of the text.
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

    // REQ-TSK-015: raw notation is never shown as it stands.
    // Tags come off too: left in, they reach the log line and are read back as tags by the Markdown tool.
    public static func displayText(fromBody body: String) -> String {
        var text = body
        text = replacingWikiLinks(text)
        text = replacing(text, markdownLinkPattern, with: "$1")
        text = replacing(text, tagPattern, with: "")
        text = strippingPairedEmphasis(text)
        text = replacing(text, whitespacePattern, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // REQ-TSK-015: raw notation is never shown as it stands. Only paired emphasis loses its marks,
    // and keeps what was between them.
    static func strippingPairedEmphasis(_ text: String) -> String {
        var result = text
        for pattern in pairedEmphasisPatterns {
            result = replacing(result, pattern, with: "$1")
        }
        return result
    }

    // REQ-TSK-022: (2) trim → (3) links become their display text → (4) tags, emoji and emphasis
    // marks come off → (5) runs of whitespace collapse → (6) NFKC. (1), removing the marker, the
    // caller has already done.
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
            // A keycap sequence (1️⃣ = "1" + VS16 + U+20E3). Digits belong in the text, so only the
            // sequence is dropped.
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

    // If U+20E3 follows the base (possibly across a variation selector), return where that sequence ends.
    private static func keycapSequenceEnd(_ scalars: [Unicode.Scalar], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < scalars.count, (0xFE00...0xFE0F).contains(scalars[cursor].value) {
            cursor += 1
        }
        guard cursor < scalars.count, scalars[cursor].value == 0x20E3 else { return nil }
        return cursor + 1
    }

    static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        // Variation selectors, ZWJ, the combining mark. Invisible on their own, but left in they make the text waver.
        if (0xFE00...0xFE0F).contains(scalar.value) || scalar.value == 0x200D || scalar.value == 0x20E3 {
            return true
        }
        let properties = scalar.properties
        if properties.isEmojiModifier || properties.isEmojiModifierBase || properties.isEmojiPresentation {
            return true
        }
        // `isEmoji` is true for ASCII digits, # and * as well, so only the symbol range is taken.
        return properties.isEmoji && scalar.value >= 0x2000
    }

    // REQ-TSK-021: the first 16 digits of the SHA-256 of the normalised text.
    public static func contentHash(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // REQ-TSK-032 / 035: the edit distance used to decide whether to follow an edit.
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
