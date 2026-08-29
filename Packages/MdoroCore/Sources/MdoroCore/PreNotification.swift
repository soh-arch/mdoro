import Foundation

// REQ-NTF-020: a pre-notification trigger. Zero to two per preset (10.3 PreNotification).
public enum PreNotification: Equatable, Sendable, Hashable {
    // n seconds before the end (60 to 900, a multiple of 60)
    case beforeEnd(seconds: Int)
    // at n% of the session elapsed (50 to 95, a multiple of 5)
    case atElapsedPercent(Int)

    public static let beforeEndRange = 60...(15 * 60)
    public static let elapsedPercentRange = 50...95

    // REQ-CFG-018: the check that keeps an out-of-range value arriving over the protocol from being applied.
    public var isWithinValidRanges: Bool {
        switch self {
        case let .beforeEnd(seconds):
            return Self.beforeEndRange.contains(seconds) && seconds % 60 == 0
        case let .atElapsedPercent(percent):
            return Self.elapsedPercentRange.contains(percent) && percent % 5 == 0
        }
    }

    // REQ-NTF-020 / 022: the percentage is of the session length, so after an extension it follows the longer one.
    public func fireDate(sessionStartedAt: Date, sessionEndAt: Date) -> Date {
        switch self {
        case let .beforeEnd(seconds):
            return sessionEndAt.addingTimeInterval(-TimeInterval(seconds))
        case let .atElapsedPercent(percent):
            let duration = sessionEndAt.timeIntervalSince(sessionStartedAt)
            return sessionStartedAt.addingTimeInterval(duration * Double(percent) / 100)
        }
    }
}

// REQ-PRT-001: deciding the fire times lives in shared code, so both devices reach the same answer.
public enum PreNotificationSchedule {
    // How close two triggers have to be to count as adjacent (REQ-NTF-023).
    public static let minimumSpacingSeconds: TimeInterval = 60

    /// The fire times to schedule, in ascending order.
    ///
    /// - REQ-NTF-021: a trigger that would fire at or before the session start is dropped.
    /// - REQ-NTF-022: a trigger already past `now` is dropped, so rescheduling after an extension does not fire it again.
    /// - REQ-NTF-023: when two fire times fall within 60 seconds of each other, only the later one is kept.
    public static func fireDates(
        for triggers: [PreNotification],
        sessionStartedAt: Date,
        sessionEndAt: Date,
        now: Date
    ) -> [Date] {
        guard sessionEndAt > sessionStartedAt else { return [] }

        let candidates = triggers
            .map { $0.fireDate(sessionStartedAt: sessionStartedAt, sessionEndAt: sessionEndAt) }
            .filter { $0 > sessionStartedAt && $0 > now }
            .sorted()

        return candidates.reduce(into: [Date]()) { result, date in
            if let last = result.last, date.timeIntervalSince(last) <= minimumSpacingSeconds {
                result[result.count - 1] = date
            } else {
                result.append(date)
            }
        }
    }
}

// 10.3: Codable is written out by hand to fix the representation used on the wire and on disk.
extension PreNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, seconds, percent
    }

    private enum Kind: String, Codable {
        case beforeEnd, atElapsedPercent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .beforeEnd:
            self = .beforeEnd(seconds: try container.decode(Int.self, forKey: .seconds))
        case .atElapsedPercent:
            self = .atElapsedPercent(try container.decode(Int.self, forKey: .percent))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .beforeEnd(seconds):
            try container.encode(Kind.beforeEnd, forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        case let .atElapsedPercent(percent):
            try container.encode(Kind.atElapsedPercent, forKey: .type)
            try container.encode(percent, forKey: .percent)
        }
    }
}
