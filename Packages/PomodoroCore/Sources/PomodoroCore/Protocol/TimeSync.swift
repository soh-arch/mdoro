import Foundation

// REQ-COM-007 / 008 / 009: 端末間の時計オフセットを NTP 方式で測る。
//
// 絶対時刻同期がこの設計の根幹である以上（3原則の3つ目）、Mac と iPhone の時計差を
// 補正しないと「終了絶対時刻」という基準そのものが端末間でずれる。
public struct TimeSyncSample: Equatable, Sendable {
    public let offset: TimeInterval
    public let roundTrip: TimeInterval

    // REQ-COM-008: offset = ((t2 − t1) + (t3 − t4)) / 2、往復遅延 = (t4 − t1) − (t3 − t2)
    public init(t1: Date, t2: Date, t3: Date, t4: Date) {
        offset = ((t2.timeIntervalSince(t1)) + (t3.timeIntervalSince(t4))) / 2
        roundTrip = (t4.timeIntervalSince(t1)) - (t3.timeIntervalSince(t2))
    }

    public init(offset: TimeInterval, roundTrip: TimeInterval) {
        self.offset = offset
        self.roundTrip = roundTrip
    }
}

public struct TimeSyncEstimator: Equatable, Sendable {
    // REQ-COM-008: 往復遅延が 500ms を超えるサンプルは棄却する。
    public static let maxRoundTrip: TimeInterval = 0.5
    // 棄却後の直近 7 サンプルの中央値を採る。
    public static let windowSize = 7
    // 有効サンプルが 3 件未満の間は、最小往復遅延のサンプルをそのまま用いる。
    public static let minimumSamplesForMedian = 3
    // REQ-ERR-007: 5 秒を超えるオフセットは警告する。
    public static let warningThreshold: TimeInterval = 5

    private var accepted: [TimeSyncSample] = []

    public init() {}

    public var sampleCount: Int { accepted.count }

    public mutating func add(_ sample: TimeSyncSample) {
        // 遅延の大きいサンプルは、オフセットの推定を素直に狂わせる。
        guard sample.roundTrip <= Self.maxRoundTrip else { return }
        accepted.append(sample)
        if accepted.count > Self.windowSize {
            accepted.removeFirst(accepted.count - Self.windowSize)
        }
    }

    public var offset: TimeInterval {
        guard !accepted.isEmpty else { return 0 }
        guard accepted.count >= Self.minimumSamplesForMedian else {
            // まだ数が揃わないうちは、いちばん速く返ってきたものが最も信用できる。
            return accepted.min { $0.roundTrip < $1.roundTrip }?.offset ?? 0
        }
        let sorted = accepted.map(\.offset).sorted()
        return sorted[sorted.count / 2]
    }

    public var roundTrip: TimeInterval {
        accepted.min { $0.roundTrip < $1.roundTrip }?.roundTrip ?? 0
    }

    // REQ-ERR-007: 時計が大きくずれている場合は、補正で押し込めずユーザーに知らせる。
    public var needsClockWarning: Bool {
        abs(offset) > Self.warningThreshold
    }

    // REQ-COM-009: 受信した sessionEndAt（サーバー時刻）を自端末の時計へ直す。
    public func localTime(forServerTime serverTime: Date) -> Date {
        serverTime.addingTimeInterval(-offset)
    }
}

// REQ-COM-004: 一時的なネットワーク遮断は指数バックオフで再接続する（初回1秒、上限30秒）。
public struct ReconnectPolicy: Equatable, Sendable {
    public static let initialDelay: TimeInterval = 1
    public static let maximumDelay: TimeInterval = 30

    private var attempt = 0

    public init() {}

    public var currentAttempt: Int { attempt }

    public mutating func nextDelay() -> TimeInterval {
        let delay = min(Self.initialDelay * pow(2, Double(attempt)), Self.maximumDelay)
        attempt += 1
        return delay
    }

    // 接続に成功したら振り出しに戻す。戻し忘れると、一度荒れた回線が延々と30秒待ちになる。
    public mutating func reset() {
        attempt = 0
    }
}

// REQ-COM-005: 5秒間隔でハートビートを送受信し、15秒応答がなければ接続断とみなす。
public enum Heartbeat {
    public static let interval: TimeInterval = 5
    public static let timeout: TimeInterval = 15

    public static func isStale(lastReceivedAt: Date?, now: Date) -> Bool {
        guard let lastReceivedAt else { return true }
        return now.timeIntervalSince(lastReceivedAt) > timeout
    }
}
