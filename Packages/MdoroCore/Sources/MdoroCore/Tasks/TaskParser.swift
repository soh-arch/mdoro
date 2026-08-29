import Foundation

// REQ-TSK-010 to 023: parsing Task.md. **Read-only** — this type offers no way to write back to the file.
public enum TaskParseError: Error, Equatable, Sendable {
    // REQ-ERR-002: it read, but it is not text. **This must never be taken for an empty list.**
    case undecodable
}

public enum TaskParser {
    // REQ-ERR-003: whatever the file's size or line count, the first 1,000 tasks are taken and no more.
    public static let maxTaskCount = 1_000
    // REQ-ERR-003: past 5MB, only the first 5MB of the file is read.
    public static let maxBytes = 5 * 1_024 * 1_024
    public static let uncategorizedSection = "(Uncategorized)"

    public static func parse(_ contents: String) -> TaskParseResult {
        var items: [TaskItem] = []
        var truncated = false
        var section = uncategorizedSection
        // REQ-TSK-013: the first indent found is one level.
        var indentUnit: Int?
        // The latest candidate parent at each depth. Nothing carries across a heading.
        var ancestors: [Int: String] = [:]
        // REQ-TSK-021: the position among lines sharing a hash. A repeated block id follows the same rule.
        var idOccurrences: [String: Int] = [:]
        // Inside a code fence nothing is Markdown. Neither headings nor tasks are picked up.
        var insideFence = false

        for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let fenceCandidate = rawLine.trimmingCharacters(in: .whitespaces)
            if fenceCandidate.hasPrefix("```") || fenceCandidate.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }

            let lineRange = NSRange(rawLine.startIndex..., in: rawLine)

            // REQ-TSK-011: a heading opens a section.
            if let heading = TaskTextNormalizer.headingPattern.firstMatch(in: rawLine, range: lineRange),
               let titleRange = Range(heading.range(at: 2), in: rawLine) {
                let title = String(rawLine[titleRange]).trimmingCharacters(in: .whitespaces)
                section = title.isEmpty ? uncategorizedSection : title
                // On entering another heading, no task from the section before it stays a parent.
                ancestors.removeAll()
                continue
            }

            // REQ-TSK-010: only a line matching this expression is a task.
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

            // REQ-TSK-012: anything but a space inside the checkbox means completed.
            let isCompleted = rawLine[markRange] != " "

            let indentWidth = rawLine[indentRange].count
            if indentUnit == nil, indentWidth > 0 { indentUnit = indentWidth }
            // REQ-TSK-013: an indent that falls between multiples rounds down to the shallower depth.
            let depth = indentUnit.map { indentWidth / $0 } ?? 0

            let remainder = String(rawLine[wholeRange.upperBound...])
            let (body, blockId) = TaskTextNormalizer.extractBlockId(from: remainder)
            let normalized = TaskTextNormalizer.normalize(body: body)

            let base: String
            let idKind: TaskIdKind
            if let blockId {
                // REQ-TSK-020: a block id, where there is one, is what is used.
                base = blockId
                idKind = .blockId
            } else {
                // REQ-TSK-021: the hash of the normalised text.
                base = TaskTextNormalizer.contentHash(normalized)
                idKind = .contentHash
            }
            // REQ-TSK-021: the position among lines sharing a hash. A block id can repeat, so the same rule
            // makes it unique. The first one takes no suffix, which keeps a block id looking like itself.
            let occurrence = idOccurrences[base, default: 0]
            idOccurrences[base] = occurrence + 1
            let stableId = (idKind == .blockId && occurrence == 0) ? base : "\(base)#\(occurrence)" 

            // REQ-TSK-013 / 014: keep the parent and child relation.
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

    // REQ-ERR-003: only the first 5MB is read, and an incomplete byte sequence at the end is dropped.
    // REQ-ERR-002: what cannot be decoded throws. **An empty result must never be returned.**
    // Taken for zero tasks, it would overwrite the list that was readable a moment ago.
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
