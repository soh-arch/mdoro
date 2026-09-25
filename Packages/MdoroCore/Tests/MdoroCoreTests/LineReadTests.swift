import Testing
import Foundation
import MdoroCore

// REQ-COM-004 / REQ-PRT-001: **every way a line can be over, and what each end's reading loop does
// about it.**
//
// This suite sits beside the judgement in `MdoroCore`, not in `MdoroiOSTests` next to one end of
// it. That placement is the point: both ends ask this one function, so one suite answers for both,
// and a Mac read loop that lets every ending through is a failure this can see.
//
// **It also has to be somewhere that runs.** The iOS suites need a simulator and nothing in CI
// starts one (`.claude/orchestrator.md` §8); `swift test` runs on every pull request.
//
// What hangs on the answers: on the iPhone the reconnect hangs off the line's ending and nothing
// else reaches it (REQ-COM-004), and on the Mac an ending not heard here is a connection believed
// in until the silence watch expires fifteen seconds later (REQ-COM-005), re-armed into all the
// while. **What this suite cannot say is that either loop then stops asking** — that is between
// `receive()` and the transport, and an `NWConnection` dials the moment it is started, so no test
// in this project stands there.
@Suite("What one read off the line means (REQ-COM-004)")
struct LineReadTests {

    private let payload = Data(#"{"v":1,"type":"heartbeat"}"#.utf8)

    // MARK: - What is carried up

    @Test func aTextFrameIsAProtocolMessage() {
        #expect(LineRead.of(data: payload, frame: .text, isComplete: true, failed: false)
                == .message(payload))
    }

    @Test func aBinaryFrameIsAProtocolMessage() {
        #expect(LineRead.of(data: payload, frame: .binary, isComplete: true, failed: false)
                == .message(payload))
    }

    // **This is the one that says why `isComplete` cannot be read as an ending on its own.** On a
    // message-oriented protocol it is true of every whole message, so a loop that ended the line
    // whenever it saw it would hang up on the first thing the peer ever said.
    @Test func aCompletedReadCarryingAMessageIsNotAnEnding() {
        #expect(LineRead.of(data: payload, frame: .text, isComplete: true, failed: false)
                != .end)
    }

    // MARK: - The endings

    // The ending the state handler never tells. A peer that closes politely leaves the connection
    // `.ready`: no `.failed`, no `.cancelled`, and nothing said anywhere except here.
    @Test func aCloseFrameEndsTheLine() {
        #expect(LineRead.of(data: nil, frame: .close, isComplete: true, failed: false) == .end)
    }

    // A close frame may carry a status code and a reason as its payload. It is still an ending.
    @Test func aCloseFrameWithAPayloadEndsTheLine() {
        #expect(LineRead.of(data: Data([0x03, 0xE8]), frame: .close, isComplete: true, failed: false)
                == .end)
    }

    @Test func aReadThatFailedEndsTheLine() {
        #expect(LineRead.of(data: nil, frame: nil, isComplete: false, failed: true) == .end)
    }

    // The end of the line as the transport reports it when there was no close frame to hand over:
    // the read completes, and nothing came with it.
    @Test func aCompletedReadWithNothingOnItEndsTheLine() {
        #expect(LineRead.of(data: nil, frame: nil, isComplete: true, failed: false) == .end)
        #expect(LineRead.of(data: Data(), frame: nil, isComplete: true, failed: false) == .end)
    }

    // MARK: - What must not be read as an ending

    // The transport answers pings by itself (`NWProtocolWebSocket.Options.autoReplyPing`). One
    // reaching this far is proof the peer is on the other end, and nothing more.
    @Test func aPingOrAPongIsNeitherAMessageNorAnEnding() {
        #expect(LineRead.of(data: nil, frame: .ping, isComplete: true, failed: false) == .skip)
        #expect(LineRead.of(data: nil, frame: .pong, isComplete: true, failed: false) == .skip)
    }

    // A frame kind neither end has anything to say about — a continuation, or one a later SDK adds.
    // **It is not an ending**: `.other` is where every opcode that is not one of the five named ones
    // lands, so reading it as an ending would hang up the line on the first one that ever arrived.
    @Test func aFrameKindThisLayerHasNothingToSayAboutIsNotAnEnding() {
        #expect(LineRead.of(data: nil, frame: .other, isComplete: true, failed: false) == .skip)
        #expect(LineRead.of(data: payload, frame: .other, isComplete: true, failed: false) == .skip)
    }

    // **A read carrying bytes is never an ending**, whatever the frame around it turned out to be.
    // Handing nothing up costs one message; hanging up costs the connection.
    @Test func aReadCarryingBytesIsNotAnEnding() {
        #expect(LineRead.of(data: payload, frame: nil, isComplete: true, failed: false) == .skip)
    }

    // An empty text frame is not a protocol message — `MessageCoder` has nothing to read — but the
    // line is fine.
    @Test func anEmptyTextFrameIsNeitherAMessageNorAnEnding() {
        #expect(LineRead.of(data: Data(), frame: .text, isComplete: true, failed: false) == .skip)
    }

    // **The one case that holds `isComplete` in the condition at all.** Every other read here is
    // either complete or failed, so drop `isComplete` from the ending above and the rest of this
    // suite goes on passing while a read that has not finished and has nothing yet becomes an
    // ending. The mark is that the read is *over* and nothing came with it; a read that is not
    // over has said nothing either way, and the line stands.
    @Test func aReadThatHasNotCompletedIsNotAnEnding() {
        #expect(LineRead.of(data: nil, frame: nil, isComplete: false, failed: false) == .skip)
        #expect(LineRead.of(data: Data(), frame: nil, isComplete: false, failed: false) == .skip)
    }

    // MARK: - The order the three endings are asked in

    // **A failed read is an ending whatever came with it.** The error is asked about before
    // anything else, so bytes that arrived alongside one are not handed up as a message on a line
    // that is already gone.
    @Test func aReadThatFailedIsAnEndingEvenCarryingBytes() {
        #expect(LineRead.of(data: payload, frame: .text, isComplete: true, failed: true) == .end)
    }
}
