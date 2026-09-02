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

    // REQ-SEC-004: with another client already connected, it waits for the user's approval.
    @Test func secondClientNeedsUserApproval() {
        var auth = Authenticator(issuedTokens: [issued("tok")])
        auth.connectedClientName = "iPhone (1台目)"
        let decision = auth.authenticate(hello(token: "tok", name: "iPhone (2台目)"), now: t0)
        #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone (2台目)"))
    }

    // POL-139 / REQ-SEC-004: **a first pairing made while another client is connected.** Nothing
    // is issued while the answer is "ask the user"; the verified hello is held, and the approval
    // issues from it directly.
    @Test func aCodeThatNeedsApprovalIssuesNothingUntilTheUserApproves() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        let first = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
        #expect(first == .needsUserApproval(requestingDeviceName: "iPhone (2)"))
        #expect(auth.issuedTokens.isEmpty, "POL-139: a token was issued before the user answered")

        guard case let .some(.accept(token)) = auth.resolveApproval(approved: true, now: t0.addingTimeInterval(30)) else {
            Issue.record("POL-139: the approved pairing was refused — the user's report, exactly")
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

    // POL-139 / REQ-SEC-004: a denial — or the 60-second timeout, which arrives as the same
    // refusal — leaves no token on record, and drops the held hello with it.
    @Test func aDeniedApprovalLeavesNoTokenBehind() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        auth.connectedClientName = "iPhone (1)"

        for attempt in 1...3 {
            let decision = auth.authenticate(hello(code: "123456", name: "iPhone (2)"), now: t0)
            #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone (2)"), "attempt \(attempt)")
        }
        #expect(auth.issuedTokens.isEmpty, "POL-139: refused attempts piled up tokens — three tries, three orphans")

        let denied = auth.resolveApproval(approved: false, now: t0)
        #expect(denied == .reject(.connectionRejectedByUser))
        #expect(auth.issuedTokens.isEmpty, "a denial issued a token")
        #expect(auth.connectedClientName == "iPhone (1)", "a denial keeps the standing connection")
        #expect(auth.resolveApproval(approved: true, now: t0) == nil,
                "the denied hello was kept, and a later approval could still issue for it")
    }

    // REQ-SEC-004: an answer with no question waiting settles nothing.
    @Test func anAnswerWithNothingWaitingIsNil() {
        var auth = Authenticator()
        #expect(auth.resolveApproval(approved: true, now: t0) == nil)
    }

    // REQ-PRT-004: an incompatible version has its connection rejected.
    @Test func incompatibleProtocolVersionIsRejected() {
        var auth = Authenticator(issuedTokens: [issued("tok")])
        guard case .reject = auth.authenticate(hello(token: "tok", version: 99), now: t0) else {
            Issue.record("an incompatible version was not rejected")
            return
        }
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
