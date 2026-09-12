import Foundation

// REQ-SEC-001 / 003 / REQ-ERR-006 / 3.2: pairing and authentication.
// "One Mac, one iPhone" does not hold while any device on the LAN can connect.
public struct PairingSession: Equatable, Sendable {
    // REQ-SEC-003: pairing mode runs only when it was started deliberately, and only for three minutes.
    public static let validity: TimeInterval = 3 * 60
    // REQ-ERR-006: five wrong codes in a row end pairing mode.
    public static let maxAttempts = 5

    public let code: String
    public let startedAt: Date
    public private(set) var failedAttempts = 0

    public init(code: String, startedAt: Date) {
        self.code = code
        self.startedAt = startedAt
    }

    // Six digits can be brute-forced, so the guard is both the validity window and the attempt count.
    public static func generateCode(using generator: () -> Int = { Int.random(in: 0...999_999) }) -> String {
        String(format: "%06d", generator() % 1_000_000)
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(startedAt) > Self.validity
    }

    public var isLockedOut: Bool { failedAttempts >= Self.maxAttempts }

    public func remainingSeconds(now: Date) -> Int {
        max(0, Int((Self.validity - now.timeIntervalSince(startedAt)).rounded(.up)))
    }

    public enum Outcome: Equatable, Sendable {
        case accepted
        case rejected(AuthFailureCode)
    }

    // This struct is what counts the failures.
    public mutating func verify(_ candidate: String, now: Date) -> Outcome {
        if isLockedOut { return .rejected(.pairingAttemptsExceeded) }
        if isExpired(now: now) { return .rejected(.pairingModeNotActive) }

        guard candidate == code else {
            failedAttempts += 1
            // The fifth attempt is the last; after it the reason given changes.
            return .rejected(isLockedOut ? .pairingAttemptsExceeded : .invalidPairingCode)
        }
        return .accepted
    }
}

// REQ-SEC-002 / Decision 0040: from the second time on, a device token authenticates on its own,
// with nothing for the user to do.
//
// **All three fields are kept, and the Mac keeps them.** It used to hold a `Set<String>` of
// values, so the name and the date were thrown away at the moment of saving — which is why there
// was no revocation screen to build: nothing was left to put on it. "There is no way to revoke"
// was really "the thing to revoke cannot be identified, because we discarded what identified it".
public struct DeviceToken: Equatable, Sendable, Codable, Hashable {
    public let value: String
    public let deviceName: String
    public let issuedAt: Date

    public init(value: String = DeviceToken.generate(), deviceName: String, issuedAt: Date = Date()) {
        self.value = value
        self.deviceName = deviceName
        self.issuedAt = issuedAt
    }

    public static func generate() -> String {
        // Nothing expires here, so the length is what makes it unguessable.
        (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined().prefix(64).description
    }
}

// Whether a connection is accepted is decided here alone; the transport layer only follows the answer.
public struct Authenticator: Equatable, Sendable {
    // Decision 0040: records, not values. **A token cannot be held here without saying whose it
    // is and when it was handed out** — the revocation screen (9.x) reads exactly this.
    public private(set) var issuedTokens: [DeviceToken] = []
    public private(set) var pairing: PairingSession?
    // REQ-SEC-004: whether another client is already connected.
    public var connectedClientName: String?
    // REQ-SEC-004: the hello that answered `.needsUserApproval`, held verified until the user
    // decides. `resolveApproval` settles it; a hello left behind by a server teardown is inert,
    // because nothing but `resolveApproval` reads it and only an approval in flight calls that.
    public private(set) var awaitingApproval: HelloPayload?

    public init(issuedTokens: [DeviceToken] = [], pairing: PairingSession? = nil) {
        self.issuedTokens = issuedTokens
        self.pairing = pairing
    }

    public mutating func beginPairing(code: String, now: Date) {
        pairing = PairingSession(code: code, startedAt: now)
    }

    public mutating func endPairing() {
        pairing = nil
    }

    // REQ-SEC-002 / Decision 0040 (judgement 4): revocation removes the record, and with it the
    // only thing that lets the value authenticate again. Nothing else is touched on purpose — a
    // hello held for approval keeps its copy, and `resolveApproval` re-reads this list, so a
    // token revoked between the question and the answer is refused at the answer.
    public mutating func revoke(tokenValue: String) {
        issuedTokens.removeAll { $0.value == tokenValue }
    }

    public var isPairingActive: Bool { pairing != nil }

    public enum Decision: Equatable, Sendable {
        case accept(DeviceToken)
        // REQ-SEC-004: with a connection already open, wait for the user to approve.
        case needsUserApproval(requestingDeviceName: String)
        case reject(AuthFailureCode)
        // REQ-PRT-004 / 10.2: refused, with the reason travelling on `error` rather than on
        // `authFailed` — see `ProtocolRefusal`. A case of its own rather than a sixth
        // `AuthFailureCode`, because 10.2 puts this reason in a different message: adding a word
        // to `authFailed.code` would be changing the protocol instead of following it, and the
        // iPhone reads the five it has today as things to do about a pairing.
        case rejectWithProtocolError(ProtocolRefusal)
    }

    public mutating func authenticate(_ hello: HelloPayload, now: Date) -> Decision {
        // REQ-PRT-004 / 10.2: an incompatible version is refused — and told so. This is looked
        // at before anything the hello carried as credentials, so the answer does not depend on
        // them; what the answer must not be is one of those credentials' own refusals.
        // `unknownDeviceToken` stood here, and the iPhone acts on it by deleting the device
        // token it holds, so a Mac updated on its own did not just mislead the user into pairing
        // again — it destroyed the pairing it was refusing, for a reason pairing cannot mend.
        guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {
            return .rejectWithProtocolError(.protocolVersionMismatch)
        }

        // REQ-SEC-002: a token we issued goes straight through.
        if let token = hello.deviceToken {
            // **The record on file is handed back, not a fresh one built from this hello.**
            // `issuedAt` means when it was issued; rebuilding it here would move that date
            // forward on every reconnect and leave the revocation screen showing today for a
            // pairing made in March.
            guard let issued = issuedTokens.first(where: { $0.value == token }) else {
                return .reject(.unknownDeviceToken)
            }
            if connectedClientName != nil {
                awaitingApproval = hello
                return .needsUserApproval(requestingDeviceName: hello.deviceName)
            }
            return .accept(issued)
        }

        // REQ-SEC-001 / 003: without a token, a pairing code is required.
        guard var session = pairing else { return .reject(.pairingModeNotActive) }
        guard let code = hello.pairingCode else {
            pairing = session
            return .reject(.invalidPairingCode)
        }

        let outcome = session.verify(code, now: now)
        // **Write the failure count back.** Forget it and the attempt limit does nothing.
        pairing = session.isLockedOut ? nil : session

        switch outcome {
        case .accepted:
            // POL-139 / REQ-SEC-004: **nothing is issued and nothing is closed while the answer
            // is "ask the user".** This used to append the token and end pairing before returning,
            // so the re-authentication that follows an approval found pairing over and refused the
            // very hello it was approving — and every refused attempt left one orphaned token
            // behind. The verified hello is held instead, and `resolveApproval` issues from it —
            // a denial (or the 60-second timeout) issues nothing, because nothing was issued yet.
            if connectedClientName != nil {
                awaitingApproval = hello
                return .needsUserApproval(requestingDeviceName: hello.deviceName)
            }
            let token = DeviceToken(deviceName: hello.deviceName, issuedAt: now)
            issuedTokens.append(token)
            pairing = nil
            return .accept(token)
        case let .rejected(code):
            return .reject(code)
        }
    }

    // REQ-SEC-004: the user's answer to `.needsUserApproval`, settled against the hello held at
    // the moment the question was asked — **not by re-running authentication**. The pairing window
    // may have expired (REQ-SEC-003) or been closed while the user was deciding, and neither
    // cancels an approval of a code that already verified; re-authenticating here is what used to
    // turn a pressed "Allow" into "Start pairing on your Mac". Issuing from the held hello also
    // pins the answer to the request the user actually saw, not to whatever occupies the pending
    // slot by the time the click lands.
    //
    // REQ-SEC-003: holding the verified hello lets an approval land after the 3-minute window —
    // by at most the 60 seconds the approval itself is allowed to wait (REQ-SEC-004), since a
    // timeout arrives here as a denial. That bounded extension is accepted.
    public mutating func resolveApproval(approved: Bool, now: Date) -> Decision? {
        guard let hello = awaitingApproval else { return nil }
        awaitingApproval = nil
        guard approved else { return .reject(.connectionRejectedByUser) }

        // A reconnecting device that already holds a token: the record on file is handed back,
        // for the same reason `authenticate` hands it back — `issuedAt` must not move.
        if let token = hello.deviceToken {
            guard let issued = issuedTokens.first(where: { $0.value == token }) else {
                // POL-146 / REQ-SEC-004: the token was revoked between the question and the
                // answer. The standing connection is still standing — nothing here closed it —
                // so it is not forgotten. Clearing `connectedClientName` before this lookup is
                // what let the next valid hello be accepted without the approval REQ-SEC-004
                // requires.
                return .reject(.unknownDeviceToken)
            }
            // The approval chose the new connection over the standing one (REQ-SEC-004) —
            // recorded only once the answer is actually an accept.
            connectedClientName = nil
            return .accept(issued)
        }

        // A first pairing: the code verified before the question was asked, so approval is the
        // last thing between it and a token.
        connectedClientName = nil
        let token = DeviceToken(deviceName: hello.deviceName, issuedAt: now)
        issuedTokens.append(token)
        pairing = nil
        return .accept(token)
    }
}
