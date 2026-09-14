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
//   - **what failed was the waiting**, and the reading of it.
//
// The reading was fixed here and stayed fixed. **The waiting was read wrong twice**: this run was
// answered by raising the bound from two seconds to twenty and asking the connection rather than
// the flag, on the theory that the line was either slow or recorded late. The next section is what
// happened to that theory.

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
// said `ready`, inside a sentence claiming the opposite. **The fourth run then showed that raising
// the number was never the answer** — at twenty seconds the line came up at +0.027 s, four times
// over. These numbers are a floor under a hang, nothing more; what made the waiting work is that
// it no longer runs on the actor it waits for.
private let dialBudget = Duration.seconds(20)
private let arrivalBudget = Duration.seconds(10)
private let fallbackDialBudget = Duration.seconds(10)

// The message every receipt leans on. One line — see above for why.
private let noReceipt = "REQ-COM-005: the timeSyncPong that says the message before it was handled never came back. Either answering a timeSyncPing has grown a condition — which the clause forbids, because the phone reads the resulting silence as the Mac being gone — or this line went down. Nothing after this point was observed."

// MARK: - What the fourth run established: the waiting was the obstacle

// The fourth run raised the dial bound to twenty seconds and printed, four times:
//
//     came up during the fallback dial — later than 20.000s, inside 20.000s + 0.027s
//
// +0.027 / +0.031 / +0.032 / +0.032 s. **A handshake does not take 20.03 seconds.** It finished the
// moment this test stopped waiting for it — four times, to the hundredth. The bound was never the
// thing in the way; **the way of waiting was.**
//
// What it was in the way of, and why plain TCP never showed it:
//
//     the probe dials
//       -> the kernel completes the TCP handshake          (so a plain dial is ready in 27 ms)
//       -> NWListener.newConnectionHandler fires
//       -> MdoroServer hops `Task { @MainActor in accept(connection) }`
//       -> **that hop has to reach the main actor**
//       -> until it does, `incoming.start(queue:)` is never called
//       -> so the WebSocket upgrade never completes
//       -> the probe sits in `preparing`
//
// **Only the upgrade needs anything of the server.** That is the asymmetry, and it is why the plain
// dial came up instantly while the real one did not: the loop that was waiting for the handshake
// was standing between the handshake and the actor it needed. Polling every 10 ms on the main
// actor, four tests at once, alongside forty-eight others — reading `isUpNow` off the connection
// (the third version's fix) removed a symptom and left the cause.
//
// So nothing in this file's observation path touches the main actor any more:
//
//   - `Probe` is not an actor-isolated type. Its state lives behind a lock and is written on
//     whichever queue saw the change — the connection's own.
//   - waiting is a **continuation resumed from that queue**, not a poll. A test that is waiting is
//     suspended: it holds nothing, wakes for nothing, and the main actor is free for the server's
//     accept.
//   - the deadline that races that continuation runs on a **detached** task, off the main actor too.
//   - `Once` is lifted from `ListenerReadiness` in `MdoroServer.swift`, which solves the same
//     problem for the listener: two things race to resume one continuation, and resuming it twice
//     is a crash.
//
// **What matters is not which executor these run on, it is what gets queued on the main actor
// while they wait.** This target builds with approachable concurrency, so a `nonisolated async`
// function called from a `@MainActor` test may well run on that same actor — and it makes no
// difference here. A wait now enqueues exactly two pieces of main-actor work, at its two ends:
// registering, and being resumed. The version before it enqueued one every ten milliseconds for
// twenty seconds, per probe, per test.

// MARK: - The far end

// Borrowed from `ListenerReadiness.Once` in `MdoroServer.swift`. An arrival and a deadline race to
// resume the same continuation; whichever loses must be able to find out that it lost.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// A client of this test's own. Deliberately **not** `MdoroClient`: what is being driven is the
// server, and a client that decides for itself when to say hello and when to beat cannot send a
// `heartbeat` from a connection that never authenticated — which is the whole of what is being
// asked here.
//
// **Deliberately not `@MainActor` either**, which is the fourth run's lesson. Everything this
// class observes is something the server does *on* the main actor; an observer that needs that
// same actor to notice is standing in its own light.
private final class Probe: @unchecked Sendable {

    // Everything this probe has seen. Copied out under the lock and read at leisure, so a test
    // never holds the lock while it thinks.
    struct Observed {
        var trail: [String] = []
        var isReady = false
        var ended = false
        var messages: [ServerMessage] = []

        var pongs: [TimeSyncPayload] {
            messages.compactMap { (message: ServerMessage) -> TimeSyncPayload? in
                if case let .timeSyncPong(payload) = message { return payload }
                return nil
            }
        }

        var welcomes: Int {
            messages.filter { (message: ServerMessage) -> Bool in
                if case .welcome = message { return true }
                return false
            }.count
        }

        var snapshots: Int {
            messages.filter { (message: ServerMessage) -> Bool in
                if case .stateSnapshot = message { return true }
                return false
            }.count
        }

        // The states this connection passed through, in order. `waiting(error)` is where a dial
        // that is refused or blocked parks; a handler that only watched for `.ready` could not tell
        // that apart from a dial still in progress, which is what left the second run mute.
        var trailDescription: String {
            trail.isEmpty ? "no state was ever reported" : trail.joined(separator: " -> ")
        }
    }

    private struct Waiter {
        let id: UUID
        let predicate: (Observed) -> Bool
        let once: Once
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "MdoroMacTests.Probe")
    private let lock = NSLock()
    private var observed = Observed()
    private var waiting: [Waiter] = []
    private var expired: Set<UUID> = []
    private var finished = false
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
        // never reached `.ready` inside 7.79 s; later runs dialled this and did reach it — though
        // the fourth run showed that what those runs were really measuring was the waiting, so the
        // comparison proves less than it looked like it did. It is kept because it is at worst
        // harmless, and the `timing:` line each dial prints is what will say how long it takes.
        connection = NWConnection(host: "localhost", port: port, using: parameters)
    }

    // MARK: Waiting without the main actor

    // Wait until `until` holds of what has been seen, or the budget runs out.
    //
    // **Nothing here reaches for the main actor.** The predicate is evaluated under this object's
    // lock, on whichever thread saw the change; the deadline runs detached. A caller that is
    // `@MainActor` releases that actor for the whole of this await, which is the point — what it
    // is waiting for usually needs that actor to happen at all.
    func waits(upTo budget: Duration, until predicate: @escaping (Observed) -> Bool) async -> Waited {
        let started = ContinuousClock.now
        let once = Once()
        let id = UUID()

        let deadline = Task.detached { [weak self] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            self?.giveUp(id)
        }
        defer { deadline.cancel() }

        let held: Bool = await withCheckedContinuation { continuation in
            lock.lock()
            // Checked and registered under one hold of the lock, so a change arriving in between
            // cannot be missed: `change` cannot run while this is deciding.
            if predicate(observed) {
                lock.unlock()
                if once.claim() { continuation.resume(returning: true) }
                return
            }
            // The deadline above was started before this registration, so in principle it can
            // arrive first. **A wait nobody ever resumes is a hung test**, and a hung test on a
            // metered runner is the most expensive failure there is, so the deadline leaves word.
            if expired.remove(id) != nil {
                lock.unlock()
                if once.claim() { continuation.resume(returning: false) }
                return
            }
            waiting.append(Waiter(id: id, predicate: predicate, once: once, continuation: continuation))
            lock.unlock()
        }
        return Waited(held: held, elapsed: started.duration(to: ContinuousClock.now))
    }

    // Every change to what has been seen goes through here, so no change can be made without the
    // waiters being asked whether it was the one they wanted.
    private func change(_ mutate: (inout Observed) -> Void) {
        lock.lock()
        mutate(&observed)
        let woken = waiting.filter { $0.predicate(observed) }
        let wokenIds = Set(woken.map(\.id))
        waiting.removeAll { wokenIds.contains($0.id) }
        lock.unlock()
        // Resumed outside the lock: a resumed task may run at once, and must not find the lock held.
        for waiter in woken where waiter.once.claim() {
            waiter.continuation.resume(returning: true)
        }
    }

    private func giveUp(_ id: UUID) {
        lock.lock()
        if let waiter = waiting.first(where: { $0.id == id }) {
            waiting.removeAll { $0.id == id }
            lock.unlock()
            if waiter.once.claim() { waiter.continuation.resume(returning: false) }
            return
        }
        // Either the wait has already been resumed — in which case this is a note nobody reads —
        // or it has not registered yet, and this is the word it needs. Both are cheap; only the
        // second one matters, and only a wait with a very short budget can reach it.
        expired.insert(id)
        lock.unlock()
    }

    // MARK: The line

    // **Whether the line is up is asked of the connection itself.** Kept alongside the flag the
    // state handler sets, never instead of it, and neither of them needs an actor drained.
    var isUpNow: Bool {
        if case .ready = connection.state { return true }
        return seen.isReady
    }

    var seen: Observed {
        lock.lock(); defer { lock.unlock() }
        return observed
    }

    // Returns whether the line came up, and how long that took.
    func dial(upTo budget: Duration) async -> Waited {
        connection.stateUpdateHandler = { [weak self] state in
            // Read out on the connection's own queue and written straight through. The framework
            // value with the error inside it never leaves this closure.
            let name: String
            var ready = false
            var ended = false
            switch state {
            case .setup: name = "setup"
            case .preparing: name = "preparing"
            case .ready: name = "ready"; ready = true
            case let .waiting(error): name = "waiting(\(error))"
            case let .failed(error): name = "failed(\(error))"; ended = true
            case .cancelled: name = "cancelled"; ended = true
            @unknown default: name = "unknown"
            }
            self?.change {
                $0.trail.append(name)
                if ready { $0.isReady = true }
                if ended { $0.ended = true }
            }
        }
        connection.start(queue: queue)
        receive()
        // The wait holds when either arm is true; only one of them is the line coming up.
        let waited = await waits(upTo: budget, until: { $0.isReady || $0.ended })
        return Waited(held: isUpNow, elapsed: waited.elapsed)
    }

    func cancel() {
        lock.lock()
        finished = true
        lock.unlock()
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
    // Anything the server wrote to this line before the pong is already in `seen` by the time this
    // returns: the frames arrive in the order they were written, this probe re-arms its own read
    // one message at a time, and each arrival is recorded before the next is asked for.
    func roundTrip(upTo budget: Duration) async throws -> Waited {
        let before = seen.pongs.count
        try send(.timeSyncPing(TimeSyncPayload(t1: Date())))
        return await waits(upTo: budget, until: { $0.pongs.count > before })
    }

    // **The re-arm is bounded, and that is not tidiness.** A WebSocket the far end closed cleanly
    // leaves this connection `.ready` — no `.failed`, no `.cancelled` — and a read that completes
    // with nothing re-arms into a read that completes with nothing at once. That is the tight loop
    // the client's own line was found able to spin in, and here it would arrive at the end of
    // every test, when the server is folded, and then go on spinning for the rest of the run. So
    // this stops on an error, on the read that says the stream is over, and on a count no test
    // comes near.
    private func receive() {
        guard claimRead() else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self else { return }
            if error != nil {
                self.change { $0.ended = true }
                return
            }
            if let data, !data.isEmpty,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .text || metadata.opcode == .binary,
               let envelope = try? MessageCoder.decodeServer(data) {
                self.change { $0.messages.append(envelope.body) }
            }
            if isComplete, context?.isFinal == true, data?.isEmpty ?? true {
                self.change { $0.ended = true }
                return
            }
            self.receive()
        }
    }

    private func claimRead() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished, reads < 200 else { return false }
        reads += 1
        return true
    }
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

// **A line that comes up in the moment after the bound expired is not a bound that was too short.**
// A handshake does not take twenty seconds and then finish in thirty milliseconds. It finished
// because something stopped standing in its way — and if the gap is small, the thing that stopped
// is *the waiting*, because that is the only thing that ended at that instant.
//
// The fourth run printed exactly this shape, four times, at +0.027 to +0.032 s, while this file
// waited by polling the main actor. **Nothing here polls any more.** So if the shape comes back,
// the waiting in this file is not the obstacle and the next place to look is whatever else holds
// the main actor while `MdoroServer.accept` is queued on it: the WebSocket upgrade cannot finish
// until that call runs, and plain TCP is untouched because the kernel completes it without asking
// anyone. **That asymmetry is the tell, and the line below carries both halves of it.**
// `beforeAnySecondDial` is there to separate the two readings of that +0.027 s, which the third and
// fourth runs could not. Both of them saw readiness appear *during* the fallback dial, and that is
// equally consistent with "the waiting stopped" and with "a second NWConnection being started did
// something". Where the line comes up says which: before any second connection exists, only the
// first can be the cause.
private func cameUpAfterTheBound(
    _ label: String, gap: Duration, trail: String, beforeAnySecondDial: Bool
) -> String {
    let atOnce = gap < .seconds(1)
    return "\(label) went ready \(describe(gap)) after the \(describe(dialBudget)) bound expired. Line: \(trail). "
        + (beforeAnySecondDial
           ? "**No second connection had been made yet**, so nothing but the end of the waiting can account for it. "
           : "**This is during the fallback dial**, so the end of the waiting and the starting of a second connection are both still on the table; a run that reports this from step 1 instead would settle it. ")
        + (atOnce
           ? "**It came up the instant this test stopped waiting, so the waiting is what it was waiting on — not the clock.** This file no longer polls the main actor, so look for whatever else holds that actor while MdoroServer.accept is queued on it; the upgrade cannot finish until that runs, and plain TCP is unaffected because the kernel completes it. Raising the bound will not fix this shape."
           : "The gap is wide enough that the line may simply be slow on this runner; read the timing: lines and raise the bound.")
}

// **A dial that does not come up ends the test, and what it says is read off the evidence in
// order.**
//
// The third run is the reason this is written the way it is. The version before it dialled plain
// TCP first and then looked at the WebSocket trail. The seconds that fallback took were enough for
// the real line to come up, so the trail read `ready` — and the sentence built around it announced
// that the WebSocket upgrade had failed. **The diagnosis contradicted the evidence it was carrying,
// in the same line.** Reading a conclusion off one arm of a branch without checking the other is
// the whole of that mistake.
//
// So the order here is fixed:
//
//   1. **is the line up now?** Asked before anything that takes time, and the gap since the bound
//      expired is measured, because a gap near zero means something different from a wide one.
//   2. only if it is not: dial the same port as plain TCP, then **ask once more**, because that
//      dial took time and time was what was missing at step 1.
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
    let boundExpired = ContinuousClock.now

    // Step 1.
    if probe.isUpNow {
        let trail = probe.seen.trailDescription
        probe.cancel()
        throw Wrong(diagnose(cameUpAfterTheBound(
            label, gap: boundExpired.duration(to: ContinuousClock.now), trail: trail,
            beforeAnySecondDial: true
        )))
    }

    // Step 2.
    let plain = Probe(port: bench.port, webSocket: false)
    let plainDial = await plain.dial(upTo: fallbackDialBudget)
    let plainTrail = plain.seen.trailDescription
    plain.cancel()

    if probe.isUpNow {
        let trail = probe.seen.trailDescription
        probe.cancel()
        throw Wrong(diagnose(cameUpAfterTheBound(
            label, gap: boundExpired.duration(to: ContinuousClock.now), trail: trail,
            beforeAnySecondDial: false
        ) + " Plain TCP to the same port: \(plainDial.held ? "ready in \(plainDial.describedElapsed)" : "not up (\(plainTrail))")."))
    }

    // Step 3.
    let webSocketTrail = probe.seen.trailDescription
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
    let welcomed = await probe.waits(upTo: arrivalBudget, until: { $0.welcomes == 1 })
    guard welcomed.held else {
        let seen = probe.seen
        probe.cancel()
        throw Wrong(diagnose("REQ-SEC-003: \(name) said hello on a line that was ready and no welcome came back in \(welcomed.describedElapsed). Line: \(seen.trailDescription). Server holds connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"), \(seen.messages.count) message(s) arrived."))
    }
    guard bench.server.connectedDeviceName == name else {
        probe.cancel()
        throw Wrong(diagnose("the welcome arrived but the server holds connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"), not \(name) — nothing below would be running against the connection on record"))
    }
    trace("timing: \(name) was welcomed in \(welcomed.describedElapsed)")
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
    let waited = try await probe.roundTrip(upTo: arrivalBudget)
    guard waited.held else {
        let seen = probe.seen
        throw Wrong(diagnose("\(noReceipt) Waiting on: \(label), for \(waited.describedElapsed). Line: \(seen.trailDescription), still up: \(probe.isUpNow), \(seen.messages.count) message(s) arrived in all."))
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

        // REQ-COM-007: **the instant asked about is not a reading of any clock here.**
        //
        // `4_000_000_000` seconds past the epoch is 2096, and it is a whole number of seconds. Both
        // halves of that are load-bearing:
        //
        //   - **whole seconds** means the value survives the wire unchanged, which is what lets the
        //     check below be exact. `MessageCoder` encodes dates with
        //     `JSONEncoder.dateEncodingStrategy = .iso8601` and decodes them with the matching
        //     strategy (`Messages.swift`), and that writes `2096-10-02T07:06:40Z` — whole seconds,
        //     no fraction. **`Date()` would not survive it**, which is why it is not used: it would
        //     come back floored to its second and force a tolerance, and a tolerance is what let
        //     the mutation below through.
        //   - **seventy years from now** means no clock on this machine can produce it by accident.
        //
        // REQ-COM-005: it being an implausible instant is also the point. `t1` is the *phone's*
        // wall clock, and the distance between the two clocks is the very thing this exchange
        // exists to measure — so the Mac must answer it without judging it. A plausibility check
        // on `t1` would leave a phone whose clock runs ahead unanswered for ever, which the phone
        // reads as the Mac being gone; here it fails a test instead of a user.
        let t1 = Date(timeIntervalSince1970: 4_000_000_000)
        try stranger.send(.timeSyncPing(TimeSyncPayload(t1: t1)))

        let answered = await stranger.waits(upTo: arrivalBudget, until: { $0.pongs.count == 1 })
        guard answered.held else {
            let seen = stranger.seen
            throw Wrong(diagnose("REQ-COM-005: a timeSyncPing arriving before any hello went unanswered in \(answered.describedElapsed) on a line that was ready. Line: \(seen.trailDescription), still up: \(stranger.isUpNow). Received so far: \(seen.messages.count) message(s)."))
        }
        let pong = try #require(stranger.seen.pongs.first)
        // REQ-COM-007: t1 comes back so the asker can pair the answer with its question, and
        // **carried back is not "about the same time"**. This was a one-second tolerance, and one
        // second is far more than a loopback round trip: a Mac answering with its own receipt time
        // — `TimeSyncPayload(t1: t2, ...)` — would have passed it every single time, which is
        // exactly the value this line exists to catch. Exact equality is what bites, and the
        // instant chosen above is what makes exact equality available.
        holds(pong.t1 == t1,
              "REQ-COM-007: the answer does not carry back the t1 it was asked about (sent \(t1), got \(pong.t1)) — an answer carrying the Mac's own clock instead cannot be paired with the question that asked for it")
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
        let baseline = await phone.waits(upTo: arrivalBudget, until: { $0.snapshots == 1 })
        guard baseline.held else {
            throw Wrong(diagnose("REQ-COM-004: the accept did not send the whole state — the welcome arrived but no stateSnapshot followed it in \(baseline.describedElapsed), so what is counted below has no baseline (\(phone.seen.messages.count) message(s) arrived in all)"))
        }
        let providedAtAccept = bench.upstream.snapshotsProvided

        try stranger.send(.requestSnapshot)
        try await receipt(from: stranger, called: "the unauthenticated probe's requestSnapshot")
        holds(stranger.seen.snapshots == 0,
              "REQ-SEC-003: the whole state went out to a connection that never authenticated — the running session, the settings, the presets and the name of the task being worked on.")
        holds(bench.upstream.snapshotsProvided == providedAtAccept,
              "REQ-SEC-003: the state was gathered for an unauthenticated asker, whether or not it reached the wire")

        try phone.send(.requestSnapshot)
        try await receipt(from: phone, called: "the authenticated connection's requestSnapshot")
        holds(phone.seen.snapshots == 2,
              "the authenticated connection asked for the state and was not sent it (\(phone.seen.snapshots) arrived in all), so the refusal checked just above was the message never being read rather than the gate holding.")
    }
}
