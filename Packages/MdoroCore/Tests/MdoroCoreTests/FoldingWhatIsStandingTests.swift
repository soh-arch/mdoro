import Testing
import Foundation
@testable import MdoroCore

// **Two things `MdoroServer` folds to make room, and what it does about them is read here rather
// than driven.**
//
// REQ-SEC-004 gives the Mac two kinds of thing that can be standing when a hello arrives: the
// connection it is holding, and a connection request a question is already waiting on. Three faults
// have come out of that pair. The exemption for the line the hello itself arrived on was missing
// from one of the two places it was written; it was then found to cover, in the other place, the log
// line but not the hang-up beside it; and `stop()` hangs up on a pending line and lets go of it in
// the other order from the one `foldPendingApproval` keeps.
//
// **All three are quiet.** Each shows up as an extra `approval.withdrawn` or an extra `conn.end` in
// a diagnostic file, or as a connection torn down one hop of the main actor after the screen was
// told it was up — none of them is a crash, a refusal, or anything a reader would think to report.
// The app targets drive the two that behaviour can reach (`ServerUnderARealConnectionTests`), and
// they do not run in CI. These read the source, which is the route this package already takes to
// rules the app targets keep, and they do run in CI.
//
// **What is read here is the shape of the code, not what it does.** That makes the failure messages
// the whole of the value: a scan that finds nothing to object to because its anchor was renamed
// passes, which is the one failure these exist to prevent, so every anchor is `#require`d rather
// than searched for.

private let macServer = "PomodoroMac/PomodoroMac/Server/MdoroServer.swift"

// The body of one named declaration in the server, comments already gone. `declarationBody` ends the
// window at the brace that closes the declaration, so no count of lines is being spent here and prose
// written inside the body cannot slide the answer.
//
// **The count of the pieces is what catches a renamed anchor, and it has to stop the scan.**
// `components(separatedBy:)` answers one piece when the separator is nowhere in the text, so
// `pieces.last` is never nil and asking for it catches nothing at all. Noting the count and carrying
// on is not enough either: the piece handed on is then the whole file, and the run goes red out of
// `declarationBody` saying that no brace closes the declaration — true, and it says nothing about the
// anchor a reader would have to go looking for. So this throws, and the sentence a reader sees names
// the anchor and what became of it.
private func bodyOfDeclaration(_ marker: String) throws -> String {
    let server = withoutComments(try source(macServer))
    let pieces = server.components(separatedBy: marker)
    try #require(
        pieces.count == 2,
        "\(macServer) holds \(pieces.count - 1) of `\(marker)` where one is expected — it was renamed or a second one was written, and a scan reading one of two says nothing about the other. This scan is watching nothing until the anchor is put right."
    )
    // Safe by the count above: two pieces mean the marker is there exactly once, and the second piece
    // is what follows it.
    let body = try declarationBody(openedBy: pieces[1], marker)
    #expect(!body.isEmpty, "the window is empty, and anything read from an empty window agrees")
    return body
}

// The statements of a body, in order, trimmed, with the blank lines a stripped comment leaves behind
// dropped. **The claims below are about which statement comes before which**, and that is a question
// a character offset inside a single line cannot be asked.
private func statements(of body: String) -> [String] {
    body.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

@Suite("Folding what is standing")
struct FoldingWhatIsStandingTests {

    // REQ-SEC-004 / REQ-ERR-010: **`stop()` lets go of a waiting question before it hangs up on the
    // line the question was asked on.**
    //
    // The hang-up's `.cancelled` echo arrives at `handleDisconnect`, which folds a `pendingApproval`
    // that is still standing when it gets there: `approval.withdrawn` written to the diagnostic log
    // and `resolveApproval(false)` called, on every stop, for a question nobody withdrew.
    //
    // **This is not a canary, and it is not a test of behaviour.** The two orders behave identically
    // as the file stands, and the reason is mechanical: the echo is a hop of the main actor away, and
    // between the two statements there is nothing for it to arrive before. A stop written the wrong
    // way round is silent, and goes on being silent until somebody puts a statement there — so it
    // leaves nothing to observe, no line in a log and no callback. **What is checked instead is that
    // the two statements are in the order that stays correct when something is put between them**,
    // which is a fact about the text and is read as one.
    //
    // The behaviour this ordering protects is driven in the app target, from the endings that reach
    // `foldPendingApproval` (`aReadThatSaysTheLineIsOverTakesTheQuestionWithIt` and the two beside
    // it). **Nothing is claimed here about which benches exist or what they reach** — the argument
    // above is the mechanism, and it is what a bench would have to get past: a run that could tell the
    // two orders apart is a run with a statement between them, which is a property of this code and
    // not of the suite.
    @Test func theStopLetsGoOfTheWaitingQuestionBeforeItHangsUpOnItsLine() throws {
        let body = try bodyOfDeclaration("func stop() {")
        let lines = statements(of: body)

        let releaseAt = try #require(
            lines.firstIndex(of: "pendingApproval = nil"),
            "nothing in `stop()`'s own body lets go of the waiting question, so a stopped server keeps one on record and the next answer is settled against it. **If the release and the hang-up were moved into a declaration of their own, that is not the fault this is about** — the ordering is what matters and it can live anywhere: point this scan at that declaration's marker instead of `func stop() {`."
        )

        // **The fault this exists for, in whatever position it is written.** A hang-up spelled
        // through the record is one the record is still holding when the echo comes back, and it
        // reads the same before the release as after it.
        for line in lines where line.contains("pendingApproval") {
            #expect(
                !line.contains("cancel("),
                "`stop()` hangs up on the waiting line through `pendingApproval` itself (`\(line)`), so the record is still standing when the `.cancelled` echo reaches `handleDisconnect` — every stop then writes `approval.withdrawn` and calls `resolveApproval(false)` for a question nobody withdrew"
            )
        }

        // Nothing else reads the record before it is released. A capture is allowed — letting go of
        // the record first is the whole point, and the line to hang up on has to come from somewhere
        // — and anything else is a statement acting on a question that is still standing.
        for line in lines.prefix(releaseAt) where line.contains("pendingApproval") {
            #expect(
                line.hasPrefix("let "),
                "`stop()` does `\(line)` while the waiting question is still on record"
            )
        }

        // **And the line is still hung up on.** Releasing the record without cancelling would leave
        // the phone holding an open connection with nothing on the Mac aware of it — a quieter fault
        // than the one above and a worse one, so the order is not read without it.
        let capture = try #require(
            lines.first { $0.hasPrefix("let ") && $0.contains("= pendingApproval") },
            "`stop()` never takes hold of the waiting line, so nothing after the release can hang up on it and the phone keeps a connection the Mac has forgotten"
        )
        let askingLine = try #require(
            capture.components(separatedBy: " ").dropFirst().first,
            "`\(capture)` names nothing that the hang-up below could be found by"
        )
        // The local cannot be named after the record, or the scan above would read a hang-up on it as
        // a hang-up through the record. Said out loud, because a rename would otherwise fail this
        // suite for a reason nobody could see.
        #expect(
            !askingLine.contains("pendingApproval"),
            "`\(askingLine)` is named after the record it was taken from, and the scan above cannot tell a hang-up on the local from a hang-up through the record — give it another name"
        )
        let hangUpAt = try #require(
            lines.firstIndex { $0.contains(askingLine) && $0.contains("cancel(") },
            "`stop()` takes hold of the waiting line as `\(askingLine)` and never hangs up on it"
        )
        #expect(
            hangUpAt > releaseAt,
            "`stop()` hangs up on the waiting line at statement \(hangUpAt) and lets go of the record at \(releaseAt) — in that order the echo of the hang-up finds the question still standing"
        )
    }

    // REQ-SEC-004: **the exemption for the line the hello arrived on is written once.**
    //
    // `settle` has two branches that fold what is standing, and the judgement they share is not
    // obvious enough to be rediscovered: a cancel of the line a hello just came in on reaches a gate
    // — `handleDisconnect`'s `closed === connection`, `foldPendingApproval`'s
    // `pending.connection === closed` — that is by then holding that very connection, so the gate
    // lets the echo through and the branch tears down what it had just stood up. Written out twice,
    // the exemption was missing from one branch, and then found to cover only the log line and not
    // the hang-up in the other. **A third correction is what one declaration takes away.**
    //
    // **This is a check on the shape of the code and not on what it does.** Two branches each
    // carrying a correct copy of the comparison would behave exactly as one shared declaration does,
    // and this would fail them — deliberately, because the two copies are the fault. What the
    // behaviour is remains the app target's to drive:
    // `aSecondHelloOnTheAskingLineDoesNotHangUpOnIt`,
    // `aSecondHelloOnTheHeldLineDoesNotHangUpOnTheConnectionItAccepts`,
    // `anAllowForASecondHelloOnTheHeldLineDoesNotHangUpOnIt` and
    // `aHelloFromAnotherLineStillFoldsTheOneTheMacWasHolding`.
    @Test func theExemptionForTheLineTheHelloArrivedOnIsWrittenOnce() throws {
        let settleBody = try bodyOfDeclaration("private func settle(")

        // Both branches go through the one declaration, and `settle` hangs up on nothing itself.
        let folds = settleBody.components(separatedBy: "fold(").count - 1
        #expect(
            folds == 2,
            "`settle` folds what is standing in \(folds) places, where the accept and the approval make two. **A number that has grown is not a fault in itself**: a third branch that reuses the shared declaration is exactly what this shape is for, and if that is what happened, this count is the thing to update. What the check refuses is a branch that went back to writing the judgement out for itself — which the two claims below are what catch."
        )
        #expect(
            !settleBody.contains("cancel("),
            "`settle` hangs up on a connection itself, outside the one declaration that decides whether that connection is the line the hello arrived on"
        )
        #expect(
            !settleBody.contains("!== source"),
            "`settle` compares against `source` in a branch of its own again, which is how the exemption came to be in one branch and not the other"
        )

        // And the declaration they share makes the comparison, once, and hangs up once.
        let foldBody = try bodyOfDeclaration("private func fold(")
        let exemptions = foldBody.components(separatedBy: "!== source").count - 1
        #expect(
            exemptions == 1,
            "the shared fold exempts `source` in \(exemptions) places. None means it hangs up on the line the hello arrived on, which is the fault it was written for; more than one is the shape it replaced. **If a second comparison here is deliberate, this count is the thing to update** — and the sentence above the declaration is where the reason belongs, because the next person reads that before this."
        )
        let hangUps = foldBody.components(separatedBy: "cancel(").count - 1
        #expect(
            hangUps == 1,
            "the shared fold hangs up in \(hangUps) places where both branches asked for one. **A second one is not read as wrong here, only as unexplained**: if the fold legitimately took on another, update this count and say above the declaration what the second one is for."
        )
    }
}
