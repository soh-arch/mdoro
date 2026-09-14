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
// **A number no type here can hold is the same kind of thing**, and reaches the same answer:
// `4.5` for an hour, a figure past `Int`, `-1` for a `UInt16`. It arrives by a different route —
// the JSON parser gives up on the literal before any of our types is asked for a value, and what
// it raises is not a `DecodingError` (`docs/platform/0012`) — a different kind of throw that
// lands in the same place. **A number that is merely malformed does not join them**
// (`01`, `1e`): those bytes are not a value at all, and REQ-ERR-009 has them discarded and
// counted.
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

// A whole preset, so the value under test is the only thing in it the decoder can trip on: a
// preset missing a field it cannot do without is a broken message, which is a different case.
private func presetJSON(sound: String = "chime", preNotifications: String = "[]") -> String {
    """
    "preset":{"id":"p1","name":"Standard","workSeconds":1500,"shortBreakSeconds":300,
     "longBreakSeconds":900,"longBreakInterval":4,"extendSeconds":300,"autoAdvance":false,
     "notificationSound":"\(sound)","timeSensitiveNotifications":false,
     "preNotifications":\(preNotifications),"isBuiltInDefault":false}
    """
}

// The two ways a settings value can be one this version cannot make a value of. On the wire each
// earns an answer; in the state file each has to keep throwing.
enum UnreadableSetting: CaseIterable, Sendable {
    case anEnumCaseThisVersionDoesNotHave
    case aNumberNoTypeHereCanHold

    var field: String {
        switch self {
        case .anEnumCaseThisVersionDoesNotHave: "appearance"
        case .aNumberNoTypeHereCanHold: "logicalDayStartHour"
        }
    }

    var value: Any {
        switch self {
        case .anEnumCaseThisVersionDoesNotHave: "sepia"
        case .aNumberNoTypeHereCanHold: 4.5
        }
    }
}

// A command whose settings carry `bytes` verbatim inside a JSON string. `commandJSON` cannot do
// this: a Swift `String` holds no byte sequence that is not UTF-8, so the bytes are spliced in
// where the `@` stands. `leadingFields` goes in front of the field, written out with its comma.
private func commandCarryingRawBytes(
    _ bytes: [UInt8], in field: String, after leadingFields: String = ""
) -> Data {
    let params = "\"settings\":{" + leadingFields + "\"" + field + "\":\"@\"}"
    let around = commandJSON(action: "updateSettings", params: params).components(separatedBy: "@")
    return Data(around[0].utf8) + Data(bytes) + Data(around[1].utf8)
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
        let preset = presetJSON(sound: "gamelan")
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
        let preset = presetJSON(preNotifications: #"[{"type":"atHalfway"}]"#)
        let command = try decodeCommand(commandJSON(action: "updatePreset", params: preset))
        #expect(command.params?.preset == nil)
        #expect(translate(command) == .failure(.valueOutOfRange(.preset)))
    }

    // REQ-CFG-018 / REQ-PRT-005: **a number no type here can hold is answered for like any other
    // value this version cannot make sense of.** `4.5` for an hour, a figure past `Int`, `-1` for
    // a `UInt16`. It used to take the whole command down: the parser gives up on the literal
    // before any of our types is asked to make a value of it, and what it raises is not a
    // `DecodingError` (`docs/platform/0012`), so the test for an unknown enum case never saw it —
    // and the iPhone waited on an answer REQ-CFG-018 requires.
    //
    // **`1e309` is here because the first fix did not reach it.** That fix asked Foundation to read
    // the field a second time as untyped JSON, and the second read gave up on `1e309` for the same
    // reason the first one did — nothing here is bounded by what a `Double` can hold, so the answer
    // stopped at ~1.8e308 and the message went back to being discarded (found in review, 2026-09-03).
    @Test func aNumberNoTypeHereCanHoldIsAnsweredForRatherThanDropped() throws {
        for params in [
            #""settings":{"logicalDayStartHour":4.5}"#,
            #""settings":{"logicalDayStartHour":99999999999999999999999}"#,
            // Past what a `Double` holds, which is where the answer used to stop.
            #""settings":{"logicalDayStartHour":1e309}"#,
            #""settings":{"logicalDayStartHour":1e400}"#,
            #""settings":{"logicalDayStartHour":-1e400}"#,
            #""settings":{"logicalDayStartHour":1e309000000000000000000}"#,
            // The last one a `Double` does hold: an hour is an `Int`, and no boundary of the
            // parser's is the boundary here.
            #""settings":{"logicalDayStartHour":1e308}"#,
            #""settings":{"pauseResumeHotKey":{"keyCode":-1,"modifierFlags":1048576,"displayName":"X"}}"#,
        ] {
            let command = try decodeCommand(
                commandJSON(action: "updateSettings", requestId: "r4", params: params)
            )
            // The answer is owed to this id, and the id survives because the value was read apart.
            #expect(command.clientRequestId == "r4")
            #expect(command.params?.unreadableValues == [.settings], "\(params)")
            // REQ-PRT-005 / REQ-CFG-013: nothing was put in its place.
            #expect(command.params?.settings == nil, "\(params)")

            guard case let .failure(failure) = translate(command) else {
                Issue.record("REQ-CFG-018: the command was accepted and the settings applied: \(params)")
                continue
            }
            #expect(failure == .valueOutOfRange(.settings))
            #expect(failure.protocolErrorCode == .settingOutOfRange)
        }
    }

    // 9.3 keeps the sound and the session lengths on the preset, so the same number arrives by the
    // other door too.
    @Test func aNumberNoTypeHereCanHoldIsAnsweredForOnThePresetItRodeIn() throws {
        let preset = presetJSON().replacingOccurrences(of: #""workSeconds":1500"#, with: #""workSeconds":1500.5"#)
        let command = try decodeCommand(commandJSON(action: "updatePreset", requestId: "r5", params: preset))
        #expect(command.clientRequestId == "r5")
        #expect(command.params?.unreadableValues == [.preset])
        #expect(command.params?.preset == nil)
        #expect(translate(command) == .failure(.valueOutOfRange(.preset)))
    }

    // REQ-PRT-005 / REQ-ERR-009: **a number that is not a number is still a broken message**, and
    // the parser raises the same error for it as for one that will not fit. The catch that answers
    // for the second must not be widened to the error type, or bytes nobody could read would come
    // back as "the setting is outside the allowed range". Reading the grammar off the message is
    // what keeps the two apart (`JSONWellFormedness`).
    //
    // **These reach the same clause the answered-for numbers do.** Measured 2026-09-03: the scanner
    // accepts a number-shaped run of bytes without reading it, so `01` gets as far inside
    // `CommandParams.init(from:)` as `1e309` does and raises the same thing there. Neither is
    // turned away earlier, which is why this test is about a line that is actually drawn.
    @Test func aMalformedNumberIsStillABrokenMessage() {
        for params in [
            #""settings":{"logicalDayStartHour":01}"#,
            #""settings":{"logicalDayStartHour":1e}"#,
            #""settings":{"logicalDayStartHour":1.2.3}"#,
            #""settings":{"logicalDayStartHour":.5}"#,
            #""settings":{"logicalDayStartHour":1.}"#,
            #""settings":{"logicalDayStartHour":+1}"#,
            #""settings":{"idleResetHours":--3}"#,
        ] {
            #expect(throws: (any Error).self, "\(params)") {
                try MessageCoder.decodeClient(Data(commandJSON(action: "updateSettings", params: params).utf8))
            }
        }
    }

    // REQ-PRT-005 / REQ-ERR-009: **a string that is not a string is a broken message too**, and it
    // arrives by the same door as a number that will not fit. An unpaired `\uD800` and a byte that
    // is not UTF-8 are refused where the value is made, not where the message is scanned, so the
    // grammar read off the bytes has to turn them down as well — or REQ-ERR-009's message would
    // come back as "the setting is outside the allowed range".
    @Test func aStringThatDoesNotDenoteAStringIsStillABrokenMessage() {
        for params in [
            #""settings":{"appearance":"\uD800"}"#,
            #""settings":{"appearance":"\uZZZZ"}"#,
            #""settings":{"appearance":"\q"}"#,
        ] {
            #expect(throws: (any Error).self, "\(params)") {
                try MessageCoder.decodeClient(Data(commandJSON(action: "updateSettings", params: params).utf8))
            }
        }
        let around = commandJSON(action: "updateSettings", params: #""settings":{"appearance":"@"}"#)
            .components(separatedBy: "@")
        var notUTF8 = Data(around[0].utf8)
        notUTF8.append(0xFF)
        notUTF8.append(contentsOf: Data(around[1].utf8))
        #expect(throws: (any Error).self) { try MessageCoder.decodeClient(notUTF8) }
    }

    // REQ-PRT-005 / REQ-ERR-009: **an unpaired surrogate is a broken message, in every shape it
    // comes in.** `aStringThatDoesNotDenoteAStringIsStillABrokenMessage` pins one of them, a
    // `\uD800` standing alone. RFC 8259 §7 lets a string spell a character outside the BMP only as
    // a high surrogate followed immediately by a low one, so there are several other ways to write
    // an escape that denotes no character — a low surrogate with nothing before it, a pair the
    // wrong way round, a debt paid to something that is not a low surrogate — and none of them is
    // a value REQ-CFG-018 owes an answer to.
    //
    // **What this measures is whether the grammar is read before any of them is answered for.**
    // `CommandParams.value` asks `JSONWellFormedness` of every throw it is willing to treat as a
    // value, whichever kind it is, so a broken character cannot come back as "the setting is
    // outside the allowed range" by arriving as one kind rather than the other. It did not always:
    // the clause for a `DecodingError` used to answer on the error alone, and the test below this
    // one is the one that caught it (REQ-ERR-009).
    @Test func anUnpairedSurrogateInASettingIsStillABrokenMessage() {
        for params in [
            // A high surrogate owed a low one that never comes.
            #""settings":{"appearance":"\uD83D"}"#,
            #""settings":{"displayName":"\uD800"}"#,
            #""settings":{"logFileName":"\uDBFF"}"#,
            // A low surrogate with no high surrogate in front of it.
            #""settings":{"appearance":"\uDC00"}"#,
            #""settings":{"displayName":"\uDE00"}"#,
            // The debt is owed to the very next escape, and these pay it to something else.
            #""settings":{"displayName":"\uD800\n"}"#,
            #""settings":{"displayName":"\uD800A"}"#,
            #""settings":{"displayName":"\uD83D\uD83D"}"#,
            #""settings":{"displayName":"a\uD83Db"}"#,
            // A pair written back to front. Kept for the shape, not for a branch of its own:
            // a review read `scanString` and found the low surrogate turned down where it
            // stands, so whatever follows is never reached — the line above already covers
            // it. Whether Foundation's own decoder splits them is not known here.
            #""settings":{"displayName":"\uDE00\uD83D"}"#,
        ] {
            #expect(throws: (any Error).self, "\(params)") {
                try MessageCoder.decodeClient(Data(commandJSON(action: "updateSettings", params: params).utf8))
            }
        }
    }

    // REQ-PRT-005 / REQ-ERR-009: **bytes that spell no character are a broken message too.**
    // `aStringThatDoesNotDenoteAStringIsStillABrokenMessage` pins a single `0xFF`, which is never
    // UTF-8 anywhere. These are the shapes that look more like text — a sequence cut short, a
    // continuation byte on its own, an overlong encoding, a surrogate spelled out in UTF-8, a
    // scalar past the last one there is. A reader that asks only `String(data:encoding:.utf8)`
    // turns all of them down, so what this holds in place is that the question is asked at all
    // before the value is answered for.
    @Test func aByteSequenceThatDenotesNoCharacterIsStillABrokenMessage() {
        let denotesNoCharacter: [[UInt8]] = [
            [0x80],                     // a continuation byte with no lead in front of it
            [0xC3],                     // the lead of a two-byte sequence, and nothing follows
            [0xE3, 0x81],               // a three-byte sequence one byte short
            [0xF0, 0x9F, 0x98],         // a four-byte sequence one byte short
            [0xC0, 0x80],               // U+0000 written the long way, which UTF-8 forbids
            [0xED, 0xA0, 0x80],         // U+D800 spelled in UTF-8, which UTF-8 also forbids
            [0xF5, 0x80, 0x80, 0x80],   // past U+10FFFF
            [0xFE, 0xFF],               // bytes UTF-8 never uses
        ]
        for bytes in denotesNoCharacter {
            #expect(throws: (any Error).self, "\(bytes)") {
                try MessageCoder.decodeClient(commandCarryingRawBytes(bytes, in: "displayName"))
            }
        }
    }

    // REQ-ERR-009: **a raw control character is refused for a different reason, so it is named
    // separately.** `0x0A` is perfectly good UTF-8 — it spells U+000A — so nothing about the
    // character is wrong, and it does not belong under a name that says otherwise. What is wrong
    // is the grammar: JSON requires a control character inside a string to be written as an
    // escape, and `scanString` turns down every byte below `0x20`. It was filed beside the bytes
    // above until a review read the name against what it was holding.
    @Test func aRawControlCharacterInAStringIsStillABrokenMessage() {
        #expect(throws: (any Error).self) {
            try MessageCoder.decodeClient(commandCarryingRawBytes([0x0A], in: "displayName"))
        }
    }

    // REQ-PRT-005 / REQ-ERR-009: **a broken character is not made readable by a value that fails
    // before it.** The two tests before this one put the broken bytes where they are the first
    // thing in the settings that cannot be read, and the reading stops on them. Here something
    // else stops it first: `appearance` is the field `AppSettings.init(from:)` asks for first, and
    // `"sepia"` is an enum case this version does not have, so it raises `dataCorrupted` while the
    // broken character is still further down the object, unread.
    //
    // **It used to be answered for.** That clause took `dataCorrupted` as a value on the strength
    // of the error alone and never read the grammar, so a message carrying bytes that denote no
    // character came back as "the setting is outside the allowed range" — where REQ-ERR-009 has it
    // discarded and counted. Measured on 2026-09-14, failing at both forms; the clause now asks
    // the same question of every throw it is willing to treat as a value.
    //
    // **Nothing about this is particular to characters.** The reading stops at the first field
    // that fails, so a malformed number sitting behind one would have gone the same way. That has
    // not been measured.
    @Test func aBrokenCharacterBesideAValueWeCannotReadIsStillABrokenMessage() {
        #expect(throws: (any Error).self) {
            try MessageCoder.decodeClient(Data(commandJSON(
                action: "updateSettings",
                params: #""settings":{"appearance":"sepia","displayName":"\uD800"}"#
            ).utf8))
        }
        #expect(throws: (any Error).self) {
            try MessageCoder.decodeClient(
                commandCarryingRawBytes([0xFF], in: "displayName", after: #""appearance":"sepia","#)
            )
        }
    }

    // REQ-PRT-005 / REQ-ERR-009: **the answer is owed to a value, not to a shape.** A field of the
    // wrong type does not say a value cannot be applied — it says the message does not hold
    // together. Nothing can be made of it, so it stays a broken message, discarded and counted
    // rather than answered.
    @Test func aFieldOfTheWrongShapeIsStillABrokenMessage() {
        for params in [#""settings":{"logicalDayStartHour":"four"}"#, #""settings":42"#] {
            #expect(throws: DecodingError.self) {
                try MessageCoder.decodeClient(Data(commandJSON(action: "updateSettings", params: params).utf8))
            }
        }
    }

    // REQ-PRT-005: **a field this action does not use is spare, and a spare field is ignored** —
    // the same way the clause has an unknown field ignored. Reading `settings` apart from the rest
    // of the command is what makes that true here: a `pause` used to be thrown away whole because
    // of a value it was never going to look at. Nothing is applied and nothing is refused.
    @Test func aValueRidingAnActionThatDoesNotUseItIsSpareRatherThanFatal() throws {
        let paused = try decodeCommand(
            commandJSON(action: "pause", params: #""settings":{"appearance":"sepia"}"#)
        )
        #expect(paused.params?.unreadableValues == [.settings])
        #expect(translate(paused) == .success(.pause))

        let started = try decodeCommand(
            commandJSON(action: "startWork", params: presetJSON(sound: "gamelan"))
        )
        #expect(started.params?.unreadableValues == [.preset])
        #expect(translate(started) == .success(.startWork(presetId: "p1", taskSnapshot: nil)))
    }

    // REQ-CFG-018: a number outside its range reads perfectly well — it is the range that refuses
    // it (`isWithinValidRanges`), and that path is untouched by the reading above. The shared
    // translator converts shapes and decides nothing about ranges, so it hands the command on;
    // the Mac never asks it about settings anyway. **Where the range refuses is `AppModel`**, and
    // the test after this one is what pins it.
    @Test func aNumberOutsideItsRangeStillReadsAndIsStillOutOfRange() throws {
        let command = try decodeCommand(
            commandJSON(action: "updateSettings", params: #""settings":{"logicalDayStartHour":23}"#)
        )
        let settings = try #require(command.params?.settings)
        #expect(settings.logicalDayStartHour == 23, "a value with a case here is read as it arrived")
        #expect(command.params?.unreadableValues.isEmpty == true)
        #expect(!settings.isWithinValidRanges(), "REQ-CFG-018: 9.3 allows 0 to 12")
        #expect(translate(command) == .success(.updateSettings(settings)))
    }

    // REQ-CFG-018: **the range has to answer, not just refuse.** The value was already kept out —
    // `didSet` puts the old settings back when the range turns the new ones down — but it did that
    // with no request in hand, so the iPhone got nothing back at all for the command it sent. The
    // answer is owed to a `clientRequestId`, and only `apply` still has one.
    @Test func theMacAnswersForANumberOutsideItsRangeBeforeItIsApplied() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        let block = try #require(appModel.components(separatedBy: "case .updateSettings:").last)
        let range = try #require(
            block.range(of: "isWithinValidRanges()"),
            "REQ-CFG-018: an out-of-range number is applied, or refused with no answer sent"
        )
        let refusal = try #require(
            block.range(of: "valueOutOfRange(.settings)", range: range.upperBound..<block.endIndex),
            "REQ-CFG-018: the range turns the value down without settingOutOfRange going back"
        )
        let application = try #require(block.range(of: "settings = updated"))
        #expect(refusal.upperBound < application.lowerBound, "the answer comes after the value is applied")
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

    // REQ-CFG-018 / REQ-UIX-033 / 9.3: **"contains at least one modifier" is a range too.** A
    // binding without one reads perfectly well — every field has a case here and the flags are a
    // number the type holds — so it arrives whole, the way a number outside 0–12 does, and it is
    // `isWithinValidRanges()` that turns it down. `theMacAnswersForANumberOutsideItsRangeBeforeItIsApplied`
    // and `theMacRefusesTheValueBeforeItIsApplied` pin where the answer is sent from, and that
    // gate asks the one question for the whole of `AppSettings`.
    @Test func aShortcutWithNoModifierStillReadsAndIsStillOutOfRange() throws {
        let command = try decodeCommand(
            commandJSON(
                action: "updateSettings",
                requestId: "r9",
                params: #""settings":{"pauseResumeHotKey":{"keyCode":35,"modifierFlags":0,"displayName":"P"}}"#
            )
        )
        // The answer is owed to this id, and the value read whole, so the id is still here.
        #expect(command.clientRequestId == "r9")
        #expect(command.params?.unreadableValues.isEmpty == true)
        let settings = try #require(command.params?.settings)
        #expect(settings.pauseResumeHotKey?.modifierFlags == 0, "a value with a case here is read as it arrived")
        #expect(!settings.isWithinValidRanges(), "REQ-CFG-018 / 9.3: a shortcut carries a modifier")
        // The shared translator decides nothing about ranges, and the Mac never asks it about
        // settings: it hands the command on exactly as it does for an out-of-range number.
        #expect(translate(command) == .success(.updateSettings(settings)))
    }

    // REQ-ERR-017 / Decision 0036: **the state file reads the same types and must keep throwing.**
    // Reading it leniently would call an unreadable file understood, and the next save would write
    // over the very bytes the reader is told to go and fetch.
    @Test(arguments: UnreadableSetting.allCases)
    func aStateFileCarryingSuchAValueIsStillSetAsideRatherThanRead(_ setting: UnreadableSetting) throws {
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
        settings[setting.field] = setting.value
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
