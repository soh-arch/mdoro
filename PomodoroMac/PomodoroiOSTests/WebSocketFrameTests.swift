import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroiOS

// REQ-PRT-001: **the half of the shared reading that had to be written twice.**
//
// `LineRead.of` decides what one read off a line means, and it lives in `MdoroCore` where one suite
// answers for both ends. What could not go with it is the translation from
// `NWProtocolWebSocket.Opcode`: `MdoroCore` imports Network.framework nowhere, and putting it there
// would put Network.framework under everything that links the package. So `WebSocketFrames.swift`
// exists once in `MdoroiOS` and once in `MdoroMac`, saying the same five things.
//
// **Those files tell the reader to change one and read the other. That is a sentence, and a
// sentence holds nothing** — it is the shape this repository has been caught by more than once.
// This table is what holds it. Its twin is `MdoroMacTests/WebSocketFrameTests`, the two ask exactly
// the same question of their own target's copy, and one entry changed on one side fails on that
// side. Neither suite can see the other's copy; nothing in one module can.
//
// **What this cannot ask: the `default` arm.** Reaching it means naming an opcode outside these
// five — `.cont`, or whatever else the SDK carries — and this project has not established those
// names. #108 left `.cont` out of its own tests for the same reason, and guessing one here would
// be a test that says more about the guess than about the mapping (`docs/PLATFORM.md`: an
// unverified fact is not something to build on). **A case dropped from the five is still caught**,
// because it falls through to `default` and comes back `.other` instead of its own name.
@Suite("The opcode each end translates for itself (REQ-PRT-001)")
struct WebSocketFrameTests {

    // **The whole table in one place**, so that a single entry changed, swapped or deleted fails
    // here rather than in whatever the line was carrying at the time.
    private let table: [(NWProtocolWebSocket.Opcode, LineFrame)] = [
        (.text, .text),
        (.binary, .binary),
        (.close, .close),
        (.ping, .ping),
        (.pong, .pong),
    ]

    @Test func everyOpcodeThisEndNamesKeepsItsName() {
        for (opcode, expected) in table {
            #expect(LineFrame(opcode) == expected,
                    "REQ-PRT-001: this target translates \(opcode) to \(LineFrame(opcode)) where the shared reading expects \(expected). The judgement in MdoroCore is one function, but the opcode it is asked about is translated once per target — so the two ends can still come apart here, and this is the only place that says so.")
        }
    }

    // **What the table means for the reading it feeds.** Each of the five carries its own weight in
    // `LineRead.of`: `.close` is an ending on its own (REQ-COM-004), `.text` and `.binary` are the
    // only two that hand a message up, and `.ping` / `.pong` must be neither. A mapping that is
    // merely self-consistent is not enough — it has to land each opcode where the shared reading
    // then puts it, which is what these three say.
    @Test func theFiveLandWhereTheSharedReadingPutsThem() {
        let payload = Data(#"{"v":1}"#.utf8)
        #expect(LineRead.of(data: nil, frame: LineFrame(.close), isComplete: true, failed: false)
                == .end,
                "REQ-COM-004: a close frame read through this target's translation is not an ending, so the one ending the connection's state handler never reports would be read through")
        #expect(LineRead.of(data: payload, frame: LineFrame(.text), isComplete: true, failed: false)
                == .message(payload),
                "REQ-COM-004: a text frame read through this target's translation does not hand its bytes up, so nothing this peer says is heard")
        #expect(LineRead.of(data: nil, frame: LineFrame(.ping), isComplete: true, failed: false)
                == .skip,
                "REQ-COM-004: a ping read through this target's translation is not skipped. The transport answers pings itself; reading one as an ending hangs up a healthy line, and reading it as a message hands nothing up as something")
    }
}
