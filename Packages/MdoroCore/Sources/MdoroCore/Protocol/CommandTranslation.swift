import Foundation

// 10.2 の `command` を `TimerAction` に翻訳する。
//
// **通信層に判断を持たせない。** ここは形の変換だけを行い、受理可否は状態機械が決める
// （REQ-ERR-016 / 4.6 マトリクス）。
public enum CommandTranslation {

    public enum Failure: Error, Equatable, Sendable {
        case missingParameter(String)
        case invalidParameter(String)

        public var errorCode: ProtocolErrorCode {
            switch self {
            case .missingParameter, .invalidParameter: return .invalidStateForAction
            }
        }
    }

    public static func action(
        for command: CommandPayload,
        activePresetId: String,
        selectedTaskSnapshot: String?
    ) -> Result<TimerAction, Failure> {
        let params = command.params ?? CommandParams()

        switch command.action {
        case .startWork:
            return .success(.startWork(presetId: activePresetId, taskSnapshot: selectedTaskSnapshot))

        case .startBreak:
            // 10.2: sessionType は必須。省略できない。
            guard let type = params.sessionType else { return .failure(.missingParameter("sessionType")) }
            guard type == .shortBreak || type == .longBreak else {
                return .failure(.invalidParameter("sessionType"))
            }
            return .success(.startBreak(type: type, presetId: activePresetId))

        case .pause: return .success(.pause)
        case .resume: return .success(.resume)
        case .skip: return .success(.skip)
        case .abort: return .success(.abort)
        case .extend: return .success(.extend)
        case .resetLoopCount: return .success(.resetLoopCount)

        case .confirmRestoredSession:
            guard let decision = params.decision else { return .failure(.missingParameter("decision")) }
            switch decision {
            case .complete: return .success(.confirmRestoredSession(.complete))
            case .discard: return .success(.confirmRestoredSession(.discard))
            // 10.2: プロトコル上の `resume` は内部の `continueSession` に対応する。
            case .resume: return .success(.confirmRestoredSession(.continueSession))
            }

        case .selectTask:
            guard let stableId = params.stableId else { return .failure(.missingParameter("stableId")) }
            return .success(.selectTask(snapshot: stableId))

        case .clearTaskSelection: return .success(.clearTaskSelection)
        case .reloadTasks: return .success(.reloadTasks)

        case .updateSettings:
            guard let settings = params.settings else { return .failure(.missingParameter("settings")) }
            return .success(.updateSettings(settings))

        case .selectPreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter("presetId")) }
            return .success(.selectPreset(id: presetId))

        case .createPreset:
            guard let preset = params.preset else { return .failure(.missingParameter("preset")) }
            return .success(.createPreset(preset))

        case .duplicatePreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter("presetId")) }
            return .success(.duplicatePreset(id: presetId))

        case .updatePreset:
            guard let preset = params.preset else { return .failure(.missingParameter("preset")) }
            return .success(.updatePreset(preset))

        case .deletePreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter("presetId")) }
            return .success(.deletePreset(id: presetId))

        case .reorderPresets:
            guard let orderedIds = params.orderedIds else { return .failure(.missingParameter("orderedIds")) }
            return .success(.reorderPresets(order: orderedIds))

        case .restoreDefaultPreset:
            return .success(.restoreDefaultPreset)
        }
    }
}

// REQ-PRT-003: 同一 clientRequestId の再送を無視する。
//
// 再接続直後にクライアントが取りこぼしを再送することがある。冪等にしないと、
// 「延長」が二重に効いたり、周回数が余分に動いたりする。
public struct RequestDeduplicator: Sendable {
    private var seen: [String] = []
    private var seenSet: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    // 初めて見た ID なら true。既出なら false（＝処理しない）。
    public mutating func shouldProcess(_ requestId: String) -> Bool {
        guard !seenSet.contains(requestId) else { return false }
        seen.append(requestId)
        seenSet.insert(requestId)
        if seen.count > capacity {
            let dropped = seen.removeFirst()
            seenSet.remove(dropped)
        }
        return true
    }
}
