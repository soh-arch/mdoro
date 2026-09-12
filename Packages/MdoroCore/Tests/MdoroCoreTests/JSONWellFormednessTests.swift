import Testing
import Foundation
@testable import MdoroCore

// REQ-ERR-009 / REQ-CFG-018: **the grammar that decides which of the two a failed read was.**
//
// `CommandParams.value` reaches the same throw for a settings number no type here can hold and for
// bytes that are not a number at all, and the first is owed `settingOutOfRange` while the second is
// discarded and counted. Foundation refuses both alike — its scanner accepts a number-shaped run of
// bytes without reading it, and `JSONSerialization` calls `1e309` malformed while reading `-1e400`
// as `-inf` (measured 2026-09-03, `docs/platform/0012`) — so the line is drawn here instead.
//
// **What this must not do is treat size as a syntax question.** RFC 8259 §6 bounds neither a
// number's magnitude nor its digit count; what a `Double` or an `Int` holds is a fact about this
// end, and the whole reason this exists is to keep the two apart.
@Suite("Is a message well-formed JSON (REQ-ERR-009 / REQ-CFG-018)")
struct JSONWellFormednessTests {
    private func holds(_ text: String) -> Bool { JSONWellFormedness.holds(for: Data(text.utf8)) }

    // The numbers that carried this whole change: well formed, and larger than anything here holds.
    @Test func aNumberIsWellFormedNoMatterHowLargeItIs() {
        for number in ["1e308", "1e309", "1e400", "-1e400", "1e-400", "1e309000000000000000000",
                       "99999999999999999999999", "4.5", "-0", "0", "1E+7", "1e-7", "-1.5e-3"] {
            #expect(holds("{\"v\":\(number)}"), "\(number)")
        }
    }

    @Test func aNumberOutsideTheGrammarIsNotWellFormed() {
        for number in ["01", "-01", "1e", "1e+", "--3", "1.2.3", ".5", "1.", "+1", "0x10", "Infinity",
                       "NaN", "1_000", "1 2", ""] {
            #expect(!holds("{\"v\":\(number)}"), "\(number)")
        }
    }

    @Test func theShapesAMessageIsMadeOfAreWellFormed() {
        for text in ["{}", "[]", "{\"a\":[1,{\"b\":null}],\"c\":true}", " { \"a\" : 1 } ",
                     "{\"a\":\"\\u00e9\\n\\t\\\"\\\\\\/\"}", "{\"a\":\"\\uD83D\\uDE00\"}",
                     "[1,2,3]", "\"bare\"", "null", "false", "17"] {
            #expect(holds(text), "\(text)")
        }
    }

    @Test func theShapesThatDoNotHoldTogetherAreNot() {
        for text in ["{", "}", "{\"a\":}", "{\"a\":1,}", "[1,]", "[1 2]", "{a:1}", "{\"a\" 1}",
                     "{\"a\":1}{\"b\":2}", "{\"a\":1} trailing", "tru", "", "   "] {
            #expect(!holds(text), "\(text)")
        }
    }

    // A string has to denote a string, not merely parse as one: Foundation refuses these where the
    // value is made, and before this they were discarded (REQ-ERR-009). Saying yes to them here
    // would answer `settingOutOfRange` for a message nobody could read.
    @Test func aStringThatDenotesNoStringIsNotWellFormed() {
        for text in ["{\"a\":\"\\uD800\"}", "{\"a\":\"\\uDC00\"}", "{\"a\":\"\\uD800\\u0041\"}",
                     "{\"a\":\"\\uD800x\"}", "{\"a\":\"\\uDE00\\uD83D\"}", "{\"a\":\"\\uZZZZ\"}",
                     "{\"a\":\"\\u00\"}", "{\"a\":\"\\q\"}", "{\"a\":\"unclosed}"] {
            #expect(!holds(text), "\(text)")
        }
        // A raw control character has to be written as an escape.
        #expect(!JSONWellFormedness.holds(for: Data("{\"a\":\"".utf8) + Data([0x0A]) + Data("\"}".utf8)))
        // Bytes that are not UTF-8 denote nothing either.
        #expect(!JSONWellFormedness.holds(for: Data("{\"a\":\"".utf8) + Data([0xFF]) + Data("\"}".utf8)))
    }

    // The walk is recursive and the bytes come off the network, so nesting is bounded rather than
    // followed. Foundation stops sooner on its own, so the cases this refuses are ones it has
    // already refused — what matters is that the answer arrives instead of the process ending.
    @Test func deepNestingIsRefusedRatherThanFollowed() {
        for depth in [16, 200, 10_000, 200_000] {
            let nested = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
            #expect(holds("{\"v\":\(nested)}") == (depth <= 200), "depth \(depth)")
        }
    }

    // A message far deeper than anything Mdoro sends is turned away rather than answered for, and
    // the decoder is the one that turns it away — the point is that neither end ends the process.
    @Test func aDeeplyNestedCommandIsDiscardedAndNotACrash() {
        let nested = String(repeating: "[", count: 50_000) + String(repeating: "]", count: 50_000)
        let json = """
        {"type":"command","messageId":"m1","sentAt":"2023-11-14T22:13:20Z","clientRequestId":"r1",
         "action":"updateSettings","params":{"settings":{"logicalDayStartHour":1e309,"x":\(nested)}}}
        """
        #expect(throws: (any Error).self) { try MessageCoder.decodeClient(Data(json.utf8)) }
    }
}
