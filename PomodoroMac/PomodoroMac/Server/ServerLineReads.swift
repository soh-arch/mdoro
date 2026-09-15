import Foundation
import Network

// REQ-COM-004: one read off an open line, in the four values `NWConnection.receiveMessage` hands
// over. They are passed on untouched: **what a read means is `LineRead.of`'s to say**
// (REQ-PRT-001, in `MdoroCore`, asked by both ends), and this seam has no opinion about any of
// them. Naming them here rather than deciding them here is the whole of the difference between a
// seam under the call and a seam under the judgement.
typealias ServerLineRead = @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void

// REQ-COM-004: **the one call in the Mac's read loop that reaches the transport.**
//
// Two things happen in `MdoroServer.receive(on:counting:)` when a read says the line is over, and
// neither could be observed from outside: the connection is handed back (`cancel()`) rather than
// merely let go of, and the loop stops asking for reads. An `NWConnection` dials the moment it is
// started, so there was nowhere to stand and hand that loop a read — the same reason
// `ClientLinkMaking` exists on the iPhone's side, and the same shape: a protocol, a real
// implementation that is the default, and a substitute chosen where the server is built.
//
// **It is one call wide on purpose.** `send`, `cancel` and `stateUpdateHandler` stay the
// connection's own, and an `NWConnection` is still what is passed everywhere a line is passed —
// `handleDisconnect` tells one line from another by identity, and a stand-in for the whole of
// `NWConnection` would be a far larger change than the one thing that could not be reached.
protocol ServerLineReading: Sendable {
    @MainActor
    func read(from connection: NWConnection, completion: @escaping ServerLineRead)
}

// Nothing is held here, and it is built where the server is built — off the main actor as readily
// as on it, the same as `WebSocketLinks` on the iPhone's side.
nonisolated struct WebSocketLineReads: ServerLineReading {
    @MainActor
    func read(from connection: NWConnection, completion: @escaping ServerLineRead) {
        connection.receiveMessage(completion: completion)
    }
}
