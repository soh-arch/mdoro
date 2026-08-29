import Foundation

// REQ-TSK-034: the state of the selected task. Decided in the order none → completed → present → missing.
public enum SelectedTaskState: String, Equatable, Sendable, Codable {
    case none
    case present
    case completed
    case missing
}

// REQ-TSK: chapter 6 / 10.3 TaskContext
public struct TaskContext: Equatable, Sendable, Codable {
    public var items: [TaskItem]
    public var wasTruncated: Bool
    public var selectedTaskId: String?
    // REQ-TSK-031: the last text known. Even after the task is gone, this is what the log records.
    public var selectedTaskSnapshot: String?
    // REQ-ERR-001 / 002: whether the last read failed. On failure, items keeps what it held before.
    public var loadFailed: Bool

    public init(
        items: [TaskItem] = [],
        wasTruncated: Bool = false,
        selectedTaskId: String? = nil,
        selectedTaskSnapshot: String? = nil,
        loadFailed: Bool = false
    ) {
        self.items = items
        self.wasTruncated = wasTruncated
        self.selectedTaskId = selectedTaskId
        self.selectedTaskSnapshot = selectedTaskSnapshot
        self.loadFailed = loadFailed
    }

    public func item(id: String) -> TaskItem? {
        items.first { $0.stableId == id }
    }

    public var selectedTask: TaskItem? {
        selectedTaskId.flatMap(item(id:))
    }

    // REQ-TSK-034: `showCompletedTasks` must not reach this decision.
    // items holds completed tasks too, so a task merely hidden from view is not mistaken for missing.
    public var selectedTaskState: SelectedTaskState {
        guard selectedTaskId != nil else { return .none }
        guard let task = selectedTask else { return .missing }
        return task.isCompleted ? .completed : .present
    }

    // REQ-TSK-036: a stableId that is not in the current list is refused.
    public mutating func select(id: String) throws {
        guard let task = item(id: id) else { throw TimerError.taskNotFound }
        selectedTaskId = id
        selectedTaskSnapshot = task.displayText
    }

    public mutating func clearSelection() {
        selectedTaskId = nil
        selectedTaskSnapshot = nil
    }

    public func grouped(showCompleted: Bool) -> [TaskSection] {
        TaskParseResult(items: items, wasTruncated: wasTruncated).grouped(showCompleted: showCompleted)
    }
}

// The result of a reread. Tells the UI whether the selection followed an edit (REQ-TSK-032).
public struct TaskReloadOutcome: Equatable, Sendable {
    public var context: TaskContext
    public var followedFrom: String?
    public var followedTo: String?

    public var didFollow: Bool { followedTo != nil }
}

public enum TaskReloader {
    // REQ-TSK-032: within 30% of the text's length.
    public static let similarityThreshold = 0.30

    // REQ-TSK-030 / 031 / 032 / 035: what a reread does to the selection.
    //
    // **The selection is never dropped on its own.** A task that looks gone may only have been
    // reworded, changing its stableId. The selection follows only when one destination is
    // unambiguous; otherwise it stays missing.
    // REQ-ERR-002: a failed parse keeps the previous list. **Never overwrite it with an empty one.**
    public static func reload(
        previous: TaskContext,
        result: Result<TaskParseResult, Error>
    ) -> TaskReloadOutcome {
        switch result {
        case let .success(parsed):
            return reload(previous: previous, parsed: parsed)
        case .failure:
            var kept = previous
            kept.loadFailed = true
            return TaskReloadOutcome(context: kept, followedFrom: nil, followedTo: nil)
        }
    }

    public static func reload(
        previous: TaskContext,
        parsed: TaskParseResult
    ) -> TaskReloadOutcome {
        var context = TaskContext(
            items: parsed.items,
            wasTruncated: parsed.wasTruncated,
            selectedTaskId: previous.selectedTaskId,
            selectedTaskSnapshot: previous.selectedTaskSnapshot,
            loadFailed: false
        )

        guard let selectedId = previous.selectedTaskId else {
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // If the same id is still there, only the text catches up.
        if let stillThere = context.item(id: selectedId) {
            context.selectedTaskSnapshot = stillThere.displayText
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // It is gone. See whether the selection can follow it.
        guard let reference = previous.item(id: selectedId) else {
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // The candidates are the lines that appeared this time, plus what REQ-TSK-035 would otherwise miss.
        // When the earlier of two identical texts disappears, the ids after it shift — but those ids are
        // already known, so they do not count as newly appeared. A line whose text matches is therefore
        // a candidate even when its id is known.
        let previousIds = Set(previous.items.map(\.stableId))
        let candidates = parsed.items.filter {
            !previousIds.contains($0.stableId) || $0.normalizedText == reference.normalizedText
        }
        guard let followed = uniqueMatch(for: reference, among: candidates) else {
            // REQ-TSK-030 / 031: the selection is not cleared automatically. It stays missing.
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        context.selectedTaskId = followed.stableId
        context.selectedTaskSnapshot = followed.displayText
        return TaskReloadOutcome(context: context, followedFrom: selectedId, followedTo: followed.stableId)
    }

    // Returns a candidate within the threshold **only when it is the only one.** Ambiguity means no following.
    static func uniqueMatch(for reference: TaskItem, among candidates: [TaskItem]) -> TaskItem? {
        let source = reference.normalizedText
        guard !source.isEmpty else { return nil }
        let allowed = Int((Double(source.count) * similarityThreshold).rounded())

        var best: (item: TaskItem, distance: Int)?
        var bestIsAmbiguous = false
        for candidate in candidates {
            let distance = TaskTextNormalizer.levenshteinDistance(source, candidate.normalizedText)
            guard distance <= allowed else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (candidate, distance)
                    bestIsAmbiguous = false
                } else if distance == current.distance {
                    // With the texts identical, whichever is chosen, the text recorded is the same.
                    if distance > 0 { bestIsAmbiguous = true }
                }
            } else {
                best = (candidate, distance)
            }
        }
        return bestIsAmbiguous ? nil : best?.item
    }
}
