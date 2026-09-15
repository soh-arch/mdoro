import Foundation

// REQ-PRT-001: **the frame kinds a WebSocket read can carry, named without Network.framework in
// them.**
//
// `MessageLink` keeps this package's vocabulary to `Data`, and that is still the rule for what
// travels on a line. This is the one thing about the transport that both ends must answer the same
// way — whether a given read is a message, a nothing, or the end — and answering it needs to know
// what frame the read came in. Naming the kinds here is what lets the answer be shared; importing
// `NWProtocolWebSocket.Opcode` instead would put Network.framework under every target that links
// this package, which is a different package from the one this is.
//
// **Each end maps its own opcode onto these** (`LineFrame.init(_:)`, once in `MdoroMac` and once in
// `MdoroiOS`). That mapping is the only part that is written twice, and it is a list of five names.
public enum LineFrame: Sendable, Equatable {
    case text
    case binary
    case close
    case ping
    case pong
    // A frame kind this layer has nothing to say about: a continuation, or one a later SDK adds.
    // It is neither a message nor an ending.
    case other
}

// REQ-COM-004: **what one read off an open line means, decided apart from the reading itself.**
//
// **It is separated so it can be answered without a LAN.** An `NWConnection` dials the moment it is
// started, so while this decision lived inside a read callback there was nowhere to stand and ask
// it — the same reason `MessageLink` exists at all.
//
// REQ-PRT-001: **and it is shared so that the two ends cannot drift into answering it differently.**
// The iPhone's half was written first, in `WebSocketLink`; the Mac's read loop had no such decision
// at all and let every ending through, and the Mac's own test harness had a third answer again. A
// read is one fact, and a fact the two ends read by different rules is what this clause is for.
public enum LineRead: Sendable, Equatable {
    // A protocol message arrived. Hand it up, then read again.
    case message(Data)
    // Something arrived that this layer has nothing to say about: a ping the transport answered by
    // itself, a frame carrying no payload. Read again.
    case skip
    // Nothing more will arrive on this line. **Do not read again.**
    case end

    // REQ-COM-004: **a line that is over has to say so here as well.**
    //
    // The state handler does not see every ending: a peer that closes politely leaves the
    // connection `.ready`, so no `.failed` and no `.cancelled` follow and the read is the only
    // place the ending is told. What each end loses by missing it differs, and neither is small.
    // The iPhone's reconnect hangs off the ending and nothing else reaches it (REQ-COM-004), so an
    // ending never told is a phone sitting on a dead line for as long as the app runs. The Mac has
    // no reconnect of its own, but it goes on believing in a connection that is gone until the
    // silence watch expires fifteen seconds later (REQ-COM-005) — and in the meantime the loop
    // re-arms into a read that completes with nothing at once, on the main actor, for the whole of
    // those fifteen seconds.
    //
    // Three endings, asked in this order:
    //
    // 1. **A read that failed.** Whatever it was, nothing more is coming.
    // 2. **A close frame.** The polite ending above. It ends the line whether or not it carries a
    //    status code as its payload.
    // 3. **A completed read with no frame on it and no bytes** — the end of the line as the
    //    transport reports it when there was no close frame to hand over.
    //
    // **The third asks for all three of completed, unframed and empty.** On a message-oriented
    // protocol `isComplete` is true of every whole message, so on its own it would end the line at
    // the first thing the peer ever said; and without it, a read that has not finished and has
    // nothing yet would be read as an ending. What marks an ending is that the read is over and
    // nothing came with it, and a read carrying bytes is never read as one.
    //
    // **The third asks for no frame, not for a context that says it is the last one.** Those are
    // different properties, and a read that arrives with no context at all satisfies the first and
    // not the second — which is the read this is most likely to be asked about.
    public static func of(
        data: Data?, frame: LineFrame?, isComplete: Bool, failed: Bool
    ) -> LineRead {
        if failed { return .end }
        if frame == .close { return .end }
        if let data, !data.isEmpty, frame == .text || frame == .binary { return .message(data) }
        if isComplete, frame == nil, data?.isEmpty ?? true { return .end }
        return .skip
    }
}
