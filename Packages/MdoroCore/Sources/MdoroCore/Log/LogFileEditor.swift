import Foundation

// REQ-LOG-001 / 003 / 022: pure functions that do one thing to the log file — insert lines.
//
// The user edits this file too. **Rewriting even one existing line destroys something of theirs.**
// Working out where to insert, and checking that nothing else moved, is kept here, apart from
// LogWriter, which is the part that touches the disk.
public enum LogFileEditor {

    public enum EditError: Error, Equatable, Sendable {
        // An existing line vanished or changed. Reaching this is a bug, so the write is abandoned.
        case wouldModifyExistingLines
    }

    public struct Insertion: Equatable, Sendable {
        public let contents: String
        // The lines actually inserted (including the heading, when a new one was created).
        public let insertedLines: [String]
    }

    // Insert one session's line into the existing contents.
    public static func inserting(
        line: String,
        underHeading heading: String,
        logicalDate: Date,
        into existing: String,
        calendar: Calendar = .current
    ) throws -> Insertion {
        // Match the existing file's line ending. An LF-only insertion would mix into a CRLF file.
        let newline = existing.contains("\r\n") ? "\r\n" : "\n"
        var lines = existing.isEmpty ? [] : existing.components(separatedBy: newline)
        // REQ-LOG-001: whether the file ends with a newline belongs to the file, not to us. The empty
        // element a trailing one leaves is held out of the position arithmetic and put back at the end
        // — **put back only if it was there.** Adding one is a change to a line already in the file, and
        // insertion is the only thing allowed here.
        //
        // A file that does not exist yet is given one. There is nothing of the user's to preserve, and a
        // Markdown file ending mid-line makes whatever is written next share that line.
        var endsWithNewline = existing.isEmpty
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
            endsWithNewline = true
        }
        let original = lines

        let insertedLines: [String]
        let insertIndex: Int

        if let headingIndex = lines.firstIndex(where: {
            LogFormatter.headingMatches($0, logicalDate: logicalDate, calendar: calendar)
        }) {
            // REQ-LOG-003: when the heading already exists, append at the end of that day's section.
            var end = lines.index(after: headingIndex)
            while end < lines.count, !lines[end].hasPrefix("## ") {
                end = lines.index(after: end)
            }
            // Insert above the blank lines closing the section: they are the gap before the next heading, so they stay put.
            var position = end
            while position > lines.index(after: headingIndex),
                  lines[position - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                position -= 1
            }
            insertedLines = [line]
            insertIndex = position
        } else {
            // REQ-LOG-022: if the heading was removed elsewhere, recreate it and append **at the end of the
            // file.** Never try to restore or repair existing lines.
            var prefix: [String] = []
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                prefix.append("")
            }
            insertedLines = prefix + [heading, "", line]
            insertIndex = lines.count
        }

        lines.insert(contentsOf: insertedLines, at: insertIndex)

        // **Before writing, confirm that nothing but an insertion happened.** Guarded by a check, not by intent.
        guard preservesAllLines(original: original, updated: lines, insertedAt: insertIndex, count: insertedLines.count) else {
            throw EditError.wouldModifyExistingLines
        }

        // The guard above compares arrays of lines, so it never saw this byte. It has to be carried.
        let contents = lines.joined(separator: newline) + (endsWithNewline ? newline : "")
        return Insertion(contents: contents, insertedLines: insertedLines)
    }

    // Removing the inserted lines from the updated array must give back the original array.
    static func preservesAllLines(original: [String], updated: [String], insertedAt index: Int, count: Int) -> Bool {
        guard updated.count == original.count + count else { return false }
        var rebuilt = updated
        rebuilt.removeSubrange(index..<(index + count))
        return rebuilt == original
    }
}
