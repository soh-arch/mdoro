import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// **No clause asks for this vocabulary.** The reader Decision 0018 wrote the log for — a stranger
// seeing it pasted into an issue — is the whole of why the endings are told apart at all, which is
// the same footing `ServerRefusalLogTests` stands on. Nothing here touches a connection: what is
// checked is that the words are usable by that reader, and that the one computed value in the line
// says what it claims to.
//
// REQ-ERR-010 / Decision 0018 reach **the form the writing takes** — one event per line, the level
// column that reader scans, nothing of the user's own words — and that is what the words below are
// held against.
//
// The wiring — which ending each of the seven paths out of a connection hands in — is watched over
// a real line in `ServerUnderARealConnectionTests`, because reaching those paths takes a connection
// the Mac has accepted.

@Suite("How an ending is written down (REQ-ERR-010)")
@MainActor
struct ConnectionEndingTests {

    // The whole point of the field is telling the endings apart, so two of them reading the same
    // would be the one fault that makes the line worthless. Walking `allCases` rather than a list
    // means an ending cannot be added without this saying something about it.
    @Test func everyEndingReadsDifferentlyFromEveryOther() {
        let words = ConnectionEnding.allCases.map(\.rawValue)
        #expect(Set(words).count == ConnectionEnding.allCases.count,
                "two endings are written with the same word, so the log cannot tell them apart")
        // The empty ones are gathered first rather than asked for inside the expectation.
        // `contains(where:)` is `rethrows`, and `#expect` takes a function call apart to report
        // its pieces — `__checkFunctionCall(words.self, calling: { $0.contains(where: $1) }, …)` —
        // where the key path arrives as an opaque argument and its not-throwing is no longer
        // visible. The compiler then asks for `try` on a call that cannot throw. A closure written
        // out in full is read differently and compiles, but a value computed on its own line is
        // the version that does not depend on how a macro chooses to read it.
        let unwritten = words.filter(\.isEmpty)
        #expect(unwritten.isEmpty, "\(unwritten.count) ending(s) are written as an empty word")
    }

    // One event per line, `key=value` separated by spaces (`DiagnosticLogFormat.line`).
    // `DiagnosticField` would turn a space into `_` on the way in, so a word with one in it would
    // not break the line — it would arrive disguised, which is worse for the reader than a refusal
    // here.
    @Test func noEndingCarriesSomethingThatWouldDisguiseItselfInTheLine() {
        for ending in ConnectionEnding.allCases {
            let word = ending.rawValue
            #expect(word == DiagnosticField(ConnectionEndingLine.howKey, word).value,
                    "`\(word)` is rewritten on its way into the line")
            #expect(!word.contains("="), "`\(word)` would read as two fields")
        }
    }

    // Decision 0018: a reader scanning a pasted log for trouble reads the levels. An ending that
    // means something went wrong is a `WARN`; one that is the design working is not, or the reader
    // learns to skip the column. **Stated case by case**, because that is the claim — a `switch`
    // in the test would only restate the one under test.
    @Test func theLevelSeparatesTroubleFromTheDesignWorking() {
        let trouble: Set<ConnectionEnding> = [
            .heartbeatTimeout, .transportFailed, .transportCancelled, .brokenMessageRun,
        ]
        for ending in ConnectionEnding.allCases {
            let expected: DiagnosticLevel = trouble.contains(ending) ? .warn : .info
            #expect(ending.level == expected, "`\(ending.rawValue)` is written as \(ending.level.rawValue)")
        }
    }

    // **No clause asks for this code.** REQ-SEC-004 is why there is anything to write down here — a
    // question the user never answered is taken away from them after 60 seconds — and REQ-ERR-010
    // reaches only the form the writing takes. Giving that moment a code of its own is for the reader
    // Decision 0018 wrote the log for, and it only works if the word is different from the ending
    // line's and reaches the file unchanged. `DiagnosticEvent` puts a code through the same tidying a
    // field goes through, so a code with a space in it would arrive disguised rather than refused.
    //
    // Why it is not a `conn.end`: that line is written beside `conn up=no` and says how the
    // connection **the Mac was holding** ended, and it carries `silent`, which is read from the
    // authenticated connection's stamp. A line the Mac never accepted has neither, so borrowing the
    // code would show a reader a disconnection that never happened with a number belonging to a
    // different connection. **Which ending it was is the same vocabulary**, and that is checked over
    // a real line in `PendingApprovalEndingTests`.
    @Test func aWithdrawnApprovalIsWrittenUnderACodeOfItsOwn() {
        let withdrawn = ConnectionEndingLine.approvalWithdrawnCode
        #expect(withdrawn != ConnectionEndingLine.code,
                "a banner that came down and a connection that ended would be one word to grep for")
        #expect(DiagnosticEvent(code: withdrawn).code == withdrawn,
                "`\(withdrawn)` is rewritten on its way into the line")
        #expect(!withdrawn.isEmpty, "the withdrawn approval is written under an empty code")
    }

    // REQ-COM-005: the number the heartbeat judgement was made on, to a tenth of a second.
    @Test func theSilenceIsTheSecondsSinceTheLastHeartbeat() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ConnectionEndingLine.silence(since: now.addingTimeInterval(-15.44), now: now) == "15.4")
        #expect(ConnectionEndingLine.silence(since: now, now: now) == "0.0")
        // The number has to be readable by a stranger, which means a decimal point and no grouping
        // wherever the reporter happens to live.
        let long = ConnectionEndingLine.silence(since: now.addingTimeInterval(-98_765.4), now: now)
        #expect(long == "98765.4", "the seconds came out as `\(long)`")
    }

    // A stamp that is not there is the word the header already uses for an absent value, not a zero
    // that would read as "the phone beat just now".
    @Test func anAbsentStampIsSaidToBeAbsentRatherThanReadAsZero() {
        #expect(ConnectionEndingLine.silence(since: nil, now: Date()) == "unset")
    }

    // A wall clock that moved backwards between the stamp and the ending is left visible. Clamping
    // it to zero would turn "this Mac's clock jumped" into "the phone beat a moment ago" — and the
    // second of those is a fact the reader would act on.
    @Test func aClockThatWentBackwardsShowsAsNegativeRatherThanZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ConnectionEndingLine.silence(since: now.addingTimeInterval(2.5), now: now) == "-2.5")
    }
}
