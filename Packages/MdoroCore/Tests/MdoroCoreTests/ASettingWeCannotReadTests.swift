import Testing
import Foundation
@testable import MdoroCore

// REQ-CFG-018 / REQ-PRT-005: **a setting whose value this version has no case for is out of
// range, and out of range is answered for.**
//
// `updateSettings` carrying `{"appearance":"sepia"}` used to take the whole command down with it:
// the value threw on the way in, `decodeClient` dropped the message, and the iPhone waited on an
// answer that REQ-CFG-018 requires. The `clientRequestId` the answer has to name sat inside the
// very object that failed to read, which is why the two values a command can carry a setting in
// — `settings` and `preset` — are read apart from the rest of it.
//
// **The value is refused, not stood in for.** REQ-PRT-005 forbids bending an unknown value onto a
// case it resembles, and REQ-CFG-013 forbids a setting changing without the reader being told; a
// default put in its place would do both at once.
//
// The state file is the other reader of these same types, and it must keep throwing: Decision 0036
// and REQ-ERR-017 set an unreadable file aside rather than write over it, and a lenient read would
// call the file understood and save on top of what was in it.

private func decodeCommand(_ json: String) throws -> CommandPayload {
    let decoded = try #require(try MessageCoder.decodeClient(Data(json.utf8)))
    guard case let .command(payload) = decoded.body else {
        throw DecodedSomethingElse(what: decoded.body.typeName)
    }
    return payload
}

private struct DecodedSomethingElse: Error, CustomStringConvertible {
    let what: String
    var description: String { "expected a command, got \(what)" }
}

// A `command` envelope carrying the given params object verbatim.
private func commandJSON(action: String, requestId: String = "r1", params: String) -> String {
    """
    {"type":"command","messageId":"m1","sentAt":"2023-11-14T22:13:20Z",
     "clientRequestId":"\(requestId)","action":"\(action)","params":{\(params)}}
    """
}

private func translate(_ command: CommandPayload) -> Result<TimerAction, CommandTranslation.Failure> {
    CommandTranslation.action(for: command, activePresetId: "p1", selectedTaskSnapshot: nil)
}

@Suite("A setting we cannot read still gets an answer (REQ-CFG-018 / REQ-PRT-005)")
struct ASettingWeCannotReadTests {

    @Test func anAppearanceWithNoCaseHereIsRefusedRatherThanDroppedInSilence() throws {
        let command = try decodeCommand(
            commandJSON(action: "updateSettings", params: #""settings":{"appearance":"sepia"}"#)
        )

        // The answer is owed to this id, and the id survives because the value was read apart.
        #expect(command.clientRequestId == "r1")
        #expect(command.params?.unreadableValues == [.settings])
        // REQ-PRT-005 / REQ-CFG-013: nothing was put in its place.
        #expect(command.params?.settings == nil, "the unknown value was bent onto a case this version knows")

        guard case let .failure(failure) = translate(command) else {
            Issue.record("REQ-CFG-018: the command was accepted and the settings applied")
            return
        }
        #expect(failure == .valueOutOfRange(.settings))
        #expect(failure.protocolErrorCode == .settingOutOfRange)
    }

    @Test func aMenuBarDisplayModeWithNoCaseHereIsRefusedTheSameWay() throws {
        let command = try decodeCommand(
            commandJSON(action: "updateSettings", requestId: "r2",
                        params: #""settings":{"menuBarDisplayMode":"stopwatch"}"#)
        )

        #expect(command.clientRequestId == "r2")
        #expect(command.params?.settings == nil)
        #expect(translate(command) == .failure(.valueOutOfRange(.settings)))
    }

    // 9.3 keeps the sound on the preset, so the same value arrives by a different door.
    @Test func aNotificationSoundWithNoCaseHereIsRefusedOnThePresetItRodeIn() throws {
        let preset = """
        "preset":{"id":"p1","name":"Standard","workSeconds":1500,"shortBreakSeconds":300,
         "longBreakSeconds":900,"longBreakInterval":4,"extendSeconds":300,"autoAdvance":false,
         "notificationSound":"gamelan","timeSensitiveNotifications":false,
         "preNotifications":[],"isBuiltInDefault":false}
        """
        for action in ["updatePreset", "createPreset"] {
            let command = try decodeCommand(commandJSON(action: action, requestId: "r3", params: preset))
            #expect(command.clientRequestId == "r3")
            #expect(command.params?.preset == nil, "\(action) applied a sound this version cannot play")
            let failure = translate(command)
            #expect(failure == .failure(.valueOutOfRange(.preset)))
        }
    }

    // The same shape one level further down: 10.3 writes a pre-notification's kind as a value too.
    @Test func aPreNotificationKindWithNoCaseHereIsRefusedRatherThanDropped() throws {
        let preset = """
        "preset":{"id":"p1","name":"Standard","workSeconds":1500,"shortBreakSeconds":300,
         "longBreakSeconds":900,"longBreakInterval":4,"extendSeconds":300,"autoAdvance":false,
         "notificationSound":"chime","timeSensitiveNotifications":false,
         "preNotifications":[{"type":"atHalfway"}],"isBuiltInDefault":false}
        """
        let command = try decodeCommand(commandJSON(action: "updatePreset", params: preset))
        #expect(command.params?.preset == nil)
        #expect(translate(command) == .failure(.valueOutOfRange(.preset)))
    }

    // REQ-PRT-005 / REQ-ERR-009: **the exemption is for a value, not for a shape.** A field of the
    // wrong type is not an unknown value — nothing can be made of the message, so it stays a
    // broken one, discarded and counted rather than answered.
    @Test func aFieldOfTheWrongShapeIsStillABrokenMessage() {
        for params in [#""settings":{"logicalDayStartHour":"four"}"#, #""settings":42"#] {
            #expect(throws: DecodingError.self) {
                try MessageCoder.decodeClient(Data(commandJSON(action: "updateSettings", params: params).utf8))
            }
        }
    }

    // REQ-CFG-018: a number outside its range reads perfectly well — it is the range that refuses
    // it (`isWithinValidRanges`), and that path is untouched by the reading above.
    @Test func aNumberOutsideItsRangeStillReadsAndIsStillOutOfRange() throws {
        let command = try decodeCommand(
            commandJSON(action: "updateSettings", params: #""settings":{"logicalDayStartHour":23}"#)
        )
        let settings = try #require(command.params?.settings)
        #expect(settings.logicalDayStartHour == 23, "a value with a case here is read as it arrived")
        #expect(command.params?.unreadableValues.isEmpty == true)
        #expect(!settings.isWithinValidRanges(), "REQ-CFG-018: 9.3 allows 0 to 12")
        // It is a readable command, so it reaches the state machine; the range is what stops it.
        #expect(translate(command) == .success(.updateSettings(settings)))
    }

    // REQ-CFG-018: the refusal has to name the request that carried the value, and on the Mac that
    // command never reaches `CommandTranslation` — `AppModel` takes settings in itself. **Refusing
    // after the assignment would be too late**: the value is applied by `didSet` on the way in.
    @Test func theMacRefusesTheValueBeforeItIsApplied() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        let block = try #require(appModel.components(separatedBy: "case .updateSettings:").last)
        let refusal = try #require(
            block.range(of: "valueOutOfRange(.settings)"),
            "REQ-CFG-018: a value the Mac cannot read is applied, or answered for nowhere"
        )
        let application = try #require(block.range(of: "settings = updated"))
        #expect(refusal.upperBound < application.lowerBound, "the refusal comes after the value is applied")

        // Every refusal the Mac raises itself is tied to the request that caused it.
        let payloads = appModel.components(separatedBy: "ProtocolErrorPayload(").dropFirst()
        #expect(!payloads.isEmpty)
        for payload in payloads {
            #expect(
                payload.prefix(200).contains("relatedRequestId: command.clientRequestId"),
                "10.2: an error goes back with no request to tie it to"
            )
        }
    }

    // REQ-ERR-017 / Decision 0036: **the state file reads the same types and must keep throwing.**
    // Reading it leniently would call an unreadable file understood, and the next save would write
    // over the very bytes the reader is told to go and fetch.
    @Test func aStateFileCarryingSuchAValueIsStillSetAsideRatherThanRead() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MdoroUnreadableSetting-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = FileStateStore(fileURL: url)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(PersistedState.initial(now: now))
        var object = try #require(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        var settings = try #require(object["settings"] as? [String: Any])
        settings["appearance"] = "sepia"
        object["settings"] = settings
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        #expect(throws: StateStoreError.corrupted) { try store.load() }

        // REQ-ERR-017: set aside, not overwritten, and saving may go on from a clean state.
        let startup = store.loadForStartup(now: now)
        #expect(startup.saved == nil)
        #expect(startup.readFailure == .corrupted)
        #expect(startup.setAsideAt != nil, "Decision 0036: the file was left where the next save will land on it")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(startup.mayPersist)
    }
}
