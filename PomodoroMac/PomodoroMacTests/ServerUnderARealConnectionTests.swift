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

// MARK: - What the first run established
//
// The first run on CI failed all four and printed no reason. What it did print was a duration per
// test, and the durations turned out to be a full account on their own: subtract the 35.075 s the
// other 48 tests all reported and the excess is 15.584 / 23.330 / 38.959 / 46.741 s — exactly
// 2, 3, 5 and 6 times 7.792 s, which is exactly the number of bounded waits each test could reach
// before a throwing `#require` ended it. **Every wait ran out.**
//
// Two things follow, and neither is a guess:
//
//   - **the listener came up.** A `raiseServer()` that threw would have ended the test with zero
//     waits reached, not two. The server started, returned a port, and the port passed its check.
//   - **the dial never went ready.** The first wait in each test is the one in `Probe.dial`, and
//     it is among the ones that ran out.
//
// (The third thing it establishes is smaller and is fixed below: 500 turns of a 10 ms sleep is
// not five seconds. Each turn measured 15.58 ms on the runner, so every bound was half again as
// long as it read.)
//
// MARK: - What the third run established, and what it got wrong
//
// The third run printed this, four times over:
//
//     never went ready against the listener at localhost:52076.
//     WebSocket dial: preparing -> ready.
//     Plain TCP to the same port: ready — the listener is reachable,
//     so what failed is the WebSocket upgrade on top of it
//
// **The evidence and the conclusion in that line contradict each other.** `preparing -> ready`
// says the WebSocket line came up; `.ready` on a connection with an application protocol in its
// stack *is* the upgrade having completed. The conclusion was reached by looking only at whether
// plain TCP came up, and never at the trail sitting in the same sentence.
//
// So three things are now settled, and none of them is a guess:
//
//   - **the port is real** (`localhost:52076`). The listener binds, reports a port and is
//     reachable across the loopback interface from inside the test host.
//   - **the WebSocket upgrade completes.** It reached `.ready`.
//   - **what failed was the two-second bound**, and the reading of it.
//
// Why two seconds was not enough has two candidates, and the fix below closes both rather than
// choosing: the line may genuinely have taken longer than two seconds on a cold runner, or it may
// have been ready sooner while the `Task { @MainActor }` hop that records it sat behind
// forty-eight other tests on the same actor. `isUpNow` asks the connection instead of the hop,
// and the bound is ten times what it was.

// MARK: - Saying why, in a form the log keeps
//
// **The first CI run failed all four and said nothing about why.** Nothing matching the check
// mark, `Issue` or `recorded` reached the log — only the `failed on` lines and their durations —
// and `CLAUDE.md` warns that `xcodebuild` output loses the start of a line. Multi-line comments
// on `#expect` were the worst possible shape for that.
//
// So every failure here goes out three ways: a **single line**, with a token in front of it to
// grep for, printed to stdout and to stderr, and carried as a thrown error. A thrown error also
// ends the test where it went wrong, which is the other half of the lesson — the first run spent
// between 15 and 47 seconds per test walking through waits whose preconditions had already
// failed.
private let diagnosisToken = "MDORO-DIAG:"

private func diagnose(_ line: String) -> String {
    let text = "\(diagnosisToken) \(line)"
    print(text)
    FileHandle.standardError.write(Data((text + "\n").utf8))
    return text
}

// The same channel for a fact worth having when nothing failed. A green run that says how close
// the bounds came is worth more than a green run that says nothing, and on this project a run
// costs real money now.
private func trace(_ line: String) {
    _ = diagnose(line)
}

// Thrown rather than expected, so nothing downstream runs on a premise that is already gone.
private struct Wrong: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func describe(_ duration: Duration) -> String {
    let parts = duration.components
    return String(format: "%.3fs", Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
}

private struct Waited {
    let held: Bool
    let elapsed: Duration
    var describedElapsed: String { describe(elapsed) }
}

// **The bounds are here to fail instead of hang. They measure nothing.** Everything waited for in
// this file happens in milliseconds when it happens at all — a dial across the loopback
// interface, a frame coming back off it. On the runner these same waits have measured whole
// seconds, and the suite shares one main actor with forty-eight other tests, so the numbers are
// generous on purpose. **A healthy run pays none of it**: every wait returns the moment its
// condition holds.
//
// The second version of this file put the dial at two seconds, and that is what the third run
// broke on. The line came up somewhere past two seconds; by the time anything read the trail it
// said `ready`, inside a sentence claiming the opposite.
private let dialBudget = Duration.seconds(20)
private let arrivalBudget = Duration.seconds(10)
private let fallbackDialBudget = Duration.seconds(10)

// The message every receipt leans on. One line — see above for why.
private let noReceipt = "REQ-COM-005: the timeSyncPong that says the message before it was handled never came back. Either answering a timeSyncPing has grown a condition — which the clause forbids, because the phone reads the resulting silence as the Mac being gone — or this line went down. Nothing after this point was observed."

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
    // Every state this connection passed through, in order. **The first run had no way to say
    // what went wrong because this was not kept**: `.waiting(error)` is where a dial that is
    // refused or blocked parks, and a handler that only looks for `.ready` cannot tell that
    // apart from a dial that is still in progress.
    private(set) var trail: [String] = []
    private(set) var dialEnded = false
    private var hasEnded = false
    private var reads = 0

    // `webSocket: false` makes the same dial without the upgrade on top. It is used only when the
    // real one fails, to split the question in two — see `connectedProbe`.
    init(port: NWEndpoint.Port, webSocket: Bool = true) {
        let parameters = NWParameters.tcp
        if webSocket {
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        }
        // **`localhost`, not a pinned 127.0.0.1.** The listener is bound with `on: .any` and
        // nothing on record says which address families it ended up accepting, so a name that
        // resolves to both lets the connection settle on whichever one is there. It is still the
        // loopback interface: nothing goes on the LAN and no name is registered.
        //
        // **Whether this was needed is not known.** The first run dialled `.ipv4(.loopback)` and
        // never reached `.ready` inside 7.79 s; the third dialled this and did reach it. That is
        // consistent with the family mattering and also with the first run simply having been
        // slower than it looked, and the two were changed in the same commit as the bound. It is
        // kept because it is at worst harmless — the `timing:` line each dial prints is what will
        // eventually say how long this actually takes.
        connection = NWConnection(host: "localhost", port: port, using: parameters)
    }

    // **Whether the line is up is asked of the connection, not of the flag.** The flag is set on a
    // hop through the main actor, and this suite shares that actor with forty-eight other tests;
    // the connection's own state needs nothing drained to be true. The flag is kept as a second
    // opinion, never as the only one.
    var isUpNow: Bool {
        if case .ready = connection.state { return true }
        return isReady
    }

    // Returns whether the line came up, and how long that took. It does not throw — the caller is
    // the one holding the context needed to say what failed.
    func dial(upTo budget: Duration) async -> Waited {
        connection.stateUpdateHandler = { [weak self] state in
            // Read out here and carried across as plain strings and flags: the state itself is a
            // framework value with an error inside it, and nothing needs it on the other side.
            let stateName: String
            var ended = false
            var ready = false
            switch state {
            case .setup: stateName = "setup"
            case .preparing: stateName = "preparing"
            case .ready: stateName = "ready"; ready = true
            case let .waiting(error): stateName = "waiting(\(error))"
            case let .failed(error): stateName = "failed(\(error))"; ended = true
            case .cancelled: stateName = "cancelled"; ended = true
            @unknown default: stateName = "unknown"
            }
            let didEnd = ended
            let didReady = ready
            Task { @MainActor in
                guard let self else { return }
                self.trail.append(stateName)
                if didReady { self.isReady = true }
                if didEnd { self.dialEnded = true }
            }
        }
        connection.start(queue: queue)
        receive()
        let waited = await waits(upTo: budget, until: { self.isUpNow || self.dialEnded })
        // `waits` holds when either arm of the condition is true; only one of them is the line
        // coming up.
        return Waited(held: isUpNow, elapsed: waited.elapsed)
    }

    var trailDescription: String {
        trail.isEmpty ? "no state was ever reported" : trail.joined(separator: " -> ")
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
    func roundTrip() async throws -> Waited {
        let before = pongs.count
        try send(.timeSyncPing(TimeSyncPayload(t1: Date())))
        return await waits(upTo: arrivalBudget, until: { self.pongs.count > before })
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
//
// **The bound is a deadline, not a count of naps.** It used to be 500 turns of a 10 ms sleep,
// called five seconds; on the CI runner each of those turns measured 15.58 ms — timer leeway —
// so every bound was really 7.79 s. That is not a rounding error when a failing test walks
// through six of them. A clock cannot drift like that.
@MainActor
private func waits(upTo budget: Duration, until condition: () -> Bool) async -> Waited {
    let started = ContinuousClock.now
    let deadline = started + budget
    while ContinuousClock.now < deadline {
        if condition() {
            return Waited(held: true, elapsed: started.duration(to: ContinuousClock.now))
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    // How long it waited goes back with the answer. A wait that ran out says nothing on its own:
    // "not yet after 0.2 s" and "not yet after 20 s" are different findings.
    return Waited(held: condition(), elapsed: started.duration(to: ContinuousClock.now))
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

// **The port is checked, not assumed.** `ListenerReadiness.awaitReady` returns
// `listener.port?.rawValue ?? 0`, and `NWEndpoint.Port(rawValue: 0)` is a perfectly good `Port`
// — it is `.any`. So a listener that went ready without a port on it would hand back 0, every
// dial would go to a port nothing listens on, and the only symptom would be silence. Nothing
// else in this project asserts the port is a port: `ListenerFoldingTests` compares it with
// itself.
@MainActor
private func raiseServer() async throws -> Bench {
    let upstream = Upstream()
    let server = MdoroServer(diagnostics: unopenedLog())
    let raw = try await server.start(callbacks: upstream.callbacks())
    guard raw != 0, let port = NWEndpoint.Port(rawValue: raw) else {
        server.stop()
        throw Wrong(diagnose("the listener went ready on port \(raw) — ListenerReadiness.awaitReady fell back to 0, so NWListener.port was nil at .ready and nothing can be dialled"))
    }
    return Bench(server: server, upstream: upstream, port: port)
}

// **A dial that does not come up ends the test, and what it says is read off the evidence in
// order.**
//
// The third run is the reason this is written the way it is. The version before this one dialled
// plain TCP first and then looked at the WebSocket trail. The extra seconds that fallback took
// were enough for the real line to come up, so the trail read `ready` — and the sentence built
// around it announced that the WebSocket upgrade had failed. **The diagnosis contradicted the
// evidence it was carrying, in the same line.** Reading a conclusion off one arm of a branch
// without checking the other is the whole of that mistake.
//
// So the order here is fixed:
//
//   1. **is the line up now?** Asked before anything that takes time. If it is, the dial works and
//      the bound was short — that and nothing else.
//   2. only if it is not: dial the same port as plain TCP, then **ask once more**, because that
//      dial took time and time was the thing missing at step 1.
//   3. only if it is still not up: the plain dial splits the question. Plain TCP up means the
//      listener is reachable and the WebSocket upgrade on top of it is what failed — worth naming,
//      because `WebSocketLinks.dialEndpoint` only ever hands `WebSocketLink` a Bonjour `.service`
//      and no test in this project has ever completed a WebSocket handshake against `MdoroServer`
//      in-process. Plain TCP down means nothing reached the listener, and the trail's own
//      `waiting(...)` / `failed(...)` names why.
@MainActor
private func connectedProbe(to bench: Bench, called label: String) async throws -> Probe {
    let probe = Probe(port: bench.port)
    let dialled = await probe.dial(upTo: dialBudget)
    if dialled.held {
        trace("timing: \(label) went ready in \(dialled.describedElapsed) on localhost:\(bench.port.rawValue)")
        return probe
    }

    // Step 1.
    if probe.isUpNow {
        let trail = probe.trailDescription
        probe.cancel()
        throw Wrong(diagnose("\(label) came up, but not inside the \(describe(dialBudget)) dial bound. Line: \(trail). **The dial is not broken and the upgrade is not broken — the bound is too short for this runner.** Raise it; do not go looking for a fault."))
    }

    // Step 2.
    let plain = Probe(port: bench.port, webSocket: false)
    let plainDial = await plain.dial(upTo: fallbackDialBudget)
    let plainTrail = plain.trailDescription
    plain.cancel()

    if probe.isUpNow {
        let trail = probe.trailDescription
        probe.cancel()
        throw Wrong(diagnose("\(label) came up during the fallback dial — later than \(describe(dialBudget)), inside \(describe(dialBudget)) + \(plainDial.describedElapsed). Line: \(trail). The bound is short by a wide margin on this runner; nothing else is wrong."))
    }

    // Step 3.
    let webSocketTrail = probe.trailDescription
    probe.cancel()
    throw Wrong(diagnose(
        "\(label) never went ready in \(dialled.describedElapsed) against localhost:\(bench.port.rawValue), and was still not up after a further \(plainDial.describedElapsed). WebSocket line: \(webSocketTrail). "
        + (plainDial.held
           ? "Plain TCP to the same port went ready in \(plainDial.describedElapsed) — the listener is reachable, so what failed is the WebSocket upgrade on top of it."
           : "Plain TCP to the same port did not come up either (\(plainTrail)) — nothing reached the listener at all.")
    ))
}

// REQ-SEC-002: the connection the Mac takes as its own. The welcome is what says the accept
// happened, and `connectedDeviceName` is what says it happened for this probe. Both the stamp on
// the watch and the name are set inside the accept before the welcome goes out, so reading them
// once the welcome is here is not a race.
@MainActor
private func authenticatedProbe(named name: String, on bench: Bench) async throws -> Probe {
    let probe = try await connectedProbe(to: bench, called: name)
    try probe.send(.hello(HelloPayload(deviceName: name)))
    let welcomed = await waits(upTo: arrivalBudget, until: { probe.welcomes == 1 })
    guard welcomed.held else {
        let trail = probe.trailDescription
        probe.cancel()
        throw Wrong(diagnose("REQ-SEC-003: \(name) said hello on a line that was ready and no welcome came back in \(welcomed.describedElapsed). Line: \(trail). Server holds connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"), \(probe.received.count) message(s) arrived."))
    }
    guard bench.server.connectedDeviceName == name else {
        probe.cancel()
        throw Wrong(diagnose("the welcome arrived but the server holds connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"), not \(name) — nothing below would be running against the connection on record"))
    }
    return probe
}

// A connection that reaches the listener and never says anything about who it is. This is what
// anyone able to reach the port can be: nothing else is needed.
@MainActor
private func strangerProbe(on bench: Bench) async throws -> Probe {
    try await connectedProbe(to: bench, called: "the unauthenticated probe")
}

// An observation that failed goes out on both channels and lets the test carry on, so one broken
// gate does not hide the observation standing next to it. `diagnose` has already printed the
// line by the time the expectation records it.
@MainActor
private func holds(_ condition: Bool, _ line: @autoclosure () -> String) {
    guard !condition else { return }
    let text = diagnose(line())
    #expect(Bool(false), "\(text)")
}

// A receipt that does not arrive ends the test where it stopped meaning anything.
@MainActor
private func receipt(from probe: Probe, called label: String) async throws {
    let waited = try await probe.roundTrip()
    guard waited.held else {
        throw Wrong(diagnose("\(noReceipt) Waiting on: \(label), for \(waited.describedElapsed). Line: \(probe.trailDescription), still up: \(probe.isUpNow), \(probe.received.count) message(s) arrived in all."))
    }
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

        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }

        let t1 = Date()
        try stranger.send(.timeSyncPing(TimeSyncPayload(t1: t1)))

        let answered = await waits(upTo: arrivalBudget, until: { stranger.pongs.count == 1 })
        guard answered.held else {
            throw Wrong(diagnose("REQ-COM-005: a timeSyncPing arriving before any hello went unanswered in \(answered.describedElapsed) on a line that was ready. Line: \(stranger.trailDescription), still up: \(stranger.isUpNow). Received so far: \(stranger.received.count) message(s)."))
        }
        let pong = try #require(stranger.pongs.first)
        // REQ-COM-007: t1 comes back so the asker can pair the answer with its question. It
        // travels as ISO-8601, which keeps whole seconds, so what returns is the same second
        // rather than the same instant.
        holds(abs(pong.t1.timeIntervalSince(t1)) < 1,
              "REQ-COM-007: the answer does not carry back the t1 it was asked about (sent \(t1), got \(pong.t1))")
        holds(pong.t2 != nil && pong.t3 != nil,
              "REQ-COM-007: the answer carries no t2/t3, so no offset can be worked out from it")
        // Answering is all it does. A ping is not a way in.
        holds(bench.server.connectedDeviceName == nil,
              "answering the ping took its sender on as the connection on record (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"))")
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
        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }

        // The accept stamps the watch, which is what gives the refusal below something to be seen
        // not moving, rather than a stamp that was never made in the first place.
        guard let atAccept = bench.server.lastHeartbeatAt else {
            throw Wrong(diagnose("the accept left lastHeartbeatAt unset, so a stamp that stayed put cannot be told from one that was never made"))
        }

        try stranger.send(.heartbeat)
        try await receipt(from: stranger, called: "the unauthenticated probe's heartbeat")
        holds(bench.server.lastHeartbeatAt == atAccept,
              "REQ-COM-005: a heartbeat from a connection that never authenticated moved the Mac's watch. The one being judged and the one allowed to postpone the judgement must be the same — a heartbeat carries no token and no body, so anyone who can reach this port could otherwise keep the authenticated connection looking alive after it has gone.")

        try phone.send(.heartbeat)
        try await receipt(from: phone, called: "the authenticated connection's heartbeat")
        let afterBeat = bench.server.lastHeartbeatAt ?? .distantPast
        holds(afterBeat > atAccept,
              "REQ-COM-005: the authenticated connection's heartbeat did not move the Mac's watch. That stamp is the whole of the watch, so with it standing still checkHeartbeat hangs up on a healthy line after fifteen seconds. It also means the refusal checked just above was this message never being read, not the gate holding.")
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
        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }

        try stranger.send(.command(CommandPayload(action: .pause)))
        try await receipt(from: stranger, called: "the unauthenticated probe's command")
        holds(bench.upstream.commands.isEmpty,
              "REQ-SEC-003: a command from a connection that never authenticated was handed upward. Anyone who can reach this port can then pause, skip or abort the session and rewrite the settings.")

        let fromPhone = CommandPayload(action: .pause)
        try phone.send(.command(fromPhone))
        try await receipt(from: phone, called: "the authenticated connection's command")
        holds(bench.upstream.commands.map(\.clientRequestId) == [fromPhone.clientRequestId],
              "the authenticated connection's command was not handed upward (\(bench.upstream.commands.count) reached it), so the refusal checked just above was the message never being read rather than the gate holding.")
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
        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }

        // REQ-COM-004: the accept sends the whole state unasked, after the welcome — so it is
        // waited for rather than read the moment the welcome lands, and what is counted below is
        // what arrives on top of this one.
        let baseline = await waits(upTo: arrivalBudget, until: { phone.snapshots == 1 })
        guard baseline.held else {
            throw Wrong(diagnose("REQ-COM-004: the accept did not send the whole state — the welcome arrived but no stateSnapshot followed it in \(baseline.describedElapsed), so what is counted below has no baseline (\(phone.received.count) message(s) arrived in all)"))
        }
        let providedAtAccept = bench.upstream.snapshotsProvided

        try stranger.send(.requestSnapshot)
        try await receipt(from: stranger, called: "the unauthenticated probe's requestSnapshot")
        holds(stranger.snapshots == 0,
              "REQ-SEC-003: the whole state went out to a connection that never authenticated — the running session, the settings, the presets and the name of the task being worked on.")
        holds(bench.upstream.snapshotsProvided == providedAtAccept,
              "REQ-SEC-003: the state was gathered for an unauthenticated asker, whether or not it reached the wire")

        try phone.send(.requestSnapshot)
        try await receipt(from: phone, called: "the authenticated connection's requestSnapshot")
        holds(phone.snapshots == 2,
              "the authenticated connection asked for the state and was not sent it (\(phone.snapshots) arrived in all), so the refusal checked just above was the message never being read rather than the gate holding.")
    }
}
