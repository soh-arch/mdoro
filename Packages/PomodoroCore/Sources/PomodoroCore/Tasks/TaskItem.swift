import Foundation

// REQ-TSK-023: ID の種別を保持し、UI 上でブロック ID を持つタスクを識別できるようにする。
public enum TaskIdKind: String, Equatable, Sendable, Codable {
    case blockId
    case contentHash
}

// REQ-TSK: 6章 / 10.3 TaskItem
public struct TaskItem: Equatable, Sendable, Codable, Identifiable {
    public var stableId: String
    public var idKind: TaskIdKind
    // REQ-TSK-015: 表示用。Markdown 記法を落としたもの。
    public var displayText: String
    // REQ-TSK-022: 同一性の判定と REQ-TSK-032 の追従に使う正規化本文。
    public var normalizedText: String
    public var isCompleted: Bool
    public var depth: Int
    public var section: String
    public var parentId: String?
    public var lineNumber: Int

    public var id: String { stableId }

    public init(
        stableId: String,
        idKind: TaskIdKind,
        displayText: String,
        normalizedText: String,
        isCompleted: Bool,
        depth: Int,
        section: String,
        parentId: String?,
        lineNumber: Int
    ) {
        self.stableId = stableId
        self.idKind = idKind
        self.displayText = displayText
        self.normalizedText = normalizedText
        self.isCompleted = isCompleted
        self.depth = depth
        self.section = section
        self.parentId = parentId
        self.lineNumber = lineNumber
    }
}

// REQ-TSK-011: 見出しごとのグループ。見出しより前のタスクは「（未分類）」に入る。
public struct TaskSection: Equatable, Sendable, Identifiable {
    public let name: String
    public let items: [TaskItem]
    public var id: String { name }
}

public struct TaskParseResult: Equatable, Sendable {
    public var items: [TaskItem]
    // REQ-TSK-037 / REQ-ERR-003: 上限に達して打ち切ったか。UI に表示できるようにする。
    public var wasTruncated: Bool

    public var loadedCount: Int { items.count }

    public init(items: [TaskItem], wasTruncated: Bool) {
        self.items = items
        self.wasTruncated = wasTruncated
    }

    // REQ-TSK-011 / 014: 見出しごとにまとめる。ファイル内の出現順を保つ。
    public func grouped(showCompleted: Bool) -> [TaskSection] {
        var order: [String] = []
        var buckets: [String: [TaskItem]] = [:]
        for item in items where showCompleted || !item.isCompleted {
            if buckets[item.section] == nil {
                order.append(item.section)
                buckets[item.section] = []
            }
            buckets[item.section]?.append(item)
        }
        return order.map { TaskSection(name: $0, items: buckets[$0] ?? []) }
    }

    public func item(id: String) -> TaskItem? {
        items.first { $0.stableId == id }
    }
}
