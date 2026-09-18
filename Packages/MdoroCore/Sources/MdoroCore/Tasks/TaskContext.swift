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
    //
    // REQ-PER-001 / 002: **the first reread after launch is one of these.** What is restored is an
    // id and a snapshot with no list behind them, and `referenceText` is what keeps the follow
    // working there rather than only for a file changing under a running app.
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
        guard let reference = referenceText(in: previous, selectedId: selectedId) else {
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // The candidates are the lines that were not in the previous list, plus what REQ-TSK-035 would otherwise miss.
        // When the earlier of two identical texts disappears, the ids after it shift — but those ids are
        // already known, so they do not count as newly appeared. A line whose text matches is therefore
        // a candidate even when its id is known.
        //
        // **With no previous list, every line is newly appeared and this filter lets all of them
        // through** (the restore path — see `referenceText`). What stands between the snapshot and a
        // wrong line is then `uniqueMatch` alone, and that is the check that was meant to carry the
        // weight: it refuses a tie, so an ambiguous restore follows nothing and the selection stays
        // missing (REQ-TSK-030).
        let previousIds = Set(previous.items.map(\.stableId))
        let candidates = parsed.items.filter {
            !previousIds.contains($0.stableId) || $0.normalizedText == reference
        }
        guard let followed = uniqueMatch(forNormalizedText: reference, among: candidates) else {
            // REQ-TSK-030 / 031: the selection is not cleared automatically. It stays missing.
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        context.selectedTaskId = followed.stableId
        context.selectedTaskSnapshot = followed.displayText
        return TaskReloadOutcome(context: context, followedFrom: selectedId, followedTo: followed.stableId)
    }

    // REQ-TSK-032 / 035: the text the selection is followed from. **The previous list is not always
    // there to hold it.** At launch the selection is restored from what was persisted (REQ-PER-001 /
    // 002), and that is the selected `stableId` and the snapshot of its text — not the list those
    // were read out of. The reread that follows therefore starts from a context with no items, so
    // asking it for the selected item answers nothing and the selection would be dropped on the
    // floor whenever the id had changed in the meantime. **An id changes without the user touching
    // the line**: it is the hash of the normalised text (REQ-TSK-021), so any change to what
    // normalisation does to that text gives the same line a different id on the next parse.
    //
    // So with no list to consult, the snapshot stands in for the item. It is `displayText`, which is
    // not the same text as `normalizedText`: it keeps emoji and has not been through NFKC, so those
    // two steps do their work here for the first time, while the rest of normalisation it has
    // already been through. **Normalising it back is therefore an approximation, not a recovery.**
    // It is good enough because what it feeds is itself an approximation — a match within 30% of the
    // length — and because it errs in the safe direction: where the two texts drift apart the
    // distance only grows, and too great a distance means no following, which is what happened
    // before this path existed.
    //
    // **Only an empty list falls back.** With items in hand, a selection missing from them stays
    // missing (REQ-TSK-030), exactly as it did: that list is evidence, and the item it does not
    // contain is a task the reread really did not find.
    static func referenceText(in previous: TaskContext, selectedId: String) -> String? {
        if let item = previous.item(id: selectedId) { return item.normalizedText }
        guard previous.items.isEmpty, let snapshot = previous.selectedTaskSnapshot else { return nil }
        return TaskTextNormalizer.normalize(body: snapshot)
    }

    // Returns a candidate within the threshold **only when it is the only one.** Ambiguity means no following.
    static func uniqueMatch(forNormalizedText source: String, among candidates: [TaskItem]) -> TaskItem? {
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
