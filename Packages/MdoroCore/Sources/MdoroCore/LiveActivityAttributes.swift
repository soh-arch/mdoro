import Foundation

#if os(iOS)
import ActivityKit

// REQ-UIX-026: 拡張はネットワークにアクセスできない。表示に必要な情報はすべてここに載せる。
// REQ-PRT-001: 本体と拡張の双方が使うため共有パッケージに置く。
public struct MdoroActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionType: SessionType
        // 端末ローカル時刻に直したもの。時計合わせは本体の仕事（REQ-COM-009）。
        public var sessionStartedAt: Date
        public var sessionEndAt: Date
        // REQ-UIX-021 / 029: 停止中はこの時刻でカウントダウンが止まる。
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
            // REQ-UIX-025: 動的データは 4KB 以内。タスク名は表示可能長で切り詰める。
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

    // REQ-UIX-025: 4KB の上限に対する実務的な打ち切り長。
    public static let maxTaskNameLength = 60

    // REQ-UIX-023: 次に状態を確認できる保証がない時刻。更新時刻＋90秒。
    public static let staleAfter: TimeInterval = 90

    // REQ-UIX-023: staleDate を押し出す間隔。スナップショットは状態変化時しか来ない（REQ-COM-006）ため、
    // これを回さないと接続中でも 90 秒で陳腐化表示になる。
    public static let staleRefreshInterval: TimeInterval = 60
}
#endif
