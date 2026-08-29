import Foundation

#if os(iOS)
import ActivityKit

// REQ-UIX-026: the extension cannot reach the network, so everything the display needs rides here.
// REQ-PRT-001: the app and the extension both use it, so it lives in the shared package.
public struct MdoroActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionType: SessionType
        // Already converted to this device's clock. Aligning the clocks is the app's job (REQ-COM-009).
        public var sessionStartedAt: Date
        public var sessionEndAt: Date
        // REQ-UIX-021 / 029: while paused, the countdown stops at this time.
        public var pauseTime: Date?
        public var loopDisplay: Int
        public var longBreakInterval: Int
        public var taskName: String?
        public var isConnected: Bool

        public init(
            sessionType: SessionType,
            sessionStartedAt: Date,
            sessionEndAt: Date,
            pauseTime: Date? = nil,
            loopDisplay: Int,
            longBreakInterval: Int,
            taskName: String? = nil,
            isConnected: Bool
        ) {
            self.sessionType = sessionType
            self.sessionStartedAt = sessionStartedAt
            self.sessionEndAt = sessionEndAt
            self.pauseTime = pauseTime
            self.loopDisplay = loopDisplay
            self.longBreakInterval = longBreakInterval
            // REQ-UIX-025: dynamic data stays within 4KB. The task name is cut to what can be shown.
            self.taskName = taskName.map { String($0.prefix(MdoroActivityAttributes.maxTaskNameLength)) }
            self.isConnected = isConnected
        }

        public var isPaused: Bool { pauseTime != nil }

        public var timerRange: ClosedRange<Date> {
            let end = max(sessionEndAt, sessionStartedAt.addingTimeInterval(1))
            return sessionStartedAt...end
        }
    }

    public var serverName: String

    public init(serverName: String) {
        self.serverName = serverName
    }

    // REQ-UIX-025: a practical cut-off length against the 4KB limit.
    public static let maxTaskNameLength = 60

    // REQ-UIX-023: the time beyond which there is no guarantee of a fresh state. Updated at + 90s.
    public static let staleAfter: TimeInterval = 90

    // REQ-UIX-023: how often staleDate is pushed out. Snapshots arrive only when the state changes
    // (REQ-COM-006), so without this the display goes stale after 90 seconds even while connected.
    public static let staleRefreshInterval: TimeInterval = 60
}
#endif
