import Foundation

// REQ-TSK-034: 選択中タスクの状態。判定順序は none → completed → present → missing。
public enum SelectedTaskState: String, Equatable, Sendable, Codable {
    case none
    case present
    case completed
    case missing
}

// REQ-TSK: 6章 / 10.3 TaskContext
public struct TaskContext: Equatable, Sendable {
    public var items: [TaskItem]
    public var wasTruncated: Bool
    public var selectedTaskId: String?
    // REQ-TSK-031: 最後に既知だった本文。消失後もログにはこれを記録する。
    public var selectedTaskSnapshot: String?
    // REQ-ERR-002 / REQ-ERR-001: 直近の読み込みが失敗したか。UI にエラーを表示するために持つ。
    // 失敗しても items は直前に成功した内容のまま残る。
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

    // REQ-TSK-034: `showCompletedTasks` は本判定に影響してはならない。
    // 表示上除外されているだけのタスクを missing と誤判定しないため、items は完了済みも含めて持つ。
    public var selectedTaskState: SelectedTaskState {
        guard selectedTaskId != nil else { return .none }
        guard let task = selectedTask else { return .missing }
        return task.isCompleted ? .completed : .present
    }

    // REQ-TSK-036: 現在の一覧に存在しない stableId は受け付けない。
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

// 再読み込みの結果。追従が起きたかを UI に伝える (REQ-TSK-032)。
public struct TaskReloadOutcome: Equatable, Sendable {
    public var context: TaskContext
    public var followedFrom: String?
    public var followedTo: String?

    public var didFollow: Bool { followedTo != nil }
}

public enum TaskReloader {
    // REQ-TSK-032: 本文長の 30% 以内。
    public static let similarityThreshold = 0.30

    // REQ-TSK-030 / 031 / 032 / 035: 再読み込みで選択をどう扱うか。
    //
    // 選択は勝手に外さない。消えたように見えても、文言の推敲で stableId が変わっただけのことがある
    // (contentHash 方式では、同一本文の先行する行が消えるだけでも変わる: REQ-TSK-035)。
    // 追従先が一意に定まるときだけ引き継ぎ、定まらなければ missing のまま維持する。
    // REQ-ERR-002: パースに失敗した場合は、直前に成功したタスク一覧を保持し続ける。
    // **空リストで上書きしないこと。** Obsidian の保存途中を読んだだけでも失敗しうるため、
    // ここで空に落とすと選択中タスクが missing へ転落する。
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

        // 同じ ID がまだあるなら、本文だけ最新に追いつかせる。
        if let stillThere = context.item(id: selectedId) {
            context.selectedTaskSnapshot = stillThere.displayText
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // 消えた。追従できるか調べる。
        guard let reference = previous.item(id: selectedId) else {
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        // 候補は「今回新しく現れた行」。加えて、REQ-TSK-035 の取りこぼしを拾う。
        // contentHash 方式では、同一本文の重複のうち先行するものが消えると後続の ID がずれる。
        // このとき残った行の ID は以前から存在しているため「新規出現」に入らず、
        // 素朴に絞ると追従できない。本文が一致する行は、ID が既知でも候補に含める。
        let previousIds = Set(previous.items.map(\.stableId))
        let candidates = parsed.items.filter {
            !previousIds.contains($0.stableId) || $0.normalizedText == reference.normalizedText
        }
        guard let followed = uniqueMatch(for: reference, among: candidates) else {
            // REQ-TSK-030 / 031: 自動的に選択を解除しない。missing のまま維持する。
            return TaskReloadOutcome(context: context, followedFrom: nil, followedTo: nil)
        }

        context.selectedTaskId = followed.stableId
        context.selectedTaskSnapshot = followed.displayText
        return TaskReloadOutcome(context: context, followedFrom: selectedId, followedTo: followed.stableId)
    }

    // 閾値を満たす候補が**一意に定まる場合のみ**返す。曖昧なら追従しない。
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
                    // 本文が完全に一致する候補が複数あっても、どれを選んでも記録される本文は同じ。
                    // 曖昧としてはねるのは、文言が違う候補が並んだときだけでよい。
                    if distance > 0 { bestIsAmbiguous = true }
                }
            } else {
                best = (candidate, distance)
            }
        }
        return bestIsAmbiguous ? nil : best?.item
    }
}
