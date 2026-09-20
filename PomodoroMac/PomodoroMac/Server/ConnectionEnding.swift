import Foundation
import MdoroCore

// REQ-ERR-010 / Decision 0018: **how the connection the Mac was holding came to an end.**
//
// The reader of this log is a stranger looking at it pasted into an issue, and until this existed
// every ending reached them as the single line `conn up=no`. A phone that had gone silent for
// fifteen seconds (REQ-COM-005), a line the transport ended under it (REQ-COM-004), a token the
// user revoked (REQ-SEC-002) and ten unreadable messages in a row (REQ-ERR-009) all wrote that one
// line and nothing else — so "it disconnected at 14:15" could be answered no further than the
// clock. That is not a hypothetical: `2026-09-19T14:15:17` in the author's own log is exactly it.
//
// **These are words, not failures, so they do not go out under `why`.** Decision 0034 gives that
// field one shape — `case(domain:code)`, every value a `DiagnosableError` — precisely so a reader
// cannot tell an OS failure from one of ours by how it is written. Most of the endings below are
// not failures at all: a revocation and a phone that closed its line politely are the design
// working. Borrowing `why` would mint error codes for things that never failed, and would put a
// value in that field that answers neither of the two questions it promises.
//
// Decision 0018: **a word from this list and a number or two are the whole of what is written.**
// Nothing of the device reaches the line — not its name, not its address, not its token. There is
// no masking step here, because there is nothing to mask.
//
// This lives beside the server rather than in `MdoroCore` because the diagnostic log is the Mac's
// alone (Decision 0018, judgement 5); the iPhone has no file for any of it to be written to.
// `nonisolated` for the same reason `WebSocketLineReads` is: this target's default isolation is the
// main actor, and a word and a number are answers no actor needs to be entered for. It is written
// from the main actor and read from a test that is not on it.
nonisolated enum ConnectionEnding: String, CaseIterable, Sendable {

    // REQ-COM-005: fifteen seconds with no `heartbeat` from the authenticated connection. The line
    // carries `silent`, which is the very number this judgement was made on.
    case heartbeatTimeout

    // REQ-COM-004: a read said the line was over — a close frame, a read that failed, or a
    // completed read carrying neither frame nor bytes. **A peer that closes politely leaves the
    // connection `.ready`**, so the read loop is the only place that ending is heard.
    case lineEnded

    // The transport put the connection into `.failed` before any read reported it.
    case transportFailed

    // `.cancelled` reached the state handler while the Mac still believed in this connection,
    // which means nothing in `MdoroServer` asked for it: every other ending here cancels and hands
    // the connection back in the same breath, so its own echo arrives after `connection` has
    // already been let go of and is refused by `handleDisconnect`'s guard.
    case transportCancelled

    // REQ-SEC-002 / Decision 0040: the token this connection authenticated with was revoked, and a
    // connection left standing on a revoked token would say the pairing was still good.
    case tokenRevoked

    // REQ-ERR-009: ten unreadable messages in a row. The line carries `broken`, the length of the
    // run that ended it.
    case brokenMessageRun

    // REQ-SEC-004: another hello was accepted and the standing connection was folded to make room
    // for it. **No `conn up=no` is written for this one** — the Mac does not stop being connected —
    // so without this line the ending leaves no trace of any kind.
    case displacedByNewHello

    // The listener was folded and the connection went with it, with no callback made:
    // `stopServer()`, or the fold at the top of `start()` that a rename goes through. The
    // deliberate route writes `server.stop` beside this; the rename's fold writes nothing at all,
    // and that is the case this is here for.
    case serverStopped

    // A reader scanning a pasted log for trouble should not have to know which of these are
    // routine. Four of them say something went wrong; the rest are the design working, and a
    // `WARN` on those would teach the reader to ignore the ones that matter.
    var level: DiagnosticLevel {
        switch self {
        case .heartbeatTimeout, .transportFailed, .transportCancelled, .brokenMessageRun: .warn
        case .lineEnded, .tokenRevoked, .displacedByNewHello, .serverStopped: .info
        }
    }
}

// REQ-ERR-010: the shape of the line, in one place, so that what is written and what a test reads
// back cannot drift apart.
nonisolated enum ConnectionEndingLine {

    // One word that greps well, beside `conn` and `conn.refused`.
    static let code = "conn.end"

    // REQ-SEC-004: **the connection request the user was being asked about ended before they
    // answered**, so the question was taken away from them (`MdoroServer.foldPendingApproval`).
    // A code of its own rather than a `conn.end`: the line it is about was never the connection the
    // Mac held, so counting it as one of those endings would have a reader see a disconnection that
    // never happened — and `silent` below, which every `conn.end` carries, describes the held
    // connection and not this one. **The `how` is the same vocabulary**, because how a line ends is
    // the same question whichever line it was.
    static let approvalWithdrawnCode = "approval.withdrawn"

    static let howKey = "how"
    static let silentKey = "silent"
    static let brokenKey = "broken"

    // REQ-COM-005: **how long the phone had been silent when the connection ended, in seconds.**
    //
    // This is the same arithmetic `Heartbeat.isStale` makes — the wall clock `lastHeartbeatAt` was
    // stamped from, against the `now` the judgement used — so the number in the log and the
    // judgement that produced the line cannot disagree. It is written for every ending, not only
    // for a timeout: on a line that simply ended, whether the phone was beating a moment ago or
    // had been quiet for fourteen seconds is the difference between a phone that went away and a
    // line that dropped under a healthy one.
    //
    // **A negative value is left as it is.** It means the wall clock moved backwards between the
    // stamp and the ending, which is worth seeing rather than clamping into a plausible zero.
    //
    // `unset` is the word `DiagnosticHeader` already uses for a value that is not there. Reaching
    // it means a connection the Mac believed in had never been stamped, which the accept in
    // `settle` is supposed to make impossible.
    static func silence(since lastHeartbeatAt: Date?, now: Date) -> String {
        guard let lastHeartbeatAt else { return "unset" }
        // No locale is passed, so the decimal separator is a point wherever this runs. A reader on
        // an issue must not have to know the reporter's region to read a number.
        return String(format: "%.1f", now.timeIntervalSince(lastHeartbeatAt))
    }
}
