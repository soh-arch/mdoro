import Foundation

// REQ-TSK-010〜023: Task.md のパース。**読み取り専用**であり、この型はファイルへ書き戻す手段を持たない。
public enum TaskParseError: Error, Equatable, Sendable {
    // REQ-ERR-002: 読めたがテキストとして解釈できない。**空リストとして扱ってはならない。**
    case undecodable
}

public enum TaskParser {
    // REQ-ERR-003: ファイルサイズ・行数にかかわらず、タスクは先頭から 1,000 件まで。
    public static let maxTaskCount = 1_000
    // REQ-ERR-003: 5MB を超えるファイルは先頭 5MB のみを読む。
    public static let maxBytes = 5 * 1_024 * 1_024
    public static let uncategorizedSection = "(Uncategorized)"

    public static func parse(_ contents: String) -> TaskParseResult {
        var items: [TaskItem] = []
        var truncated = false
        var section = uncategorizedSection
        // REQ-TSK-013: 最初に検出したインデントを1段分とする。
        var indentUnit: Int?
        // 深さごとの直近の親候補。見出しをまたいで引き継がない。
        var ancestors: [Int: String] = [:]
        // REQ-TSK-021: 同一ハッシュ内での出現順。ブロック ID の重複にも同じ規則を使う。
        var idOccurrences: [String: Int] = [:]
        // コードブロックの中は Markdown ではない。見出しもタスクも拾わない。
        var insideFence = false

        for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let fenceCandidate = rawLine.trimmingCharacters(in: .whitespaces)
            if fenceCandidate.hasPrefix("```") || fenceCandidate.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }

            let lineRange = NSRange(rawLine.startIndex..., in: rawLine)

            // REQ-TSK-011: 見出しをセクションとして認識する。
            if let heading = TaskTextNormalizer.headingPattern.firstMatch(in: rawLine, range: lineRange),
               let titleRange = Range(heading.range(at: 2), in: rawLine) {
                let title = String(rawLine[titleRange]).trimmingCharacters(in: .whitespaces)
                section = title.isEmpty ? uncategorizedSection : title
                // 別の見出しに入ったら、前の節のタスクを親として引き継がない。
                ancestors.removeAll()
                continue
            }

            // REQ-TSK-010: この正規表現に一致する行だけをタスクとして扱う。
            guard let match = TaskTextNormalizer.taskLinePattern.firstMatch(in: rawLine, range: lineRange),
                  let indentRange = Range(match.range(at: 1), in: rawLine),
                  let markRange = Range(match.range(at: 2), in: rawLine),
                  let wholeRange = Range(match.range, in: rawLine) else {
                continue
            }

            guard items.count < maxTaskCount else {
                truncated = true
                break
            }

            // REQ-TSK-012: チェックボックス内が半角スペース以外なら完了済み。
            let isCompleted = rawLine[markRange] != " "

            let indentWidth = rawLine[indentRange].count
            if indentUnit == nil, indentWidth > 0 { indentUnit = indentWidth }
            // REQ-TSK-013: 倍数に満たない中途半端なインデントは、直近の浅い方の深さへ丸める。
            let depth = indentUnit.map { indentWidth / $0 } ?? 0

            let remainder = String(rawLine[wholeRange.upperBound...])
            let (body, blockId) = TaskTextNormalizer.extractBlockId(from: remainder)
            let normalized = TaskTextNormalizer.normalize(body: body)

            let base: String
            let idKind: TaskIdKind
            if let blockId {
                // REQ-TSK-020: ブロック ID があればそれを採用する。
                base = blockId
                idKind = .blockId
            } else {
                // REQ-TSK-021: 正規化本文のハッシュ。
                base = TaskTextNormalizer.contentHash(normalized)
                idKind = .contentHash
            }
            // 同一ハッシュ内での出現順 (REQ-TSK-021)。
            // ブロック ID がユーザーの操作で重複することもあり、その場合も一意にしておかないと
            // 2件目が選択できなくなり、UI の ForEach も破綻する。
            // 先頭の1件は接尾辞を付けず、ブロック ID の見た目と安定性を保つ。
            let occurrence = idOccurrences[base, default: 0]
            idOccurrences[base] = occurrence + 1
            let stableId = (idKind == .blockId && occurrence == 0) ? base : "\(base)#\(occurrence)" 

            // REQ-TSK-013 / 014: 親子関係を保持する。
            ancestors = ancestors.filter { $0.key < depth }
            let parentId = depth > 0 ? ancestors[depth - 1] : nil
            ancestors[depth] = stableId

            items.append(
                TaskItem(
                    stableId: stableId,
                    idKind: idKind,
                    displayText: TaskTextNormalizer.displayText(fromBody: body),
                    normalizedText: normalized,
                    isCompleted: isCompleted,
                    depth: depth,
                    section: section,
                    parentId: parentId,
                    lineNumber: index + 1
                )
            )
        }

        return TaskParseResult(items: items, wasTruncated: truncated)
    }

    // REQ-ERR-003: 5MB を超えるファイルは先頭 5MB のみを読む。
    // マルチバイト文字の途中で切れても落ちないよう、末尾の不完全なバイト列は捨てる。
    //
    // REQ-ERR-002: 解釈できなかった場合は throw する。**空の結果を返してはならない。**
    // 空リストを返すと、呼び出し側が「タスクが0件になった」と受け取り、直前まで読めていた
    // 一覧を上書きしてしまう (Obsidian の保存途中を読んだだけでも起こる)。
    public static func parse(data: Data) throws -> TaskParseResult {
        let limited = data.count > maxBytes ? data.prefix(maxBytes) : data[...]
        var slice = Data(limited)
        var text = String(data: slice, encoding: .utf8)
        var dropped = 0
        while text == nil, dropped < 4, !slice.isEmpty {
            slice = slice.dropLast()
            dropped += 1
            text = String(data: slice, encoding: .utf8)
        }
        guard let contents = text else { throw TaskParseError.undecodable }

        var result = parse(contents)
        if data.count > maxBytes { result.wasTruncated = true }
        return result
    }
}
