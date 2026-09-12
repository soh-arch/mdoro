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

    // **Whitespace is all four bytes RFC 8259 §2 names, not the two a message arrives with.** A
    // space and a newline are both read over wherever a command is scanned — the messages that
    // reach here carry them — so a tab and a carriage return are the only two whose place in the
    // set nothing establishes.
    @Test func aTabAndACarriageReturnAreWhitespaceTheSameWayASpaceIs() {
        // Kills: dropping 0x09 from the bytes that are skipped. Every space below is a tab, so a
        // reader that does not step over one stops on it and reads the message as broken.
        #expect(holds("\t{\t\"a\"\t:\t1\t}\t"))
        // Kills: dropping 0x0D. Same message, written with carriage returns instead.
        #expect(holds("\r{\r\"a\"\r:\r1\r}\r"))
    }

    // The array walk steps over the whitespace that follows an element, and every array above is
    // written closed up — `[1 2]` reaches the line but is refused either way, because what comes
    // next is a second number and not a comma.
    @Test func anArrayIsReadWithSpaceAroundItsElements() {
        // Kills: removing that skip. The object walk has its own, established by ` { "a" : 1 } `
        // above, so an array is the only place the loss shows.
        #expect(holds("[ 1 , 2 ]"))
    }

    // Two guards that only a key can reach: the one that has an object's member start with a
    // string, and the one that has a string open with a quote. Every key above is a well-formed
    // string, and `{a:1}` is refused by the colon that is missing rather than by either guard, so
    // both could stop being enforced without one answer above changing.
    @Test func aKeyHasToBeAStringAndAStringHasToOpenWithAQuote() {
        // Kills: no longer refusing a member whose key does not scan as a string. Without that
        // guard this reads as a nameless member and holds, because the `:` is already there.
        #expect(!holds("{:1}"))
        // Kills: no longer requiring the opening quote. Without it the key scan starts at `a` and
        // ends at the quote after it, swallowing the quote, and the rest of the object lines up.
        #expect(!holds("{a\":1}"))
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

    // The escape that never arrives: a `\` as the last byte there is. Every escape above is
    // followed by something, so nothing above is decided by the branch that finds nothing.
    @Test func aBackslashWithNothingAfterItEscapesNothing() {
        // Kills: answering yes where the bytes run out right after `\`. **It has to be the whole
        // text.** Inside an object the missing `}` refuses the message a step later whichever way
        // that branch answers, and the loss would not show — the same trap as the two below.
        #expect(!holds("\"\\"))
    }

    // REQ-ERR-009: a `\uD800` owes a low surrogate to **the escape right after it**, and the two
    // guards that say so are reached by an escape and by a raw character.
    //
    // **`{"a":"\uD800x"}` above reaches the second of them and still cannot tell whether it
    // fired.** Drop the debt from that guard and the raw `x` is let through, but the closing quote
    // one byte later finds the debt unpaid and refuses the string anyway: the answer is no either
    // way. **Paying the debt back after the intruding byte is what separates them.** With the
    // guards the string is refused where the intruder sits; without them it runs to the end, the
    // low surrogate settles the debt, and a string Foundation will not make holds.
    @Test func aSurrogateDebtIsOwedToTheVeryNextEscape() {
        // Kills: dropping `!owedALowSurrogate` from the guard over the simple escapes.
        #expect(!holds("{\"a\":\"\\uD800\\n\\uDC00\"}"))
        // Kills: dropping `!owedALowSurrogate` from the guard over raw characters.
        #expect(!holds("{\"a\":\"\\uD800x\\uDC00\"}"))
    }

    // The walk is recursive and the bytes come off the network, so nesting is bounded rather than
    // followed. Foundation stops sooner on its own, so the cases this refuses are ones it has
    // already refused — what matters is that the answer arrives instead of the process ending.
    //
    // **The bound is 256, and the two cases that matter are 256 and 257.** The wrapping object is
    // scanned at depth 0 and hands its value depth 1, so the *n*-th `[` is the one scanned at
    // depth *n*, and the innermost pair closes without asking for a depth of its own: a document
    // 256 deep is the last one accepted. Nothing here can read `depthLimit` — it is private to the
    // reader — so the number is written out, which is the point: moving the bound by one, or
    // turning `<=` into `<`, changes one of these two answers.
    @Test func deepNestingIsRefusedRatherThanFollowed() {
        for depth in [16, 200, 255, 256, 257, 10_000, 200_000] {
            let nested = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
            #expect(holds("{\"v\":\(nested)}") == (depth <= 256), "depth \(depth)")
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
