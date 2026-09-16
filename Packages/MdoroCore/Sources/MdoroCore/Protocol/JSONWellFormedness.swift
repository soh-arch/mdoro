import Foundation

// REQ-ERR-009 / REQ-CFG-018: **the one question that separates a value the sender is owed an
// answer for from a message there is nothing to answer about.**
//
// A settings field can fail to read for two reasons that look identical from inside the decoder
// (`CommandParams.value`): the number is well formed but no type here can hold it
// (`"logicalDayStartHour":4.5`, `1e309`, a figure past `Int`), or the bytes are not a JSON number
// at all (`01`, `1e`, `--3`). The first is a value, and REQ-CFG-018 owes it `settingOutOfRange`;
// the second is a broken message, and REQ-ERR-009 has it discarded and counted.
//
// **Foundation cannot be asked to tell them apart.** Its scanner accepts a number-shaped run of
// bytes without reading it and only judges the digits when a type asks for a value, so every
// numeric type refuses both alike; `JSONSerialization` refuses both as well (it calls `1e309`
// malformed, while reading `-1e400` as `-inf`). Measured 2026-09-03 — the table is in
// `docs/platform/0012`. So the grammar is read here instead, off the bytes as they arrived.
//
// **Size is not part of the question.** RFC 8259 §6 puts no bound on a number's magnitude or its
// digit count; how large a value a `Double` or an `Int` can hold is a fact about this end, and
// keeping the two apart is the whole reason this exists.
enum JSONWellFormedness {
    // Whether `data` is one complete JSON text, per RFC 8259.
    //
    // Strings are held to what Foundation will actually accept rather than to the grammar alone:
    // an unpaired `\uD800` and a byte that is not UTF-8 both parse as syntax and neither denotes a
    // string, so both are refused here rather than handed on as well-formed.
    static func holds(for data: Data) -> Bool {
        guard String(data: data, encoding: .utf8) != nil else { return false }
        var reader = Reader(Array(data))
        return reader.scanWholeText()
    }
}

private struct Reader {
    private let bytes: [UInt8]
    private var index = 0

    // The walk is recursive and the bytes came off the network, so nesting is bounded rather than
    // followed. Foundation stops sooner than this on its own (measured: a document 1,000 deep is
    // refused before any field of it is read), so reaching the limit means the decoder has already
    // let the text through, and refusing it here only sends it back to REQ-ERR-009.
    private static let depthLimit = 256

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func scanWholeText() -> Bool {
        skipWhitespace()
        guard scanValue(depth: 0) else { return false }
        skipWhitespace()
        return index == bytes.count
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }

    private mutating func take(word: String) -> Bool {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected
        else { return false }
        index += expected.count
        return true
    }

    private mutating func scanValue(depth: Int) -> Bool {
        guard depth <= Self.depthLimit, let byte = current else { return false }
        switch byte {
        case UInt8(ascii: "{"): return scanObject(depth: depth)
        case UInt8(ascii: "["): return scanArray(depth: depth)
        case UInt8(ascii: "\""): return scanString()
        case UInt8(ascii: "t"): return take(word: "true")
        case UInt8(ascii: "f"): return take(word: "false")
        case UInt8(ascii: "n"): return take(word: "null")
        default: return scanNumber()
        }
    }

    private mutating func scanObject(depth: Int) -> Bool {
        guard take(UInt8(ascii: "{")) else { return false }
        skipWhitespace()
        if take(UInt8(ascii: "}")) { return true }
        while true {
            skipWhitespace()
            guard scanString() else { return false }
            skipWhitespace()
            guard take(UInt8(ascii: ":")) else { return false }
            skipWhitespace()
            guard scanValue(depth: depth + 1) else { return false }
            skipWhitespace()
            if take(UInt8(ascii: ",")) { continue }
            return take(UInt8(ascii: "}"))
        }
    }

    private mutating func scanArray(depth: Int) -> Bool {
        guard take(UInt8(ascii: "[")) else { return false }
        skipWhitespace()
        if take(UInt8(ascii: "]")) { return true }
        while true {
            skipWhitespace()
            guard scanValue(depth: depth + 1) else { return false }
            skipWhitespace()
            if take(UInt8(ascii: ",")) { continue }
            return take(UInt8(ascii: "]"))
        }
    }

    private mutating func scanString() -> Bool {
        guard take(UInt8(ascii: "\"")) else { return false }
        // A `\uD800` owes a low surrogate to the escape right after it, and nothing else will do.
        var owedALowSurrogate = false
        while let byte = current {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return !owedALowSurrogate
            case UInt8(ascii: "\\"):
                guard let escaped = current else { return false }
                index += 1
                if escaped == UInt8(ascii: "u") {
                    guard let scalar = scanFourHexDigits() else { return false }
                    if owedALowSurrogate {
                        guard (0xDC00...0xDFFF).contains(scalar) else { return false }
                        owedALowSurrogate = false
                    } else if (0xD800...0xDBFF).contains(scalar) {
                        owedALowSurrogate = true
                    } else if (0xDC00...0xDFFF).contains(scalar) {
                        return false
                    }
                    continue
                }
                guard !owedALowSurrogate, #"\"/bfnrt"#.utf8.contains(escaped) else { return false }
            default:
                // A raw control character has to be written as an escape.
                guard !owedALowSurrogate, byte >= 0x20 else { return false }
            }
        }
        return false
    }

    private mutating func scanFourHexDigits() -> UInt32? {
        var scalar: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current, let digit = Self.hexDigit(byte) else { return nil }
            scalar = scalar << 4 | UInt32(digit)
            index += 1
        }
        return scalar
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    // RFC 8259 §6: `[ "-" ] ( "0" / [1-9][0-9]* ) [ "." 1*DIGIT ] [ ("e"/"E") ["+"/"-"] 1*DIGIT ]`.
    private mutating func scanNumber() -> Bool {
        _ = take(UInt8(ascii: "-"))
        if take(UInt8(ascii: "0")) {
            // A leading zero admits no more digits, which is what makes `01` two numbers, not one.
            if let byte = current, Self.isDigit(byte) { return false }
        } else {
            guard let byte = current, Self.isDigit(byte) else { return false }
            skipDigits()
        }
        if take(UInt8(ascii: ".")) {
            guard let byte = current, Self.isDigit(byte) else { return false }
            skipDigits()
        }
        if let byte = current, byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
            index += 1
            if let sign = current, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                index += 1
            }
            guard let byte = current, Self.isDigit(byte) else { return false }
            skipDigits()
        }
        return true
    }

    private mutating func skipDigits() {
        while let byte = current, Self.isDigit(byte) { index += 1 }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
