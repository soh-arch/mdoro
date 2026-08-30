import Foundation

// REQ-LOG-002 / Decision 0033: whether the session log has anywhere to go.
//
// **An unset destination is not a failed write. It is a destination nobody has chosen yet**, and
// every user starts there. Keeping the two apart is the whole point of this type: a failure is
// queued, retried and eventually notified (REQ-LOG-005 / REQ-ERR-004), and none of that may happen
// to a folder that was simply never set. The timer itself is untouched either way — sessions run,
// finish and count their loops with nowhere to write them (Decision 0033).
public enum LogDestination: String, Sendable, Equatable, CaseIterable {
    case configured
    case notSet

    public init(isConfigured: Bool) { self = isConfigured ? .configured : .notSet }

    // REQ-LOG-002: while nothing is set, an entry is neither written nor kept for later.
    public var recordsEntries: Bool { self == .configured }

    // REQ-LOG-002 / Decision 0033: what a queue saved by an earlier run may bring back.
    //
    // Entries queued while nothing was set were never meant to exist. Carried over, they would all
    // land in the file the moment a folder is chosen — days of sessions the user never asked to
    // write. Entries queued while a folder *was* set are genuine write failures and are kept, which
    // is what REQ-LOG-005 requires of them.
    public func carryOver(_ saved: [LogEntry]) -> LogCarryOver {
        recordsEntries
            ? LogCarryOver(kept: saved, dropped: 0)
            : LogCarryOver(kept: [], dropped: saved.count)
    }
}

// The outcome of `LogDestination.carryOver`. **The count is carried so the drop is not silent**:
// Decision 0018 allows a number in the diagnostic log and nothing that came from the user.
public struct LogCarryOver: Equatable, Sendable {
    public let kept: [LogEntry]
    public let dropped: Int

    public init(kept: [LogEntry], dropped: Int) {
        self.kept = kept
        self.dropped = dropped
    }
}
