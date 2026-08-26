import Foundation

// REQ-SEC-001 / 003 / REQ-ERR-006: ペアリングと認証。
//
// 「Mac 1台対 iPhone 1台」を原則に掲げる以上、LAN 内の任意の端末から
// 接続・操作できる状態ではその原則が担保されない（3.2 背景・理由）。
public struct PairingSession: Equatable, Sendable {
    // REQ-SEC-003: ペアリングモードは明示的に開始したときのみ、かつ3分間のみ有効。
    public static let validity: TimeInterval = 3 * 60
    // REQ-ERR-006: 5回連続で誤ったらペアリングモードを終了する。
    public static let maxAttempts = 5

    public let code: String
    public let startedAt: Date
    public private(set) var failedAttempts = 0

    public init(code: String, startedAt: Date) {
        self.code = code
        self.startedAt = startedAt
    }

    // 6桁。総当たりが現実的でない長さではないので、有効期間と試行回数の両方で守る。
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

    // 入力されたコードを照合する。失敗回数はこの構造体が数える。
    public mutating func verify(_ candidate: String, now: Date) -> Outcome {
        if isLockedOut { return .rejected(.pairingAttemptsExceeded) }
        if isExpired(now: now) { return .rejected(.pairingModeNotActive) }

        guard candidate == code else {
            failedAttempts += 1
            // 5回目で打ち止め。以降は理由を変えて、コードの当てずっぽうを続けさせない。
            return .rejected(isLockedOut ? .pairingAttemptsExceeded : .invalidPairingCode)
        }
        return .accepted
    }
}

// REQ-SEC-002: 2回目以降はデバイストークンで自動認証し、ユーザー操作を不要にする。
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
        // 推測できない長さにする。ペアリングコードと違い、有効期限で守らないため。
        (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined().prefix(64).description
    }
}

// サーバー側の認証判断。接続の受理可否をここに集約し、通信層は結果に従うだけにする。
public struct Authenticator: Equatable, Sendable {
    public private(set) var issuedTokens: Set<String> = []
    public private(set) var pairing: PairingSession?
    // REQ-SEC-004: 既に別のクライアントが接続中か。
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
        // REQ-SEC-004: 既存接続があるときは、ユーザーの承認を待つ。
        case needsUserApproval(requestingDeviceName: String)
        case reject(AuthFailureCode)
    }

    public mutating func authenticate(_ hello: HelloPayload, now: Date) -> Decision {
        // REQ-PRT-004: 非互換なら接続を拒否する。
        guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {
            return .reject(.unknownDeviceToken)
        }

        // REQ-SEC-002: 既知のトークンならそのまま通す。
        if let token = hello.deviceToken {
            guard issuedTokens.contains(token) else { return .reject(.unknownDeviceToken) }
            if connectedClientName != nil {
                return .needsUserApproval(requestingDeviceName: hello.deviceName)
            }
            return .accept(DeviceToken(value: token, deviceName: hello.deviceName, issuedAt: now))
        }

        // REQ-SEC-001 / 003: トークンが無いならペアリングコードが要る。
        guard var session = pairing else { return .reject(.pairingModeNotActive) }
        guard let code = hello.pairingCode else {
            pairing = session
            return .reject(.invalidPairingCode)
        }

        let outcome = session.verify(code, now: now)
        // 失敗回数を持ち帰る。ここを書き戻し忘れると回数制限が効かない。
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
