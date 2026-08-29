import Testing
import Foundation
@testable import MdoroCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func hello(token: String? = nil, code: String? = nil, name: String = "iPhone",
                   version: Int = PomodoroProtocol.version) -> HelloPayload {
    HelloPayload(protocolVersion: version, deviceToken: token, pairingCode: code, deviceName: name)
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
        #expect(auth.issuedTokens.contains(token.value))
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
        var reconnect = Authenticator(issuedTokens: [token.value])
        #expect(!reconnect.isPairingActive)
        guard case .accept = reconnect.authenticate(hello(token: token.value), now: t0) else {
            Issue.record("the issued token did not get through")
            return
        }
    }

    // REQ-SEC-003: a connection without a valid token is rejected.
    @Test func unknownTokenIsRejected() {
        var auth = Authenticator(issuedTokens: ["good"])
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
        var auth = Authenticator(issuedTokens: ["tok"])
        auth.connectedClientName = "iPhone (1台目)"
        let decision = auth.authenticate(hello(token: "tok", name: "iPhone (2台目)"), now: t0)
        #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone (2台目)"))
    }

    // REQ-PRT-004: an incompatible version has its connection rejected.
    @Test func incompatibleProtocolVersionIsRejected() {
        var auth = Authenticator(issuedTokens: ["tok"])
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
