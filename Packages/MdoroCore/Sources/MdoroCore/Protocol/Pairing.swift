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

// REQ-SEC-002: from the second time on, a device token authenticates on its own, with nothing for the user to do.
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
    public private(set) var issuedTokens: Set<String> = []
    public private(set) var pairing: PairingSession?
    // REQ-SEC-004: whether another client is already connected.
    public var connectedClientName: String?

    public init(issuedTokens: Set<String> = [], pairing: PairingSession? = nil) {
        self.issuedTokens = issuedTokens
        self.pairing = pairing
    }

    public mutating func beginPairing(code: String, now: Date) {
        pairing = PairingSession(code: code, startedAt: now)
    }

    public mutating func endPairing() {
        pairing = nil
    }

    public var isPairingActive: Bool { pairing != nil }

    public enum Decision: Equatable, Sendable {
        case accept(DeviceToken)
        // REQ-SEC-004: with a connection already open, wait for the user to approve.
        case needsUserApproval(requestingDeviceName: String)
        case reject(AuthFailureCode)
    }

    public mutating func authenticate(_ hello: HelloPayload, now: Date) -> Decision {
        // REQ-PRT-004: an incompatible version is refused.
        guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {
            return .reject(.unknownDeviceToken)
        }

        // REQ-SEC-002: a token we issued goes straight through.
        if let token = hello.deviceToken {
            guard issuedTokens.contains(token) else { return .reject(.unknownDeviceToken) }
            if connectedClientName != nil {
                return .needsUserApproval(requestingDeviceName: hello.deviceName)
            }
            return .accept(DeviceToken(value: token, deviceName: hello.deviceName, issuedAt: now))
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
            let token = DeviceToken(deviceName: hello.deviceName, issuedAt: now)
            issuedTokens.insert(token.value)
            pairing = nil
            if connectedClientName != nil {
                return .needsUserApproval(requestingDeviceName: hello.deviceName)
            }
            return .accept(token)
        case let .rejected(code):
            return .reject(code)
        }
    }
}
