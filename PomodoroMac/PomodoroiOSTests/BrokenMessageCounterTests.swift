import Testing
@testable import MdoroiOS

// REQ-ERR-009: one broken message is thrown away; **ten in a row** mean the connection is remade.
@Suite("Counting broken messages")
struct BrokenMessageCounterTests {

    @Test func theRequirementSaysTen() {
        #expect(BrokenMessageCounter.limit == 10)
    }

    @Test func theTenthInARowAsksForTheReconnect() {
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

    // Whatever is still in flight on the doomed connection must not ask for a second reconnect.
    @Test func theCountIsZeroOnceItHasAsked() {
        var counter = BrokenMessageCounter()
        for _ in 1...BrokenMessageCounter.limit { _ = counter.recordBroken() }
        #expect(counter.count == 0)
        #expect(counter.recordBroken() == false)
    }
}
