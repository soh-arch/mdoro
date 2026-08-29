import Foundation

// REQ-TSK-023: the kind of id, so the UI can tell which tasks carry a block id.
public enum TaskIdKind: String, Equatable, Sendable, Codable {
    case blockId
    case contentHash
}

// REQ-TSK: chapter 6 / 10.3 TaskItem
public struct TaskItem: Equatable, Sendable, Codable, Identifiable {
    public var stableId: String
    public var idKind: TaskIdKind
    // REQ-TSK-015: for display. The Markdown notation has been taken off.
    public var displayText: String
    // REQ-TSK-022: the normalised text, used to decide identity and to follow an edit (REQ-TSK-032).
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

// REQ-TSK-011: a group per heading. Tasks above the first heading go into "(Uncategorized)".
public struct TaskSection: Equatable, Sendable, Identifiable {
    public let name: String
    public let items: [TaskItem]
    public var id: String { name }
}

public struct TaskParseResult: Equatable, Sendable {
    public var items: [TaskItem]
    // REQ-TSK-037 / REQ-ERR-003: whether the limit was reached and the read cut short, so the UI can say so.
    public var wasTruncated: Bool

    public var loadedCount: Int { items.count }

    public init(items: [TaskItem], wasTruncated: Bool) {
        self.items = items
        self.wasTruncated = wasTruncated
    }

    // REQ-TSK-011 / 014: gather by heading, keeping the order they appear in the file.
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
