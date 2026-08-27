import Foundation

// REQ-LOG-001 / 003 / 022: ログファイルへの「行の挿入」だけを行う純粋関数。
//
// このファイルはユーザーの保管場所の中にあり、ユーザー自身も編集する。
// 既存行を1行でも書き換えれば、アプリの外にあるユーザーの資産を壊す。
// そのため挿入位置の計算と、**既存行が保存されていることの検証**をここに閉じ込め、
// 入出力を持つ側 (LogWriter) から分離している。
public enum LogFileEditor {

    public enum EditError: Error, Equatable, Sendable {
        // 挿入の結果、既存行が消えた・変わった。到達したら実装の誤りなので書き込みを中止する。
        case wouldModifyExistingLines
    }

    public struct Insertion: Equatable, Sendable {
        public let contents: String
        // 実際に挿入した行 (見出しを新設した場合は見出しを含む)。
        public let insertedLines: [String]
    }

    // 既存の内容へ1セッション分の行を挿入する。
    public static func inserting(
        line: String,
        underHeading heading: String,
        logicalDate: Date,
        into existing: String,
        calendar: Calendar = .current
    ) throws -> Insertion {
        // 既存ファイルの改行コードに合わせる。挿入行だけ LF になると、CRLF のファイルで混ざる。
        let newline = existing.contains("\r\n") ? "\r\n" : "\n"
        var lines = existing.isEmpty ? [] : existing.components(separatedBy: newline)
        // 末尾の改行で生じる空要素は、挿入位置の計算から外して最後に戻す。
        var trailingNewline = false
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
            trailingNewline = true
        }
        let original = lines

        let insertedLines: [String]
        let insertIndex: Int

        if let headingIndex = lines.firstIndex(where: {
            LogFormatter.headingMatches($0, logicalDate: logicalDate, calendar: calendar)
        }) {
            // REQ-LOG-003: 当該見出しが既に存在する場合は、その日付セクションの末尾へ追記する。
            var end = lines.index(after: headingIndex)
            while end < lines.count, !lines[end].hasPrefix("## ") {
                end = lines.index(after: end)
            }
            // セクション末尾の空行より前に入れる。空行は次の見出しとの間隔なので動かさない。
            var position = end
            while position > lines.index(after: headingIndex),
                  lines[position - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                position -= 1
            }
            insertedLines = [line]
            insertIndex = position
        } else {
            // REQ-LOG-022: 見出しが外部で削除・改名されていた場合は、見出しを再作成して
            // **ファイル末尾へ**追記する。既存の行を復元・修正しようとしてはならない。
            var prefix: [String] = []
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                prefix.append("")
            }
            insertedLines = prefix + [heading, "", line]
            insertIndex = lines.count
        }

        lines.insert(contentsOf: insertedLines, at: insertIndex)

        // **挿入以外のことをしていないことを、書き込む前に確かめる。**
        // 意図ではなく検査で守る。ここを通らなければファイルには触れない。
        guard preservesAllLines(original: original, updated: lines, insertedAt: insertIndex, count: insertedLines.count) else {
            throw EditError.wouldModifyExistingLines
        }

        let contents = lines.joined(separator: newline) + newline
        return Insertion(contents: contents, insertedLines: insertedLines)
    }

    // 更新後の行列から挿入分を取り除くと、元の行列に一致すること。
    static func preservesAllLines(original: [String], updated: [String], insertedAt index: Int, count: Int) -> Bool {
        guard updated.count == original.count + count else { return false }
        var rebuilt = updated
        rebuilt.removeSubrange(index..<(index + count))
        return rebuilt == original
    }
}
