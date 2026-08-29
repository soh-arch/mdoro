import Foundation

// REQ-COM-007 / 008 / 009: the clock offset between the devices, measured the NTP way.
// Without the correction the absolute end time — the basis itself — differs between the two
// devices (the third principle).
public struct TimeSyncSample: Equatable, Sendable {
    public let offset: TimeInterval
    public let roundTrip: TimeInterval

    // REQ-COM-008: offset = ((t2 − t1) + (t3 − t4)) / 2, round trip = (t4 − t1) − (t3 − t2)
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
    // REQ-COM-008: a sample whose round trip exceeds 500ms is discarded.
    public static let maxRoundTrip: TimeInterval = 0.5
    // The median of the last seven samples that were kept.
    public static let windowSize = 7
    // While fewer than three samples have been kept, the one with the shortest round trip is used as it is.
    public static let minimumSamplesForMedian = 3
    // REQ-ERR-007: an offset beyond five seconds raises a warning.
    public static let warningThreshold: TimeInterval = 5

    private var accepted: [TimeSyncSample] = []

    public init() {}

    public var sampleCount: Int { accepted.count }

    public mutating func add(_ sample: TimeSyncSample) {
        // A sample with a long delay throws the offset estimate off.
        guard sample.roundTrip <= Self.maxRoundTrip else { return }
        accepted.append(sample)
        if accepted.count > Self.windowSize {
            accepted.removeFirst(accepted.count - Self.windowSize)
        }
    }

    public var offset: TimeInterval {
        guard !accepted.isEmpty else { return 0 }
        guard accepted.count >= Self.minimumSamplesForMedian else {
            // Until there are enough of them, use the one that came back fastest.
            return accepted.min { $0.roundTrip < $1.roundTrip }?.offset ?? 0
        }
        let sorted = accepted.map(\.offset).sorted()
        return sorted[sorted.count / 2]
    }

    public var roundTrip: TimeInterval {
        accepted.min { $0.roundTrip < $1.roundTrip }?.roundTrip ?? 0
    }

    // REQ-ERR-007: a badly wrong clock is told to the user, not quietly absorbed by the correction.
    public var needsClockWarning: Bool {
        abs(offset) > Self.warningThreshold
    }

    // REQ-COM-009: convert the sessionEndAt received, which is in server time, to this device's clock.
    public func localTime(forServerTime serverTime: Date) -> Date {
        serverTime.addingTimeInterval(-offset)
    }
}

// REQ-COM-004: a brief network cut is reconnected with exponential backoff (one second first, thirty at most).
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

    // **Back to the start once a connection succeeds.** Forget it and a line that was rough once waits thirty seconds for ever.
    public mutating func reset() {
        attempt = 0
    }
}

// REQ-COM-005: heartbeats go both ways every five seconds; fifteen seconds of silence counts as disconnected.
public enum Heartbeat {
    public static let interval: TimeInterval = 5
    public static let timeout: TimeInterval = 15

    public static func isStale(lastReceivedAt: Date?, now: Date) -> Bool {
        guard let lastReceivedAt else { return true }
        return now.timeIntervalSince(lastReceivedAt) > timeout
    }
}
