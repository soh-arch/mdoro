import Foundation

// REQ-ERR-016 / 10.2: translate a `command` into a `TimerAction`.
// **The transport layer decides nothing.** It converts shapes; the state machine decides what is accepted.
public enum CommandTranslation {

    // 10.2: the fields a `command` can carry. A case rather than a string literal at each
    // call, because Decision 0034 needs somewhere to hang a code: the case name of a failure
    // says what went wrong with a field, and the code says which field, so `case(domain:code)`
    // holds without spending the resolution the decision says not to lose.
    public enum Parameter: String, Equatable, Hashable, Sendable, CaseIterable {
        case sessionType
        case decision
        case stableId
        case settings
        case presetId
        case preset
        case orderedIds

        // 50–59 in the `Mdoro` domain. Handed out here, like 40–49 are with `TimerError`;
        // `ErrorCode.swift` holds the rest of the table.
        public var errorCode: ErrorCode {
            switch self {
            case .sessionType: ErrorCode(own: 50)
            case .decision: ErrorCode(own: 51)
            case .stableId: ErrorCode(own: 52)
            case .settings: ErrorCode(own: 53)
            case .presetId: ErrorCode(own: 54)
            case .preset: ErrorCode(own: 55)
            case .orderedIds: ErrorCode(own: 56)
            }
        }
    }

    // REQ-ERR-010 / Decision 0034: one of ours, written the way an OS failure is written.
    public enum Failure: Error, Equatable, Sendable, DiagnosableError {
        case missingParameter(Parameter)
        case invalidParameter(Parameter)
        // REQ-CFG-018 / REQ-PRT-005: the field carries a value this version has no case for.
        // **A value that cannot be read is out of range**: it is not applied, and it is not bent
        // onto a case it resembles either, because that would put a setting on the Mac that
        // nobody asked for.
        case valueOutOfRange(Parameter)

        // 10.2: what the iPhone gets in `error.code`, which is where its wording comes from.
        // Named apart from `errorCode` because that one answers the diagnostic log instead.
        public var protocolErrorCode: ProtocolErrorCode {
            switch self {
            case .missingParameter, .invalidParameter: return .invalidStateForAction
            // REQ-CFG-018: the same answer a number outside its range gets. 10.2 defines the code
            // as "the setting is outside the allowed range" and draws no line inside that.
            case .valueOutOfRange: return .settingOutOfRange
            }
        }

        public var errorCode: ErrorCode {
            switch self {
            case let .missingParameter(parameter), let .invalidParameter(parameter),
                 let .valueOutOfRange(parameter):
                return parameter.errorCode
            }
        }

        // Spelled out rather than reflected: `String(describing:)` would carry the payload
        // into the case name and break the one shape every failure is written in.
        public var diagnosticSummary: String {
            switch self {
            case .missingParameter: return errorCode.summary("missingParameter")
            case .invalidParameter: return errorCode.summary("invalidParameter")
            case .valueOutOfRange: return errorCode.summary("valueOutOfRange")
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
            // 10.2: sessionType is required and cannot be omitted.
            guard let type = params.sessionType else { return .failure(.missingParameter(.sessionType)) }
            guard type == .shortBreak || type == .longBreak else {
                return .failure(.invalidParameter(.sessionType))
            }
            return .success(.startBreak(type: type, presetId: activePresetId))

        case .pause: return .success(.pause)
        case .resume: return .success(.resume)
        case .skip: return .success(.skip)
        case .abort: return .success(.abort)
        case .extend: return .success(.extend)
        case .resetLoopCount: return .success(.resetLoopCount)

        case .confirmRestoredSession:
            guard let decision = params.decision else { return .failure(.missingParameter(.decision)) }
            switch decision {
            case .complete: return .success(.confirmRestoredSession(.complete))
            case .discard: return .success(.confirmRestoredSession(.discard))
            // 10.2: `resume` on the wire is `continueSession` inside.
            case .resume: return .success(.confirmRestoredSession(.continueSession))
            }

        case .selectTask:
            guard let stableId = params.stableId else { return .failure(.missingParameter(.stableId)) }
            return .success(.selectTask(snapshot: stableId))

        case .clearTaskSelection: return .success(.clearTaskSelection)
        case .reloadTasks: return .success(.reloadTasks)

        case .updateSettings:
            // REQ-CFG-018: a value this version cannot read is refused before anything is applied.
            if params.unreadableValues.contains(.settings) { return .failure(.valueOutOfRange(.settings)) }
            guard let settings = params.settings else { return .failure(.missingParameter(.settings)) }
            return .success(.updateSettings(settings))

        case .selectPreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter(.presetId)) }
            return .success(.selectPreset(id: presetId))

        case .createPreset:
            // REQ-CFG-018: a preset carries settings too, and `notificationSound` is one of them.
            if params.unreadableValues.contains(.preset) { return .failure(.valueOutOfRange(.preset)) }
            guard let preset = params.preset else { return .failure(.missingParameter(.preset)) }
            return .success(.createPreset(preset))

        case .duplicatePreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter(.presetId)) }
            return .success(.duplicatePreset(id: presetId))

        case .updatePreset:
            if params.unreadableValues.contains(.preset) { return .failure(.valueOutOfRange(.preset)) }
            guard let preset = params.preset else { return .failure(.missingParameter(.preset)) }
            return .success(.updatePreset(preset))

        case .deletePreset:
            guard let presetId = params.presetId else { return .failure(.missingParameter(.presetId)) }
            return .success(.deletePreset(id: presetId))

        case .reorderPresets:
            guard let orderedIds = params.orderedIds else { return .failure(.missingParameter(.orderedIds)) }
            return .success(.reorderPresets(order: orderedIds))

        case .restoreDefaultPreset:
            return .success(.restoreDefaultPreset)
        }
    }
}

// REQ-PRT-003: a resend carrying a clientRequestId already seen is ignored.
// Without idempotence, a resend just after reconnecting would extend twice, or move the loop
// count on by an extra step.
public struct RequestDeduplicator: Sendable {
    private var seen: [String] = []
    private var seenSet: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    // True for an id seen for the first time; false if it has been seen before, meaning: do not process it.
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
