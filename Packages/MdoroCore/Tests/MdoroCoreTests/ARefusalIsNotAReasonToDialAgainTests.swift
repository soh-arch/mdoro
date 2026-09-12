import Testing
import Foundation
@testable import MdoroCore

// REQ-COM-004: **a refusal is an answer, not a line that dropped.**
//
// The clause spoke only of a temporary network outage, and the client read every ending the same
// way — so a Mac that refused a `hello` got the same `hello` back at the thirty-second ceiling for
// ever, while the iPhone asked the user nothing and told them nothing. v2.36 wrote down what
// happens outside that scope: stop dialling, let the pairing code go, and show the user the next
// move — **which is not the same move for every reason** (REQ-PRT-004: a version wants an update,
// and six digits cannot mend one).
//
// The client and the banner live in the iPhone target, which `swift test` cannot link. Reading
// their source is how a rule this package's own types take part in stays checked in CI — the same
// route `ProtocolRefusalTests` takes to `MdoroServer` next door.
@Suite("A refusal is not a reason to dial again (REQ-COM-004 / REQ-PRT-004)")
struct ARefusalIsNotAReasonToDialAgainTests {

    // MARK: - What the refusal itself says (no source reading: these are this package's own types)

    // REQ-PRT-004 is a **MUST**, and it has two halves: refuse the connection, **and prompt both
    // devices to update**. Decision 0035 leaves the wording to the side with the screen, so this
    // one sentence is the whole of the second half.
    //
    // REQ-COM-004 adds the other edge: **it must not be the sentence that sends the user to a
    // pairing field.** Re-entering six digits cannot mend a version, so a user sent there loops
    // between a code and the same refusal with nothing changing.
    @Test func theVersionRefusalAsksForAnUpdateAndNeverForAPairingCode() {
        let shown = ProtocolRefusal.protocolVersionMismatch.protocolErrorCode.displayMessage.lowercased()

        #expect(shown.contains("update"),
                "REQ-PRT-004: the refusal that has to prompt an update does not mention one")
        for pairing in ["code", "pair", "digit"] {
            #expect(!shown.contains(pairing),
                    "REQ-COM-004: this refusal sends the user to pair, and pairing cannot mend a version")
        }
    }

    // The client turns an arriving `error.code` back into a `ProtocolRefusal` by walking
    // `allCases` — **the reverse of the very map the Mac sends by, rather than a second map of its
    // own that could drift from it.** That reversal is a function only while no two refusals share
    // a wire code, so the day a second refusal is added, this is what says so.
    @Test func noTwoRefusalsShareAWireCode() {
        let codes = ProtocolRefusal.allCases.map(\.protocolErrorCode)
        #expect(Set(codes).count == codes.count,
                "the client's reverse lookup would answer with whichever refusal it met first")
    }

    // And every one of them has something to say, because the state the client enters on a refusal
    // shows this sentence and nothing else. 10.2's catalogue is exhaustive over `displayMessage`,
    // so what is checked here is the hop from the refusal to the code.
    @Test func everyRefusalHasASentenceToPutOnTheScreen() {
        for refusal in ProtocolRefusal.allCases {
            #expect(!refusal.protocolErrorCode.displayMessage.isEmpty)
        }
    }

    // MARK: - What the client does with one

    // REQ-COM-004: **both refusals stop the dialling.** The Mac closes the line straight after
    // either, so the `.ended` that follows must not be read as a network that dropped.
    @Test func eitherRefusalStopsTheClientDialling() throws {
        let text = try clientSource()

        for refusal in ["authFailed", "error"] {
            let arm = try branch(refusal, in: text)
            #expect(arm.contains("stopDialling()"),
                    "REQ-COM-004: a `\(refusal)` refusal leaves the client sending the same hello for ever")
        }
    }

    // REQ-COM-004: and stopping means **the pairing code at hand goes too.** Held, it keeps
    // `sendHello` out of the one branch that asks the user for a new one — which is exactly the
    // silence the clause names: not connected, and never asked anything.
    @Test func stoppingLetsThePairingCodeGoAndIsWhatTheReconnectReads() throws {
        let text = try clientSource()
        let stopping = try body(ofFunction: "stopDialling", in: text)

        #expect(stopping.contains("pairingCode = nil"),
                "REQ-COM-004: the code is kept, so the user is left waiting without being asked")
        #expect(stopping.contains("isStopping = true"))
        #expect(text.contains("guard !isStopping else { return }"),
                "REQ-COM-004: the reconnect no longer reads the flag a refusal sets, so it dials on")
    }

    // REQ-PRT-004: **a version mismatch must not cost the user their pairing.** Deleting
    // the token is the one thing the client does to a registration it holds, and exactly one
    // refusal may reach it — the one that says this Mac no longer knows this device.
    @Test func onlyAnUnknownTokenEverMakesTheClientDeleteOne() throws {
        let text = try clientSource()
        #expect(text.components(separatedBy: "tokens.delete(").count - 1 == 1,
                "the client deletes a token somewhere new — REQ-PRT-004 has to be read against that path too")

        let refused = try branch("error", in: text)
        #expect(!refused.contains("tokens.delete("),
                "REQ-PRT-004: the version refusal throws the pairing away, and the pairing is not what is wrong")

        let authFailed = try branch("authFailed", in: text)
        #expect(authFailed.contains("tokens.delete("))
        #expect(authFailed.contains("payload.code == .unknownDeviceToken"),
                "REQ-PRT-004: the delete is loose from the one reason that means the token itself is gone")
    }

    // REQ-ERR-016 / 10.2: **`error` carries two different kinds of news.** One of its codes is a
    // handshake that failed and the Mac hangs up after it; every other one answers a command sent
    // on a connection that goes on standing. Treating the second kind like the first would tear
    // down a live connection over a preset that could not be renamed.
    @Test func anErrorThatIsNotARefusalStillReachesTheBanner() throws {
        let text = try clientSource()
        let refused = try branch("error", in: text)

        #expect(refused.contains("ProtocolRefusal.allCases"),
                "the handshake refusals are picked out by a code written here rather than by the shared list")
        #expect(refused.contains("callbacks?.receivedError(payload)"),
                "REQ-ERR-016: a refused command no longer reaches the screen at all")
    }

    // MARK: - What the user sees

    // REQ-COM-004: **a state nothing reads changes nothing for the user**, which is the whole of
    // what went wrong here. So the refused state is on the banner, and — REQ-PRT-004 — what it
    // offers is the update and not a field for six digits.
    @Test func theRefusedStateIsShownAndIsOfferedNoPairingField() throws {
        let views = try swiftFiles(under: "PomodoroMac/PomodoroiOS/Views")
        let banner = try #require(views["ConnectionViews.swift"])

        let refused = try noticeBranch(after: "case let .refused(reason) = model.status {", in: banner)
        #expect(refused.contains("displayMessage"),
                "REQ-PRT-004: the refused state shows nothing, so nobody is prompted to update")
        #expect(!refused.contains("pairingField"),
                "REQ-COM-004: a version mismatch asks for a code, and a code cannot mend a version")

        // REQ-COM-004: the other refusal is the opposite case. Nothing is dialling any more, so a
        // reason shown with no control beside it is the same dead end by another door.
        let failed = try noticeBranch(after: "case let .failed(code) = model.status {", in: banner)
        #expect(failed.contains("pairingField"),
                "REQ-COM-004: a refused pairing shows its reason and no way forward")
    }

    // REQ-COM-013 / REQ-UIX-004: and it is one of the not-connected states. The compiler makes the
    // classification exhaustive; **which side of it this lands on is a judgement, not a compile
    // error** — `reconnecting` would put a spinner over a line nobody is trying to open.
    @Test func theRefusedStateCountsAsNotConnected() throws {
        let model = withoutComments(try source("PomodoroMac/PomodoroiOS/ClientModel.swift"))
        let line = try #require(model.split(separator: "\n").first(where: { $0.contains("return .disconnected") }),
                                "the connection states are classified somewhere new")
        #expect(line.contains(".refused"),
                "REQ-COM-013: a refusal reads as reconnecting, over a line nothing is dialling")
    }

    // MARK: - Reading the iPhone target

    private func clientSource() throws -> String {
        withoutComments(try source("PomodoroMac/PomodoroiOS/Client/MdoroClient.swift"))
    }

    // One `case` of the client's switch over what arrived, up to the next one — or, for the last
    // case, up to the switch's own closing brace.
    private func branch(_ name: String, in text: String) throws -> String {
        guard let opening = text.range(of: "case let .\(name)(payload):") else {
            throw ShapeHasMoved(what: "`\(name)` as a branch of the client's switch")
        }
        let rest = text[opening.upperBound...]
        let ends = ["\n        case ", "\n        }"].compactMap { rest.range(of: $0)?.lowerBound }
        guard let end = ends.min() else { return String(rest) }
        return String(rest[..<end])
    }

    // The body of a no-argument method, up to the closing brace at method indentation.
    private func body(ofFunction name: String, in text: String) throws -> String {
        guard let opening = text.range(of: "func \(name)() {") else {
            throw ShapeHasMoved(what: "`\(name)()` in the client")
        }
        let rest = text[opening.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    // One arm of the banner's `if` / `else if` chain, up to the next arm.
    private func noticeBranch(after opening: String, in text: String) throws -> String {
        guard let start = text.range(of: opening) else {
            throw ShapeHasMoved(what: "`\(opening)` in the connection banner")
        }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: "} else if") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }
}

// **A shape that moved is not a shape that passes.** Answering "nothing to object to" when the
// code has been rearranged is the one failure a test that reads source exists to prevent, so every
// slice that cannot find its landmark says so instead of returning an empty string.
private struct ShapeHasMoved: Error, CustomStringConvertible {
    let what: String
    var description: String { "\(what) could not be found — this test is reading the wrong shape" }
}
