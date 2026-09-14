// REQ-ERR-009: a broken message is thrown away on its own, but ten in a row say the line itself is
// no good rather than the one message. **Counting is the whole of what this does.** What a run of
// ten leads to belongs to the caller, and the two ends answer it differently: the iPhone makes the
// connection again (REQ-COM-004), and the Mac — which never dials, so has no "again" of its own —
// hangs up, which is what sets that reconnect going.
//
// REQ-PRT-001: **one counter, shared.** It sat inside the iPhone's client while that end was the
// only one counting; the clause naming the Mac as the other counter is what moved it here.
public struct BrokenMessageCounter: Sendable, Equatable {
    // REQ-ERR-009: "ten in a row". The number the requirement names, in one place.
    public static let limit = 10

    public private(set) var count = 0

    public init() {}

    // True when this failure is the tenth in a row, and the count starts over at that point:
    // anything still in flight on the doomed connection must not ask for a second hang-up.
    public mutating func recordBroken() -> Bool {
        count += 1
        guard count >= Self.limit else { return false }
        count = 0
        return true
    }

    // A message that decodes puts the count back to zero — the requirement says *in a row*.
    public mutating func reset() {
        count = 0
    }
}
