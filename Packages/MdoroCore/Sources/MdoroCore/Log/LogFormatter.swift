import Foundation

// REQ-LOG-010〜017 / 023: ログ1行と日付見出しの整形。ファイル入出力は持たない。
public enum LogFormatter {
    public struct Options: Equatable, Sendable {
        // REQ-LOG-013: 既定はプレーンテキスト。設定でリンク化を選べる。
        public var taskAsLink: Bool

        public init(taskAsLink: Bool = false) {
            self.taskAsLink = taskAsLink
        }

        public static let `default` = Options()
    }

    // REQ-UIX-038: 曜日はロケールに左右させず、英語3文字で固定する。
    static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // REQ-LOG-003: `## YYYY-MM-DD (Day)`
    public static func dayHeading(for logicalDate: Date, calendar: Calendar = .current) -> String {
        var utc = calendar
        // logicalDate は LogicalDay が暦日として正規化した値なので、同じ暦で読み戻す。
        utc.locale = Locale(identifier: "en_US_POSIX")
        let components = utc.dateComponents([.year, .month, .day, .weekday], from: logicalDate)
        let weekday = weekdaySymbols[((components.weekday ?? 1) - 1) % 7]
        return String(format: "## %04d-%02d-%02d (%@)",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0, weekday)
    }

    // REQ-LOG-003 / Decision 0014: 日付が読めれば、曜日が書き換えられていても同一の見出しとみなす。
    //
    // **日付は `## ` の直後に限る。** 行のどこかにあれば一致とすると、
    // `## 週次レビュー 2026-08-24 の分` のような見出しに一致し、ユーザーの節へログ行を混入させる。
    public static func headingMatches(_ line: String, logicalDate: Date, calendar: Calendar = .current) -> Bool {
        guard let dateRange = line.range(of: #"^##[ \t]+(\d{4}-\d{2}-\d{2})"#, options: .regularExpression) else {
            return false
        }
        let expected = dayHeading(for: logicalDate, calendar: calendar)
        guard let expectedDate = expected.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
              let actualDate = line[dateRange].range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return false
        }
        return expected[expectedDate] == line[dateRange][actualDate]
    }

    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    // 秒は最も近い分へ丸める。切り捨てると完了直後の 24m59s が 24m になる。
    static func minutes(_ seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded())
    }

    // REQ-LOG-010〜016 / 023
    public static func line(for entry: LogEntry, options: Options = .default, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        parts.append("-")
        parts.append("\(timeOfDay(entry.startedAt, calendar: calendar))–\(timeOfDay(entry.endedAt, calendar: calendar))")
        parts.append(entry.sessionType.rawValue)
        parts.append("\(minutes(entry.elapsedSeconds))m")

        switch entry.outcome {
        case .completed: parts.append("✅")
        case .skipped: parts.append("⏭ Skipped")
        case .aborted: parts.append("⏹ Stopped")
        }

        // REQ-LOG-011: 完了後の周回数を n / longBreakInterval で含める。n は REQ-TIM-025 と同じ剰余表現。
        if entry.sessionType == .work, entry.outcome == .completed,
           let loopCount = entry.loopCountAfterCompletion, loopCount > 0, entry.longBreakInterval > 0 {
            let display = ((loopCount - 1) % entry.longBreakInterval) + 1
            parts.append("Loop \(display)/\(entry.longBreakInterval)")
        }

        // REQ-LOG-012: 延長が行われた場合は累積延長時間を併記する。
        if entry.extendedSeconds > 0 {
            parts.append("(+\(minutes(entry.extendedSeconds))m extended)")
        }

        // REQ-LOG-016: A 群がセッション中に編集されていたらプリセット名に * を付す。
        parts.append("[\(entry.presetName)\(entry.presetEditedDuringSession ? "*" : "")]")

        // REQ-LOG-010 / 023: タスク名は WORK のみ。開始時点のスナップショットを使う。
        if entry.sessionType == .work, let task = entry.taskSnapshot, !task.isEmpty {
            parts.append("— \(options.taskAsLink ? "[[\(task)]]" : plainTaskName(task))")
        }

        return parts.joined(separator: " ")
    }

    // REQ-LOG-013: 本文の [[...]] が意図せずリンクにならないよう括弧を落とす。
    static func plainTaskName(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }
}
