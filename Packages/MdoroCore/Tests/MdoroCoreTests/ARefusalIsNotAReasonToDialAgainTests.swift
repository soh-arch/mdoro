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

// The banner is read out of its directory rather than by path, so that a view that moved is a
// directory `swiftFiles(under:)` can refuse — and the path is still spelled once, for the anchor
// lookups that have to name the file they were watching.
private let bannerDirectory = "PomodoroMac/PomodoroiOS/Views"
private let bannerFile = "ConnectionViews.swift"
private let bannerPath = bannerDirectory + "/" + bannerFile

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
    @Test func theRefusedStateIsShownWithARetryAndNoPairingField() throws {
        let refused = try noticeBranch(after: "case let .refused(reason) = model.status {", in: try bannerSource())

        #expect(refused.contains("displayMessage"),
                "REQ-PRT-004: the refused state shows nothing, so nobody is prompted to update")
        #expect(!refused.contains("pairingField"),
                "REQ-COM-004: a version mismatch asks for a code, and a code cannot mend a version")
        // REQ-COM-004: **and the update the sentence asks for has to be worth making.** The client
        // stopped dialling on the refusal and nothing starts it again by itself, so with no control
        // here the user updates the end that was behind and the app goes on showing the same
        // sentence until it is quit and opened again — the dead end the clause names, reached from
        // the one refusal that is most likely to have been mended since.
        #expect(refused.contains("tryAgain"),
                "REQ-COM-004: nothing here dials again, so a Mac that has been updated is never noticed")
    }

    // REQ-COM-004: **the reason, and a way out of it** — but not the same way out for all five.
    // Four of the `AuthFailureCode`s answer what the hello carried as credentials, and their
    // sentences name a code or name pairing again; `submitPairingCode` re-dials as it sends the six
    // digits. **`connectionRejectedByUser` is not one of them**: the token this iPhone holds is
    // good, the Mac's user simply did not approve, and there are no six digits anywhere in the
    // user's hands — a field there is a control with nothing to put in it, which is the same dead
    // end as no control at all. What that one needs is to ask again.
    //
    // The sorting is a `switch`, so **the compiler asks about a sixth reason** rather than letting
    // it inherit whichever side a default happened to be. Which side each of the five is on is not
    // a thing the compiler can ask about, which is what this reads.
    @Test func onlyTheFailuresThatSixDigitsCanMendAreOfferedTheField() throws {
        let failed = try noticeBranch(after: "case let .failed(code) = model.status {", in: try bannerSource())
        // Through `afterEachAnchor`: a `switch` written at another indentation leaves nothing to
        // loop over, and the count below would then read as an arm having been deleted.
        let arms = try afterEachAnchor("\n            case ", in: failed, of: bannerPath)
        #expect(arms.count == 2, "the banner no longer sorts the reasons into a control each")

        let rejected = try #require(arms.first(where: { $0.hasPrefix(".connectionRejectedByUser:") }),
                                    "REQ-SEC-004: the one reason no code can mend has no arm of its own")
        #expect(rejected.contains("tryAgain"),
                "REQ-SEC-004: a Mac that did not approve leaves the user with nothing to press")
        #expect(!rejected.contains("pairingField"),
                "REQ-SEC-004: an empty six-digit field, for a refusal that was never about a code")

        let mendable = try #require(arms.first(where: { !$0.hasPrefix(".connectionRejectedByUser:") }))
        for code in AuthFailureCode.allCases where code != .connectionRejectedByUser {
            #expect(mendable.contains(".\(code.rawValue)"),
                    "REQ-COM-004: `\(code.rawValue)` is sorted away from the field its own wording asks for")
        }
        #expect(mendable.contains("pairingField"),
                "REQ-COM-004: the reasons whose wording names a code are offered no way to enter one")
        #expect(!mendable.contains("tryAgain"),
                "REQ-COM-004: the same credentials sent back unchanged get the same refusal")
    }

    // REQ-COM-004: and "try again" has to mean dialling. A refusal stops the client for good —
    // `connect` is the only thing that clears the flag `scheduleReconnect` reads — so the control
    // has to reach the same door `submitPairingCode` goes through, **with no code in hand**: the
    // token this iPhone already holds is the whole of what it has to offer, and the user was asked
    // for nothing.
    @Test func tryingAgainDialsAgainWithTheTokenAlreadyHeld() throws {
        let control = try body(ofProperty: "tryAgain", in: try bannerSource())
        #expect(control.contains("\"Try again\""),
                "the wording the two stopped states are shown has changed")
        #expect(control.contains("model.redial()"),
                "REQ-COM-004: the control offered by both stopped states calls nothing")

        let model = withoutComments(try source("PomodoroMac/PomodoroiOS/ClientModel.swift"))
        let redial = try body(ofFunction: "redial", in: model)
        #expect(redial.contains("connect(to: server)"),
                "REQ-COM-004: trying again does not re-open the connection, which is the one thing it is for")
        #expect(!redial.contains("pairingCode"),
                "REQ-COM-004: trying again sends a code the user was never asked for")
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
            throw ShapeHasMoved(what: "`\(name)()` in the file it was being read from")
        }
        let rest = text[opening.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    private func bannerSource() throws -> String {
        let views = try swiftFiles(under: bannerDirectory)
        guard let banner = views[bannerFile] else {
            throw ShapeHasMoved(what: "`\(bannerFile)` among the iPhone's views")
        }
        return banner
    }

    // The body of a computed view property, up to the closing brace at member indentation.
    private func body(ofProperty name: String, in text: String) throws -> String {
        guard let opening = text.range(of: "var \(name): some View {") else {
            throw ShapeHasMoved(what: "`\(name)` in the connection banner")
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
