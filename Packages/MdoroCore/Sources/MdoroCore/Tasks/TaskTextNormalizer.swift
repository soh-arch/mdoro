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

    // REQ-TSK-022 (4): emoji come off the text. REQ-TSK-021 hashes what is left into the stableId.
    // **Neither clause says what the unit of removal is, and it cannot be the scalar.** One emoji
    // is often several scalars and not all of them are emoji themselves: the tag letters that
    // spell out a subdivision flag are not, and neither is a combining mark typed after one.
    // Taken away scalar by scalar, those stay behind with nothing to stand on and attach to
    // whatever now precedes them -- step (6) folds an orphaned accent onto the letter before, and
    // an orphan nobody can see is still enough to give two identical names two different hashes.
    //
    // **What the clause says to remove is the emoji, not what was standing next to one.** So the
    // cluster is walked, not the string: the emoji scalars go, and when the scalar the cluster
    // stands on is one of them, whatever is left that cannot stand on its own goes with it.
    // Anything that can stand on its own is a character in its own right and stays.
    static func removingEmoji(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for cluster in text {
            let scalars = Array(cluster.unicodeScalars)
            // A keycap sequence (1️⃣ = "1" + VS16 + U+20E3) is one cluster standing on an
            // ordinary digit. Digits belong in the text, so what is dropped is the sequence itself,
            // never a bare digit -- and the cluster is then treated like any other an emoji stands
            // on, so that anything else caught in it is judged the same way.
            //
            // A Prepend character (UAX #29 GB9b) joins whatever follows it into its cluster, so a
            // cluster can open on one and only then reach its base. The base is the first scalar
            // after any Prepend characters. The Prepend characters themselves were typed before
            // the base and are not part of it; they are kept as the text they are.
            let baseIndex = scalars.firstIndex { !isPrepend($0) } ?? scalars.count
            for scalar in scalars[..<baseIndex] { result.append(scalar) }
            let body = Array(scalars[baseIndex...])
            guard let base = body.first else { continue }
            let keycap = isKeycapCluster(body)
            let standsOnAnEmoji = keycap || isEmojiScalar(base)
            for (index, scalar) in body.enumerated() {
                // The digit a keycap is built on. The rest of the sequence, the variation selector
                // and U+20E3, `isEmojiScalar` takes below.
                if keycap, index == 0 { continue }
                if isEmojiScalar(scalar) { continue }
                if standsOnAnEmoji, !standsOnItsOwn(scalar) { continue }
                result.append(scalar)
            }
        }
        return String(result)
    }

    // Whether a scalar is a character in its own right, or something that only exists attached to
    // the one before it. The second kind is whatever Unicode marks Grapheme_Extend -- every
    // combining mark, the tag letters that spell out a flag, and oddities like the halfwidth
    // katakana voiced mark, which its category calls a letter and which still cannot stand alone --
    // and, on top of that, a spacing mark, an invisible format character, a control, a lone
    // surrogate, an unassigned code point. None of them can be left behind when what they were
    // sitting on is taken away; they would fasten themselves to the text in front instead.
    private static func standsOnItsOwn(_ scalar: Unicode.Scalar) -> Bool {
        // U+200C, the non-joiner, is Grapheme_Extend, so the test below would sweep it away with
        // the emoji it happened to sit behind. It is named here for the reason `isEmojiScalar`
        // leaves it alone: it changes what a word says in Persian and other scripts, so it is text
        // wherever it lands, and the two tests must not say opposite things about it.
        if scalar.value == 0x200C { return true }
        let properties = scalar.properties
        if properties.isGraphemeExtend { return false }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .format, .control, .surrogate, .unassigned:
            return false
        default:
            return true
        }
    }

    // Whether a scalar is Grapheme_Cluster_Break=Prepend. Swift exposes no such property, so the
    // segmentation that built the cluster is asked directly: only GB9b joins a scalar to a
    // following plain letter. Asking it keeps this in step with the Unicode version the clusters
    // were cut with, where a list would freeze one.
    private static func isPrepend(_ scalar: Unicode.Scalar) -> Bool {
        var probe = String.UnicodeScalarView()
        probe.append(scalar)
        probe.append("a")
        return String(probe).count == 1
    }

    // A base of "#", "*" or a digit, then U+20E3, possibly across a variation selector.
    private static func isKeycapCluster(_ scalars: [Unicode.Scalar]) -> Bool {
        guard let base = scalars.first,
              base.value == 0x23 || base.value == 0x2A || (0x30...0x39).contains(base.value) else {
            return false
        }
        var cursor = 1
        while cursor < scalars.count, (0xFE00...0xFE0F).contains(scalars[cursor].value) {
            cursor += 1
        }
        return cursor < scalars.count && scalars[cursor].value == 0x20E3
    }

    static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        // Variation selectors, ZWJ, the combining mark. Invisible on their own, but left in they make the text waver.
        // U+200C, the non-joiner, is deliberately not among them: it changes what a word says in
        // Persian and other scripts, so it is text and stays.
        if (0xFE00...0xFE0F).contains(scalar.value) || scalar.value == 0x200D || scalar.value == 0x20E3 {
            return true
        }
        let properties = scalar.properties
        if properties.isEmojiModifier || properties.isEmojiModifierBase || properties.isEmojiPresentation {
            return true
        }
        // `isEmoji` is true below U+2000 as well -- for the ASCII digits, for # and *, and for
        // © and ®. The threshold leaves every one of them to the text. It is a threshold and not a
        // list of them because `isEmoji` moves with the Unicode version, and a list would freeze
        // this one. (A © that a ZWJ has joined onto an emoji stays as well: `removingEmoji` takes
        // the emoji scalars and whatever cannot stand without them, and a © stands on its own.)
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
