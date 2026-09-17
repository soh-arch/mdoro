import Foundation

// REQ-LOG-010 / 011 / 012 / 013 / 016 / 023: the log line. REQ-LOG-003 / 022: the day heading,
// and whether one already in the file is that day's. No file I/O here.
public enum LogFormatter {
    public struct Options: Equatable, Sendable {
        // REQ-LOG-013: plain text by default. A setting turns the task name into a link.
        public var taskAsLink: Bool

        public init(taskAsLink: Bool = false) {
            self.taskAsLink = taskAsLink
        }

        public static let `default` = Options()
    }

    // REQ-UIX-038: weekday names are fixed three-letter English, never taken from the locale.
    static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // REQ-LOG-003: `## YYYY-MM-DD (Day)`
    public static func dayHeading(for logicalDate: Date, calendar: Calendar = .current) -> String {
        var utc = calendar
        // logicalDate was normalised to a calendar day by LogicalDay, so it is read back with the same calendar.
        utc.locale = Locale(identifier: "en_US_POSIX")
        let components = utc.dateComponents([.year, .month, .day, .weekday], from: logicalDate)
        let weekday = weekdaySymbols[((components.weekday ?? 1) - 1) % 7]
        return String(format: "## %04d-%02d-%02d (%@)",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0, weekday)
    }

    // REQ-LOG-003 / REQ-LOG-022 / Decision 0014: if the date reads, it is the same heading even when
    // the weekday has been rewritten. **Rewriting the weekday is not a "rename" under REQ-LOG-022.**
    // Taking it for a different heading and rebuilding one at the end would leave two headings for
    // the same day, splitting the record in two.
    //
    // **The date must follow `## ` directly.** Matching it anywhere in the line would match a heading
    // such as `## Weekly review for 2026-08-24` and drop log lines into the user's own section.
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

    // Seconds round to the nearest minute. Truncating would turn a just-completed 24m59s into 24m.
    static func minutes(_ seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded())
    }

    // REQ-LOG-010 / 011 / 012 / 013 / 016 / 023
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

        // REQ-LOG-011: carry the loop count after completion as n / longBreakInterval. n uses the same
        // modulo form as REQ-TIM-025.
        if entry.sessionType == .work, entry.outcome == .completed,
           let loopCount = entry.loopCountAfterCompletion, loopCount > 0, entry.longBreakInterval > 0 {
            let display = ((loopCount - 1) % entry.longBreakInterval) + 1
            parts.append("Loop \(display)/\(entry.longBreakInterval)")
        }

        // REQ-LOG-012: when the session was extended, the accumulated extension is written alongside.
        if entry.extendedSeconds > 0 {
            parts.append("(+\(minutes(entry.extendedSeconds))m extended)")
        }

        // REQ-LOG-016: mark the preset name with * when a group A setting was edited during the session.
        parts.append("[\(entry.presetName)\(entry.presetEditedDuringSession ? "*" : "")]")

        // REQ-LOG-010 / 023: the task name is for WORK only, and comes from the snapshot made at start.
        if entry.sessionType == .work, let task = entry.taskSnapshot, !task.isEmpty {
            parts.append("— \(options.taskAsLink ? "[[\(task)]]" : plainTaskName(task))")
        }

        return parts.joined(separator: " ")
    }

    // REQ-LOG-013: strip the brackets so a [[...]] in the text does not become a link by accident.
    static func plainTaskName(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }
}
