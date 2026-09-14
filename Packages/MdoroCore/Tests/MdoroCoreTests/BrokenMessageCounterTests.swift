import Testing
import MdoroCore

// REQ-ERR-009: one broken message is thrown away; **ten in a row** mean the line itself is no good.
//
// REQ-PRT-001: **the counter is shared, so these run once for both ends.** They moved here with it
// — while it lived in the iPhone's client they ran inside MdoroiOSTests, which needs a simulator,
// and the Mac had no counter to run them against at all.
@Suite("Counting broken messages")
struct BrokenMessageCounterTests {

    @Test func theRequirementSaysTen() {
        #expect(BrokenMessageCounter.limit == 10)
    }

    @Test func theTenthInARowIsTheOneThatAsksForTheLineToEnd() {
        var counter = BrokenMessageCounter()
        for _ in 1..<BrokenMessageCounter.limit {
            #expect(counter.recordBroken() == false, "the connection is kept until the tenth")
        }
        #expect(counter.recordBroken() == true)
    }

    @Test func oneMessageThatDecodesStartsTheRunOver() {
        var counter = BrokenMessageCounter()
        for _ in 1..<BrokenMessageCounter.limit { _ = counter.recordBroken() }
        counter.reset()
        #expect(counter.count == 0)
        // Nine more are still nine, not nineteen.
        for _ in 1..<BrokenMessageCounter.limit {
            #expect(counter.recordBroken() == false)
        }
        #expect(counter.recordBroken() == true)
    }

    // Whatever is still in flight on the doomed connection must not ask for a second hang-up.
    @Test func theCountIsZeroOnceItHasAsked() {
        var counter = BrokenMessageCounter()
        for _ in 1...BrokenMessageCounter.limit { _ = counter.recordBroken() }
        #expect(counter.count == 0)
        #expect(counter.recordBroken() == false)
    }
}
