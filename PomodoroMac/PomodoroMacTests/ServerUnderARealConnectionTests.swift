import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroMac

// REQ-COM-005 / REQ-SEC-003: **`MdoroServer` driven over a line that really carries bytes.**
//
// Three of the cases in `handle(_:from:)` — `.command`, `.requestSnapshot` and `.heartbeat` —
// begin with `guard source === connection`. They are the whole of what keeps anyone else who can
// reach the port from driving the timer, reading the task the user is working on, or holding the
// authenticated connection's liveness clock open. **A `heartbeat` carries no token and no body,
// so sending one takes nothing but the port.** Until this file there was no test on any of the
// three: the gate could be deleted and both suites stayed green.
//
// Two of the four legs REQ-COM-005 stands on are the Mac's, and they were unverified for the same
// reason — `MdoroServer` holds its own `NWConnection`, so nothing reached it without a wire.
//
// **What this puts on the machine, and what it does not.** One ephemeral TCP listener per test on
// the loopback interface, and one or two client connections of this test's own against it, all
// cancelled before the test returns. **`advertise` is never called**, so nothing is registered
// with Bonjour and no name of the reader's goes on the LAN — the same line `ListenerFoldingTests`
// draws. The listener takes whatever port the kernel hands it, so two of these running at once
// cannot collide over a port or a name.
//
// **Nothing here waits on a length of time.** Every wait is for an arrival and returns the moment
// it happens; the bounds exist so that a broken run fails instead of hanging.
//
// MARK: - How "it did not happen" is observed
//
// The gates are refusals: the server is meant to do *nothing* with a message from a connection
// that is not the authenticated one. Send such a message, look at the server, see nothing — that
// reads the same whether the gate held or **the message never arrived at all**. A test that
// cannot tell those apart is watching nothing.
//
// What stands in is a **receipt on the same line**. REQ-COM-005 requires the Mac to answer every
// `timeSyncPing` it receives with nothing asked of it first, so a ping sent *after* the message
// under test comes back as a `timeSyncPong`, and its arrival says the earlier message was taken
// off the same connection and handled before it.
//
// **That inference is not a clause.** It rests on three things, none of which is written down:
//
//   1. one WebSocket connection delivers in the order it was written (TCP beneath it);
//   2. `MdoroServer.receive(on:)` re-arms only *after* `handle` has returned, so messages from
//      one connection are handled one after another on the main actor;
//   3. the pong is sent inside that same handling, before the re-arm.
//
// Move the re-arm in `receive(on:)` above the `handle` call and the ordering is gone — these
// tests would go on passing while observing nothing. **If that line is ever touched, this is the
// reason to stop and look here.** It also buys nothing across two connections, which is why every
// exchange below is sequenced: one connection's message and its receipt, then the other's.
//
// **What the receipt still cannot tell apart**, and what stands in for that: a message discarded
// as unreadable (REQ-ERR-009 throws the bytes away in silence) looks exactly like a message a
// gate refused. So each test below sends the same message, built by the same helper, down the
// **authenticated** line as well and requires it to be honoured. One half is the gate; the other
// half is the proof that those bytes reach the handler at all.
//
// **Left unverified here on purpose:** the fifteen-second silence check itself
// (`startHeartbeatMonitor` / `checkHeartbeat`). Pinning it would mean either waiting fifteen
// seconds or reaching into the clock, and neither belongs in this file. What is pinned is the
// stamp that check reads.

// The message every step below leans on. Named so that a run which loses it says so once, in
// words, instead of four tests failing with nothing to read.
private let noReceipt: Comment = """
REQ-COM-005: the timeSyncPong that says the message before it was handled never came back. \
Either answering a timeSyncPing has grown a condition — which the clause forbids, because the \
phone reads the resulting silence as the Mac being gone — or this line went down. Nothing after \
this point has been observed.
"""

// MARK: - The far end

// A client of this test's own. Deliberately **not** `MdoroClient`: what is being driven is the
// server, and a client that decides for itself when to say hello and when to beat cannot send a
// `heartbeat` from a connection that never authenticated — which is the whole of what is being
// asked here.
@MainActor
private final class Probe {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "MdoroMacTests.Probe")
    private(set) var received: [ServerMessage] = []
    private(set) var isReady = false
    private var hasEnded = false
    private var reads = 0

    init(port: NWEndpoint.Port) {
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        connection = NWConnection(to: .hostPort(host: .ipv4(.loopback), port: port), using: parameters)
    }

    func start() async -> Bool {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state { self?.isReady = true }
            }
        }
        connection.start(queue: queue)
        receive()
        return await waits(until: { self.isReady })
    }

    func cancel() {
        hasEnded = true
        connection.cancel()
    }

    // The same shape the phone puts on the wire (`WebSocketLink.send`): one text frame carrying
    // the encoded envelope. Built through `MessageCoder` so that what is refused below is a
    // message the server can actually read — bytes it cannot read are discarded in silence
    // (REQ-ERR-009) and would look just like a gate holding.
    func send(_ message: ClientMessage) throws {
        let data = try MessageCoder.encode(Envelope(body: message))
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    // REQ-COM-005: the Mac answers every `timeSyncPing`, with nothing asked of it first. That is
    // what makes this usable as a receipt — see the note at the top of the file for what the
    // inference rests on and where it stops.
    //
    // Anything the server wrote to this line before the pong is already in `received` by the time
    // this returns: the frames arrive in the order they were written, this probe re-arms its own
    // read one message at a time, and each arrival is appended on the main actor in that order.
    func roundTrip() async throws -> Bool {
        let before = pongs.count
        try send(.timeSyncPing(TimeSyncPayload(t1: Date())))
        return await waits(until: { self.pongs.count > before })
    }

    var pongs: [TimeSyncPayload] {
        received.compactMap { (message: ServerMessage) -> TimeSyncPayload? in
            if case let .timeSyncPong(payload) = message { return payload }
            return nil
        }
    }

    var welcomes: Int {
        received.filter { (message: ServerMessage) -> Bool in
            if case .welcome = message { return true }
            return false
        }.count
    }

    var snapshots: Int {
        received.filter { (message: ServerMessage) -> Bool in
            if case .stateSnapshot = message { return true }
            return false
        }.count
    }

    // **The re-arm is bounded, and that is not tidiness.** A WebSocket the far end closed cleanly
    // leaves this connection `.ready` — no `.failed`, no `.cancelled` — and a read that completes
    // with nothing re-arms into a read that completes with nothing at once. That is the tight loop
    // the client's own line was found able to spin in, and here it would arrive at the end of
    // every test, when the server is folded, and then go on spinning for the rest of the run. So
    // this stops on an error, on the read that says the stream is over, and on a count no test
    // comes near.
    private func receive() {
        guard !hasEnded, reads < 200 else { return }
        reads += 1
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self, !self.hasEnded else { return }
                guard error == nil else {
                    self.hasEnded = true
                    return
                }
                if let data, !data.isEmpty,
                   let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .text || metadata.opcode == .binary,
                   let envelope = try? MessageCoder.decodeServer(data) {
                    self.received.append(envelope.body)
                }
                if isComplete, context?.isFinal == true, data?.isEmpty ?? true {
                    self.hasEnded = true
                    return
                }
                self.receive()
            }
        }
    }
}

// Waiting for an arrival, not for a length of time: it returns the moment the condition holds.
// Five seconds is far longer than the loopback interface takes and short enough to fail a run
// rather than hang it.
@MainActor
private func waits(upTo attempts: Int = 500, until condition: () -> Bool) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

// MARK: - The near end

// What the server hands upward. Nothing here holds domain judgement — the server has none either
// — so this records what it was asked and answers with a fixed state.
@MainActor
private final class Upstream {
    private(set) var commands: [CommandPayload] = []
    private(set) var snapshotsProvided = 0

    // Every hello is accepted: REQ-SEC-003's own judgement lives in `Authenticator` and is held
    // still elsewhere. What the gates below are about is a connection that never said hello at
    // all, which never reaches this.
    func callbacks() -> MdoroServer.Callbacks {
        MdoroServer.Callbacks(
            authenticate: { hello in .accept(DeviceToken(deviceName: hello.deviceName)) },
            resolveApproval: { _ in nil },
            handleCommand: { [weak self] payload in
                self?.commands.append(payload)
            },
            provideSnapshot: { [weak self] in
                self?.snapshotsProvided += 1
                return StateSnapshot(
                    timer: .idle(now: Date()),
                    task: TaskContext(),
                    settings: .default,
                    presets: .initial(),
                    connection: ConnectionState(isConnected: true)
                )
            },
            provideTaskList: { nil },
            provideDisplayName: { AppSettings.defaultDisplayName },
            connectionChanged: { _ in }
        )
    }
}

// A log that is never opened writes nothing, so the server has somewhere to report to without a
// file of the reader's being touched.
@MainActor
private func unopenedLog() -> DiagnosticLog {
    DiagnosticLog(directory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroRealConnection-\(UUID().uuidString)", isDirectory: true))
}

@MainActor
private struct Bench {
    let server: MdoroServer
    let upstream: Upstream
    let port: NWEndpoint.Port
}

@MainActor
private func raiseServer() async throws -> Bench {
    let upstream = Upstream()
    let server = MdoroServer(diagnostics: unopenedLog())
    let raw = try await server.start(callbacks: upstream.callbacks())
    let port = try #require(
        NWEndpoint.Port(rawValue: raw),
        "the listener settled on \(raw), which is not a port anything can be dialled on"
    )
    return Bench(server: server, upstream: upstream, port: port)
}

// REQ-SEC-002: the connection the Mac takes as its own. The welcome is what says the accept
// happened, and `connectedDeviceName` is what says it happened for this probe. Both the stamp on
// the watch and the name are set inside the accept before the welcome goes out, so reading them
// once the welcome is here is not a race.
@MainActor
private func authenticatedProbe(named name: String, on bench: Bench) async throws -> Probe {
    let probe = Probe(port: bench.port)
    let reached = await probe.start()
    #expect(reached, "\(name) never reached the listener on the loopback interface")
    try probe.send(.hello(HelloPayload(deviceName: name)))
    let welcomed = await waits(until: { probe.welcomes == 1 })
    #expect(welcomed, "\(name) said hello and no welcome came back, so nothing below runs against an accepted connection")
    #expect(bench.server.connectedDeviceName == name, "the server did not take \(name) as the connection on record")
    return probe
}

// A connection that reaches the listener and never says anything about who it is. This is what
// anyone able to reach the port can be: nothing else is needed.
@MainActor
private func strangerProbe(on bench: Bench) async -> Probe {
    let probe = Probe(port: bench.port)
    let reached = await probe.start()
    #expect(reached, "the unauthenticated probe never reached the listener on the loopback interface")
    return probe
}

@Suite("MdoroServer over a line that carries bytes (REQ-COM-005 / REQ-SEC-003)")
@MainActor
struct ServerUnderARealConnectionTests {

    // REQ-COM-005 / REQ-COM-007: **every ping is answered, with nothing asked of it first** — the
    // third of the four legs the clause names, and the one with no gate on purpose. A
    // `timeSyncPing` moves nothing on this Mac; it is answered and forgotten, so there is nothing
    // for an unauthenticated sender to reach. Put a condition here and the phone, whose own watch
    // is the arrival of this answer, reads a healthy line as fifteen seconds of silence and hangs
    // up a beat later with every other test still green.
    //
    // **This is also the receipt the three tests below are built on**, so it is asked for on its
    // own before they lean on it.
    @Test func theMacAnswersATimeSyncPingFromAConnectionThatNeverAuthenticated() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let stranger = await strangerProbe(on: bench)
        defer { stranger.cancel() }

        let t1 = Date()
        try stranger.send(.timeSyncPing(TimeSyncPayload(t1: t1)))

        let answered = await waits(until: { stranger.pongs.count == 1 })
        #expect(answered, "REQ-COM-005: a timeSyncPing arriving before any hello went unanswered")
        let pong = try #require(stranger.pongs.first)
        // REQ-COM-007: t1 comes back so the asker can pair the answer with its question. It
        // travels as ISO-8601, which keeps whole seconds, so what returns is the same second
        // rather than the same instant.
        #expect(abs(pong.t1.timeIntervalSince(t1)) < 1,
                "REQ-COM-007: the answer does not carry back the t1 it was asked about")
        #expect(pong.t2 != nil && pong.t3 != nil,
                "REQ-COM-007: the answer carries no t2/t3, so no offset can be worked out from it")
        // Answering is all it does. A ping is not a way in.
        #expect(bench.server.connectedDeviceName == nil,
                "answering the ping took its sender on as the connection on record")
    }

    // REQ-COM-005: **the fourth leg, and the gate that sits on it.**
    //
    // `lastHeartbeatAt` is the whole of the Mac's watch — `checkHeartbeat` reads it against
    // fifteen seconds, and the only things that carry it forward are this message and the accept.
    // Both halves are here because they are one stamp seen from two sides: the phone's beat must
    // move it, or a healthy line is hung up on; and a stranger's must not, or an unauthenticated
    // sender holds the authenticated connection's clock open — the one thing a message carrying no
    // token could otherwise do.
    //
    // The two beats are identical bytes from the same helper, sequenced one receipt at a time, so
    // the second half is also what says the first half refused a message it had read rather than
    // never having read one.
    @Test func theWatchMovesOnTheAuthenticatedConnectionsBeatAndOnNobodyElses() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }
        let stranger = await strangerProbe(on: bench)
        defer { stranger.cancel() }

        // The accept stamps the watch, which is what gives the refusal below something to be seen
        // not moving, rather than a stamp that was never made in the first place.
        let atAccept = try #require(
            bench.server.lastHeartbeatAt,
            "the accept left the watch unset, so a stamp that stayed put cannot be told from one that was never made"
        )

        try stranger.send(.heartbeat)
        let strangerHeard = try await stranger.roundTrip()
        #expect(strangerHeard, noReceipt)
        #expect(bench.server.lastHeartbeatAt == atAccept, """
            REQ-COM-005: a heartbeat from a connection that never authenticated moved the Mac's \
            watch. The one being judged and the one allowed to postpone the judgement must be the \
            same — a heartbeat carries no token and no body, so anyone who can reach this port \
            could otherwise keep the authenticated connection looking alive after it has gone.
            """)

        try phone.send(.heartbeat)
        let phoneHeard = try await phone.roundTrip()
        #expect(phoneHeard, noReceipt)
        let afterBeat = try #require(bench.server.lastHeartbeatAt)
        #expect(afterBeat > atAccept, """
            REQ-COM-005: the authenticated connection's heartbeat did not move the Mac's watch. \
            That stamp is the whole of the watch, so with it standing still checkHeartbeat hangs \
            up on a healthy line after fifteen seconds. It also means the refusal checked just \
            above was this message never being read, not the gate holding.
            """)
    }

    // REQ-SEC-003: **a command is the timer being driven.** Without this gate, reaching the port
    // is enough to pause, skip or abort the user's session and to rewrite their settings and
    // presets — no token, no pairing, nothing to approve.
    //
    // The two commands are alike but for their `clientRequestId` (REQ-PRT-003 ignores a resend of
    // the same one), so the second is what says the first was read and refused.
    @Test func onlyTheAuthenticatedConnectionsCommandIsActedOn() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }
        let stranger = await strangerProbe(on: bench)
        defer { stranger.cancel() }

        try stranger.send(.command(CommandPayload(action: .pause)))
        let strangerHeard = try await stranger.roundTrip()
        #expect(strangerHeard, noReceipt)
        #expect(bench.upstream.commands.isEmpty, """
            REQ-SEC-003: a command from a connection that never authenticated was handed upward. \
            Anyone who can reach this port can then pause, skip or abort the session and rewrite \
            the settings.
            """)

        let fromPhone = CommandPayload(action: .pause)
        try phone.send(.command(fromPhone))
        let phoneHeard = try await phone.roundTrip()
        #expect(phoneHeard, noReceipt)
        #expect(bench.upstream.commands.map(\.clientRequestId) == [fromPhone.clientRequestId], """
            the authenticated connection's command was not handed upward, so the refusal checked \
            just above was the message never being read rather than the gate holding.
            """)
    }

    // REQ-SEC-003: **the snapshot is what the user is doing.** It carries the running session, the
    // settings, the presets and the name of the task being worked on, and it goes to whoever asked
    // (`send(..., to: source)`). Without this gate, reaching the port is enough to read all of it,
    // as often as one likes, without ever pairing.
    @Test func onlyTheAuthenticatedConnectionIsSentTheSnapshotItAsksFor() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }
        let stranger = await strangerProbe(on: bench)
        defer { stranger.cancel() }

        // REQ-COM-004: the accept sends the whole state unasked, after the welcome — so it is
        // waited for rather than read the moment the welcome lands, and what is counted below is
        // what arrives on top of this one.
        let stateArrived = await waits(until: { phone.snapshots == 1 })
        #expect(stateArrived, "REQ-COM-004: the accept did not send the whole state")
        let providedAtAccept = bench.upstream.snapshotsProvided

        try stranger.send(.requestSnapshot)
        let strangerHeard = try await stranger.roundTrip()
        #expect(strangerHeard, noReceipt)
        #expect(stranger.snapshots == 0, """
            REQ-SEC-003: the whole state went out to a connection that never authenticated — the \
            running session, the settings, the presets and the name of the task being worked on.
            """)
        #expect(bench.upstream.snapshotsProvided == providedAtAccept,
                "REQ-SEC-003: the state was gathered for an unauthenticated asker, whether or not it reached the wire")

        try phone.send(.requestSnapshot)
        let phoneHeard = try await phone.roundTrip()
        #expect(phoneHeard, noReceipt)
        #expect(phone.snapshots == 2, """
            the authenticated connection asked for the state and was not sent it, so the refusal \
            checked just above was the message never being read rather than the gate holding.
            """)
    }
}
