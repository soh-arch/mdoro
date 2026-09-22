import Testing
import Foundation
@testable import MdoroCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func hello(token: String? = nil, code: String? = nil, name: String = "iPhone",
                   version: Int = PomodoroProtocol.version) -> HelloPayload {
    HelloPayload(protocolVersion: version, deviceToken: token, pairingCode: code, deviceName: name)
}

// Decision 0040: **a token cannot be held without saying whose it is and when it was issued.**
// A bare value is not a thing the Mac can keep any more, which is why every one of these says both.
private func issued(_ value: String, to name: String = "iPhone", at when: Date = t0) -> DeviceToken {
    DeviceToken(value: value, deviceName: name, issuedAt: when)
}

@Suite("Pairing (REQ-SEC-001 / 003 / REQ-ERR-006)")
struct PairingSessionTests {

    @Test func codeIsSixDigits() {
        for value in [0, 7, 123_456, 999_999] {
            let code = PairingSession.generateCode { value }
            #expect(code.count == 6)
            let isAllDigits = code.allSatisfy { $0.isNumber }
            #expect(isAllDigits)
        }
    }

    // REQ-SEC-003: valid for three minutes only.
    @Test func codeExpiresAfterThreeMinutes() {
        var session = PairingSession(code: "123456", startedAt: t0)
        #expect(!session.isExpired(now: t0.addingTimeInterval(179)))
        #expect(session.isExpired(now: t0.addingTimeInterval(181)))
        let expired = session.verify("123456", now: t0.addingTimeInterval(181))
        #expect(expired == .rejected(.pairingModeNotActive))
    }

    @Test func remainingSecondsCountsDown() {
        let session = PairingSession(code: "123456", startedAt: t0)
        #expect(session.remainingSeconds(now: t0) == 180)
        #expect(session.remainingSeconds(now: t0.addingTimeInterval(120)) == 60)
        #expect(session.remainingSeconds(now: t0.addingTimeInterval(999)) == 0)
    }

    @Test func correctCodeIsAccepted() {
        var session = PairingSession(code: "123456", startedAt: t0)
        let outcome = session.verify("123456", now: t0)
        #expect(outcome == .accepted)
    }

    // REQ-ERR-006: five wrong codes in a row end pairing mode.
    @Test func fiveWrongAttemptsLockOut() {
        var session = PairingSession(code: "123456", startedAt: t0)
        for attempt in 1...4 {
            let outcome = session.verify("000000", now: t0)
            #expect(outcome == .rejected(.invalidPairingCode), "attempt \(attempt)")
            #expect(!session.isLockedOut)
        }
        let fifth = session.verify("000000", now: t0)
        #expect(fifth == .rejected(.pairingAttemptsExceeded), "the fifth attempt locks pairing out")
        #expect(session.isLockedOut)
        // Once locked out, even the right code does not get through. No going on guessing.
        let afterLockout = session.verify("123456", now: t0)
        #expect(afterLockout == .rejected(.pairingAttemptsExceeded))
    }
}

@Suite("Authentication (REQ-SEC-001 / 002 / 004 / REQ-PRT-004)")
struct AuthenticatorTests {

    // REQ-SEC-003: a connection with no token, outside pairing mode, is rejected.
    @Test func withoutPairingModeAnUnknownClientIsRejected() {
        var auth = Authenticator()
        let decision = auth.authenticate(hello(), now: t0)
        #expect(decision == .reject(.pairingModeNotActive))
    }

    // REQ-SEC-001: the right code issues a token.
    @Test func correctPairingCodeIssuesAToken() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        guard case let .accept(token) = auth.authenticate(hello(code: "123456"), now: t0) else {
            Issue.record("the correct pairing code was not accepted")
            return
        }
        #expect(token.deviceName == "iPhone")
        #expect(auth.issuedTokens.contains(token))
        #expect(!auth.isPairingActive, "pairing mode closes once a device is paired")
    }

    // REQ-SEC-002: from the second time on, the token authenticates on its own. No user action.
    @Test func knownTokenIsAcceptedWithoutPairing() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        guard case let .accept(token) = auth.authenticate(hello(code: "123456"), now: t0) else {
            Issue.record("the correct pairing code was not accepted")
            return
        }
        var reconnect = Authenticator(issuedTokens: [token])
        #expect(!reconnect.isPairingActive)
        guard case .accept = reconnect.authenticate(hello(token: token.value), now: t0) else {
            Issue.record("the issued token did not get through")
            return
        }
    }

    // REQ-SEC-003: a connection without a valid token is rejected.
    @Test func unknownTokenIsRejected() {
        var auth = Authenticator(issuedTokens: [issued("good")])
        let decision = auth.authenticate(hello(token: "bad"), now: t0)
        #expect(decision == .reject(.unknownDeviceToken))
    }

    // REQ-ERR-006: the failure count carries across the authenticator. Forget to write it back
    // and the attempt limit stops working.
    @Test func failedAttemptsAccumulateAcrossCalls() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        for _ in 1...4 {
            let decision = auth.authenticate(hello(code: "000000"), now: t0)
            #expect(decision == .reject(.invalidPairingCode))
        }
        let locked = auth.authenticate(hello(code: "000000"), now: t0)
        #expect(locked == .reject(.pairingAttemptsExceeded))
        #expect(!auth.isPairingActive, "pairing mode ends when the attempt limit is reached")
    }

    // REQ-SEC-001: **a hello with nothing in it at all, while the window is open.** The iPhone
    // sends one whenever it holds neither a token nor a code (`MdoroClient.sendHello`) — the version
    // is read before the credentials are, so an empty hello is how it finds out whether a version is
    // what is wrong. 10.2 has no word for "no code was sent", so the answer is `invalidPairingCode`,
    // and **the iPhone reads that answer to a codeless hello as "the Mac is waiting for the six"**
    // rather than putting "that code is not correct" in front of a user who has typed nothing.
    //
    // REQ-ERR-006: **and it costs none of the five.** Nothing was verified, so nothing was got
    // wrong. Counted, a user pressing "Try again" six times would close their own pairing window —
    // and be told, correctly by then, to start pairing again.
    @Test func aHelloCarryingNoCodeAtAllIsNotCountedAsAWrongGuess() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)

        for attempt in 1...(PairingSession.maxAttempts + 1) {
            #expect(auth.authenticate(hello(), now: t0) == .reject(.invalidPairingCode), "attempt \(attempt)")
        }
        #expect(auth.pairing?.failedAttempts == 0,
                "REQ-ERR-006: a hello with no code in it spent one of the user's five attempts")
        #expect(auth.isPairingActive,
                "REQ-ERR-006: hellos that carried no code at all closed the pairing window")

        // And the window is the one it was: the code the Mac is showing still gets through.
        guard case .accept = auth.authenticate(hello(code: "123456"), now: t0) else {
            Issue.record("REQ-SEC-001: the right code was refused after hellos that carried none")
            return
        }
    }

    // REQ-SEC-004: with another client already connected, it waits for the user's approval.
    @Test func secondClientNeedsUserApproval() {
        var auth = Authenticator(issuedTokens: [issued("tok")])
        auth.connectedClientName = "iPhone (1台目)"
        let decision = auth.authenticate(hello(token: "tok", name: "iPhone (2台目)"), now: t0)
        #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone (2台目)"))
    }

    // REQ-SEC-004: **a first pairing made while another client is connected.** Nothing
    // is issued while the answer is "ask the user"; the verified hello is held, and the approval
    // issues from it directly.
    @Test func aCodeThatNeedsApprovalIssuesNothingUntilTheUserApproves() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        let first = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
        #expect(first == .needsUserApproval(requestingDeviceName: "iPhone (2)"))
        #expect(auth.issuedTokens.isEmpty, "a token was issued before the user answered")

        guard case let .some(.accept(token)) = auth.resolveApproval(approved: true, now: t0.addingTimeInterval(30)) else {
            Issue.record("the approved pairing was refused — the user's report, exactly")
            return
        }
        #expect(auth.issuedTokens == [token], "exactly one token, issued by the approval alone")
        #expect(token.deviceName == "iPhone (2)")
        #expect(auth.connectedClientName == nil, "the approval chose the new connection over the standing one")
        #expect(!auth.isPairingActive)
    }

    // REQ-SEC-004: the approval settles against the hello held when the question was asked, so
    // the 3-minute window (REQ-SEC-003) expiring while the user decides does not refuse the very
    // hello being approved. The extension this grants is bounded by the 60-second approval
    // timeout, which arrives as a denial.
    @Test func anApprovalLandsAfterThePairingWindowExpires() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        let asked = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
        #expect(asked == .needsUserApproval(requestingDeviceName: "iPhone (2)"))

        // Past the 3-minute window: `verify` would refuse this now, and the countdown outside
        // would have called `endPairing()`. Neither may cancel an approval already verified.
        auth.endPairing()
        let late = t0.addingTimeInterval(PairingSession.validity + 45)
        guard case let .some(.accept(token)) = auth.resolveApproval(approved: true, now: late) else {
            Issue.record("the window expiring turned a pressed Allow into a refusal")
            return
        }
        #expect(auth.issuedTokens == [token])
    }

    // REQ-SEC-004: closing the pairing screen while the approval banner waits (`endPairing`)
    // does not refuse the approval either — same shape as the window expiring.
    @Test func anApprovalLandsAfterPairingWasClosed() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        let asked = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
        #expect(asked == .needsUserApproval(requestingDeviceName: "iPhone (2)"))

        auth.endPairing()
        guard case .some(.accept) = auth.resolveApproval(approved: true, now: t0.addingTimeInterval(10)) else {
            Issue.record("closing the pairing screen turned a pressed Allow into a refusal")
            return
        }
    }

    // REQ-SEC-004: an approval of a reconnecting device that already holds a token hands back
    // the record on file — `issuedAt` does not move, and nothing new is issued.
    @Test func anApprovedReconnectionHandsBackTheRecordOnFile() {
        let record = issued("tok", to: "iPhone (2)", at: t0.addingTimeInterval(-86_400))
        var auth = Authenticator(issuedTokens: [record])
        auth.connectedClientName = "iPhone (1)"

        let asked = auth.authenticate(hello(token: "tok", name: "iPhone (2)"), now: t0)
        #expect(asked == .needsUserApproval(requestingDeviceName: "iPhone (2)"))

        let answer = auth.resolveApproval(approved: true, now: t0)
        #expect(answer == .accept(record), "the record on file, not a fresh one")
        #expect(auth.issuedTokens == [record], "nothing new was issued")
    }

    // REQ-SEC-004: a denial — or the 60-second timeout, which arrives as the same
    // refusal — leaves no token on record, and drops the held hello with it.
    @Test func aDeniedApprovalLeavesNoTokenBehind() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        for attempt in 1...3 {
            let decision = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
            #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone (2)"), "attempt \(attempt)")
        }
        #expect(auth.issuedTokens.isEmpty, "refused attempts piled up tokens — three tries, three orphans")

        let denied = auth.resolveApproval(approved: false, now: t0)
        #expect(denied == .reject(.connectionRejectedByUser))
        #expect(auth.issuedTokens.isEmpty, "a denial issued a token")
        #expect(auth.connectedClientName == "iPhone (1)", "a denial keeps the standing connection")
        #expect(auth.resolveApproval(approved: true, now: t0) == nil,
                "the denied hello was kept, and a later approval could still issue for it")
    }

    // REQ-SEC-002 / Decision 0040 (judgement 4): revocation removes exactly the named record —
    // and with it the record's power to authenticate.
    @Test func revokingRemovesOnlyTheNamedRecord() {
        var auth = Authenticator(issuedTokens: [issued("tok1", to: "A"), issued("tok2", to: "B")])
        auth.revoke(tokenValue: "tok2")
        #expect(auth.issuedTokens == [issued("tok1", to: "A")], "the wrong record was removed, or too many")
        #expect(auth.authenticate(hello(token: "tok2", name: "B"), now: t0) == .reject(.unknownDeviceToken),
                "a revoked token still authenticates")
    }

    // REQ-SEC-004: a token revoked between the question and the answer is refused at the answer —
    // and the refusal does not forget who is connected. Clear `connectedClientName` before the
    // token is looked up and one such refusal is enough: every valid hello after it is accepted
    // without the approval REQ-SEC-004 requires.
    @Test func aTokenRevokedWhileTheQuestionWaitedDoesNotForgetTheStandingConnection() {
        var auth = Authenticator(issuedTokens: [issued("tok1", to: "A"), issued("tok2", to: "B")])
        auth.connectedClientName = "A"

        let asked = auth.authenticate(hello(token: "tok2", name: "B"), now: t0)
        #expect(asked == .needsUserApproval(requestingDeviceName: "B"))

        auth.revoke(tokenValue: "tok2")
        let answer = auth.resolveApproval(approved: true, now: t0)
        #expect(answer == .reject(.unknownDeviceToken))
        #expect(auth.connectedClientName == "A",
                "the refusal forgot the standing connection, which nothing closed")

        // The proof it matters: the next valid hello still has to ask.
        let next = auth.authenticate(hello(token: "tok1", name: "C"), now: t0)
        #expect(next == .needsUserApproval(requestingDeviceName: "C"),
                "REQ-SEC-004: a hello after the refusal was accepted without approval")
    }

    // REQ-SEC-004: an answer with no question waiting settles nothing.
    @Test func anAnswerWithNothingWaitingIsNil() {
        var auth = Authenticator()
        #expect(auth.resolveApproval(approved: true, now: t0) == nil)
    }

    // REQ-PRT-004 / 10.2: an incompatible version has its connection rejected — **and which
    // refusal is sent is the whole of it.** `authFailed.code` has no word for a version, so 10.2
    // carries this reason on `error.code`. Sent as `unknownDeviceToken` it reaches the iPhone as
    // "this device is no longer registered", and the iPhone answers that by deleting the device
    // token it holds: a Mac updated on its own would destroy the pairing it is refusing, then send
    // the user to pair again, which fails the same way for the same reason, for ever.
    //
    // The decision is compared whole: asking only `case .reject` lets the wrong code stand.
    @Test func incompatibleProtocolVersionIsRefusedAsAVersionAndNotAsAnUnknownToken() {
        var auth = Authenticator(issuedTokens: [issued("tok")])
        let decision = auth.authenticate(hello(token: "tok", version: 99), now: t0)

        #expect(decision == .rejectWithProtocolError(.protocolVersionMismatch),
                "REQ-PRT-004: an incompatible version was not refused as one")
        #expect(decision != .reject(.unknownDeviceToken),
                "the iPhone reads this as a revoked pairing and deletes the token it holds")
        #expect(auth.issuedTokens == [issued("tok")], "the refusal took the record with it")
    }

    // REQ-PRT-004: the version is settled before anything the hello carried as credentials, so
    // the answer cannot come back as a problem with those instead — whichever of them was sent.
    // Refused as a pairing problem, the user is sent to a pairing screen that cannot help.
    @Test func theVersionIsTheAnswerWhateverElseTheHelloCarried() {
        let samples = [
            hello(version: 99),
            hello(token: "tok", version: 99),
            hello(token: "unknown", version: 99),
            hello(code: "123456", version: 99),
            hello(code: "000000", version: 99),
        ]
        for sample in samples {
            var auth = Authenticator(issuedTokens: [issued("tok")])
            auth.beginPairing(code: "123456", now: t0)
            #expect(auth.authenticate(sample, now: t0) == .rejectWithProtocolError(.protocolVersionMismatch),
                    "a hello refused for its credentials rather than for its version")
            // REQ-ERR-006: nor does a version mismatch spend one of the five pairing attempts.
            #expect(auth.isPairingActive, "the pairing window closed over a version number")
        }
    }

    // REQ-PRT-004: a version this Mac does speak is not refused here at all — the guard reads
    // the version, not the presence of one.
    @Test func theCurrentVersionPassesTheVersionGuard() {
        var auth = Authenticator(issuedTokens: [issued("tok")])
        let decision = auth.authenticate(hello(token: "tok", version: PomodoroProtocol.version), now: t0)
        #expect(decision == .accept(issued("tok")))
    }
}

// REQ-PRT-004 / 10.2: the vocabulary the refusal is spoken in.
//
// REQ-PRT-004 says to refuse and to tell both ends to update, but not which message says so. 10.2
// does, and nothing in the implementation itself holds it there. These are that anchor.
@Suite("A version the Mac cannot speak to (REQ-PRT-004 / 10.2)")
struct ProtocolRefusalTests {

    // 10.2 lists five `authFailed.code` values and not one of them is about a version. **That
    // absence is the reason this refusal leaves by `error`** — so it is written down here, where
    // a sixth `authFailed` code quietly becoming the answer would be caught.
    @Test func authFailedHasNoWordForAVersion() {
        #expect(AuthFailureCode.allCases.count == 5)
        let mentionsAVersion = AuthFailureCode.allCases.contains { $0.rawValue.lowercased().contains("version") }
        #expect(!mentionsAVersion, "10.2: `authFailed.code` gained a word for a version")
        #expect(ProtocolErrorCode.allCases.contains(.protocolVersionMismatch),
                "10.2: `error.code` is where the version mismatch lives")
    }

    // 10.2: and this is the code it goes out under — the one value every version's catalogue
    // already holds, so no end has to decode a code its age keeps it from knowing (REQ-PRT-005).
    @Test func itLeavesUnderTheCode10Point2AssignsIt() {
        #expect(ProtocolRefusal.protocolVersionMismatch.protocolErrorCode == .protocolVersionMismatch)
        #expect(ProtocolRefusal.allCases.count == 1, "a second reason needs its own line in 10.2 first")
    }

    // REQ-ERR-010 / Decision 0034: it is still a refused connection, so it is written
    // into the diagnostic log like every other failure of ours — `case(domain:code)`, in our own
    // domain, out of the block of numbers this enum owns.
    @Test func everyProtocolRefusalIsWrittenLikeAnyOtherFailure() {
        var seen = Set<String>()
        for refusal in ProtocolRefusal.allCases {
            #expect(refusal.errorCode.domain == ErrorCode.ownDomain)
            #expect((70...79).contains(refusal.errorCode.code), "Decision 0034: 70–79 belong to this enum")
            #expect(refusal.diagnosticSummary == "\(refusal.rawValue)(\(refusal.errorCode))")
            // Decision 0018 rewrites whitespace in a field; there must be none to rewrite.
            #expect(DiagnosticField("why", refusal.diagnosticSummary).value == refusal.diagnosticSummary)
            #expect(seen.insert(refusal.diagnosticSummary).inserted)
        }
    }

    // **A refusal is recorded before it leaves, on every path.** No clause asks for that record —
    // the reader Decision 0018 wrote the log for is the whole of why it is written, and
    // `MdoroServer` says so beside `refuse`. The Mac target is not reachable from here, so the
    // wiring is read: every case `settle` answers must go through a `refuse` that records, not
    // straight to the wire.
    @Test func theServerRecordsThisRefusalBeforeSendingIt() throws {
        let serverPath = "PomodoroMac/PomodoroMac/Server/MdoroServer.swift"
        let server = withoutComments(try source(serverPath))

        // Two `refuse`s now, one per message 10.2 carries a reason in — and each records first.
        // Through `afterEachAnchor`: a renamed anchor leaves nothing to loop over, and the count
        // below would then read as a refusal having been deleted (see `MissingAnchor`).
        let refusals = try afterEachAnchor("private func refuse(", in: server, of: serverPath)
        #expect(refusals.count == 2, "10.2: one refusal for `authFailed`, one for `error`")
        for refusal in refusals {
            // The body, not a count of characters: see `bracedBody`.
            let body = try bracedBody(openedBy: refusal, "private func refuse(")
            let recorded = try #require(body.range(of: "record(refusal:"), "a refusal that leaves no line")
            let sent = try #require(body.range(of: "sendThenClose("), "a refusal that is recorded but never sent")
            #expect(recorded.upperBound < sent.lowerBound, "the line is written after the refusal is sent")
        }
        // 10.2 / REQ-PRT-004: and the one on `error` carries the code the refusal itself names,
        // rather than one written out here — the enum is what keeps it to a value every version knows.
        #expect(server.contains("ProtocolErrorPayload(code: reason.protocolErrorCode"),
                "REQ-PRT-004: the version refusal does not go out on `error`")
    }
}

@Suite("Command translation (10.2 / REQ-PRT-003)")
struct CommandTranslationTests {

    private func translate(_ action: CommandAction, _ params: CommandParams? = nil) -> Result<TimerAction, CommandTranslation.Failure> {
        CommandTranslation.action(
            for: CommandPayload(action: action, params: params),
            activePresetId: "p", selectedTaskSnapshot: "タスク"
        )
    }

    // 10.2: startBreak requires its sessionType. It cannot be left out.
    @Test func startBreakRequiresItsSessionType() {
        #expect(translate(.startBreak) == .failure(.missingParameter(.sessionType)))
        #expect(translate(.startBreak, CommandParams(sessionType: .work)) == .failure(.invalidParameter(.sessionType)))
        #expect(translate(.startBreak, CommandParams(sessionType: .longBreak))
                == .success(.startBreak(type: .longBreak, presetId: "p")))
    }

    // 10.2: `resume` on the wire corresponds to `continueSession` inside.
    @Test func confirmDecisionMapsResumeToContinueSession() {
        #expect(translate(.confirmRestoredSession, CommandParams(decision: .resume))
                == .success(.confirmRestoredSession(.continueSession)))
        #expect(translate(.confirmRestoredSession, CommandParams(decision: .complete))
                == .success(.confirmRestoredSession(.complete)))
        #expect(translate(.confirmRestoredSession) == .failure(.missingParameter(.decision)))
    }

    @Test func startWorkCarriesTheCurrentSelection() {
        #expect(translate(.startWork) == .success(.startWork(presetId: "p", taskSnapshot: "タスク")))
    }

    @Test func presetCommandsRequireTheirIdentifiers() {
        #expect(translate(.selectPreset) == .failure(.missingParameter(.presetId)))
        #expect(translate(.deletePreset) == .failure(.missingParameter(.presetId)))
        #expect(translate(.reorderPresets) == .failure(.missingParameter(.orderedIds)))
        #expect(translate(.createPreset) == .failure(.missingParameter(.preset)))
    }

    @Test func parameterlessCommandsTranslateDirectly() {
        #expect(translate(.pause) == .success(.pause))
        #expect(translate(.resume) == .success(.resume))
        #expect(translate(.skip) == .success(.skip))
        #expect(translate(.abort) == .success(.abort))
        #expect(translate(.extend) == .success(.extend))
        #expect(translate(.resetLoopCount) == .success(.resetLoopCount))
        #expect(translate(.restoreDefaultPreset) == .success(.restoreDefaultPreset))
    }

    // REQ-PRT-003: a resend carrying the same clientRequestId is ignored.
    // Without idempotence, a resend right after reconnecting applies the extension twice.
    @Test func repeatedRequestIdsAreProcessedOnlyOnce() {
        var dedup = RequestDeduplicator()
        let first = dedup.shouldProcess("r1")
        let repeated = dedup.shouldProcess("r1")
        let other = dedup.shouldProcess("r2")
        let repeatedAgain = dedup.shouldProcess("r1")
        #expect(first)
        #expect(!repeated)
        #expect(other)
        #expect(!repeatedAgain)
    }

    @Test func deduplicatorForgetsTheOldestBeyondCapacity() {
        var dedup = RequestDeduplicator(capacity: 3)
        for id in ["a", "b", "c"] {
            let accepted = dedup.shouldProcess(id)
            #expect(accepted)
        }
        let stillRemembered = dedup.shouldProcess("a")
        #expect(!stillRemembered)
        let fourth = dedup.shouldProcess("d")
        #expect(fourth, "the oldest id is forgotten once capacity is exceeded")
        let forgotten = dedup.shouldProcess("a")
        #expect(forgotten, "a forgotten id is processed again")
    }
}
