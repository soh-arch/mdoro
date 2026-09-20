import Testing
import Foundation
import Network
import MdoroCore
@testable import MdoroMac

// REQ-COM-005 / REQ-SEC-003: **`MdoroServer` driven over a line that really carries bytes.**
//
// Three of the cases in `dispatch(_:from:)` — `.command`, `.requestSnapshot` and `.heartbeat` —
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
//   2. `MdoroServer.receive(on:counting:)` re-arms only *after* `handle` has returned, so messages
//      from one connection are handled one after another on the main actor;
//   3. the pong is sent inside that same handling, before the re-arm.
//
// Move the re-arm in `receive(on:counting:)` above the `handle` call and the ordering is gone — these
// tests would go on passing while observing nothing. **If that line is ever touched, this is the
// reason to stop and look here.** It also buys nothing across two connections, which is why every
// exchange below is sequenced: one connection's message and its receipt, then the other's.
//
// **What the receipt still cannot tell apart**, and what stands in for that: a message discarded
// as unreadable (REQ-ERR-009 throws the bytes away in silence, for the first nine in a row) looks
// exactly like a message a gate refused. So each gate test below sends the same message, built by
// the same helper, down the **authenticated** line as well and requires it to be honoured. One
// half is the gate; the other half is the proof that those bytes reach the handler at all.
//
// **The three tests about broken messages** are about that silence itself — what ends it
// (REQ-ERR-009's run of ten), what must not be mistaken for it (REQ-PRT-005's unknown message
// type), and whose it is (a stranger's unreadable messages are not the iPhone's). They are also
// where the receipt earns the most: a pong coming back after nine unreadable messages says both
// that the line is still here and that the nine were read off it. **The last of the three carries
// a written-up account of a mutation no test here catches; read it before adding a fourth.**
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
        sendRaw(try MessageCoder.encode(Envelope(body: message)))
    }

    // REQ-ERR-009 / REQ-PRT-005: the same frame, carrying bytes `MessageCoder` never made. This is
    // the only way to put a message on this wire that the far end cannot read — everything sent
    // through `send(_:)` above is by construction readable — and it is the whole of what the two
    // tests about counting stand on.
    func sendRaw(_ data: Data) {
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
    // both ends' own lines were found able to spin in, and here it would arrive at the end of
    // every test, when the server is folded, and then go on spinning for the rest of the run. So
    // this stops on the read that says the stream is over, and on a count no test comes near.
    //
    // **The ending is read by `LineRead`, the same function the server under test reads it with.**
    // Ask instead for `isComplete, context?.isFinal == true, data?.isEmpty ?? true`, where
    // `LineRead` asks for no frame on the read rather than for a context that says it is the last
    // one, and **those are different properties** — a read arriving with no context at all
    // satisfies the second and not the first, because `nil?.isFinal == true` is false — so the
    // probe goes on reading past an ending the server stopped at, or stops at one the server read
    // through, and either way a test is watching a line the two ends disagree about. **The count
    // below is what keeps this bounded if that judgement is ever wrong**; it is not what decides
    // the ending.
    private func receive() {
        guard claimRead() else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self else { return }
            switch LineRead.of(
                data: data, frame: context?.webSocketFrame, isComplete: isComplete,
                failed: error != nil
            ) {
            case let .message(message):
                if let envelope = try? MessageCoder.decodeServer(message) {
                    self.change { $0.messages.append(envelope.body) }
                }
            case .skip:
                break
            case .end:
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
    // REQ-ERR-009: how many times the Mac has said the connection is gone. **This is the near end
    // of the hang-up**, and it is what the counting test observes: `handleDisconnect` reports it
    // on the main actor at the moment it drops the connection, so it is exact and it is early —
    // earlier than the close can travel back down the wire and be noticed there.
    private(set) var hangUps = 0
    // **The far end of the fault `PendingApprovalEndingTests` is about**: how many times the Mac has
    // been told it *is* connected. `note` below counted only the noes, so a connection reported for a
    // line that was already over was observed by nothing.
    private(set) var connectedReports = 0
    // REQ-SEC-004: what `resolveApproval` was asked, in order. A `false` in here is the banner coming
    // down; whether the user or something else put it there is what the test around it says.
    private(set) var approvalsAsked: [Bool] = []

    // REQ-SEC-004: what `authenticate` answers. **Every test above wants the accept** and says
    // nothing about this; the ones about a question waiting for the user replace it.
    var answersHelloWith: (HelloPayload) -> Authenticator.Decision = { hello in
        .accept(DeviceToken(deviceName: hello.deviceName))
    }

    private var waitingForHangUp: CheckedContinuation<Void, Never>?
    private var waitingForApproval: CheckedContinuation<Void, Never>?

    // Wait until the Mac drops a connection, or give up. **Nothing is polled**: this is resumed
    // from `connectionChanged`, which runs on the main actor — the same actor `MdoroServer` needs
    // to do the dropping — so a test that is waiting here is holding nothing of what it waits for.
    // That is the fourth run's lesson at the top of this file, kept to.
    func waitsForHangUp(upTo budget: Duration) async -> Bool {
        if hangUps > 0 { return true }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            self?.giveUpWaitingForHangUp()
        }
        defer { deadline.cancel() }
        // The deadline sleeps before it can resume anything, so the registration below is always
        // in place first — there is no window in which a resumption is lost.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waitingForHangUp = continuation
        }
        return hangUps > 0
    }

    private func giveUpWaitingForHangUp() {
        waitingForHangUp?.resume()
        waitingForHangUp = nil
    }

    // REQ-SEC-004: wait until the question about a connection request is settled one way or the
    // other. **Nothing is polled**, for the reason `waitsForHangUp` gives: this is resumed from
    // `resolveApproval`, on the main actor, which is the actor the settling has to happen on.
    //
    // **One waiting slot, and no test here has two of these in flight** — a second waiter would
    // take it from the first, which would then run out its own budget and blame the server. Should
    // one ever be needed, take `HeldReads.waitsForReads`'s precondition rather than this comment.
    func waitsForApprovalSettled(upTo budget: Duration) async -> Bool {
        if !approvalsAsked.isEmpty { return true }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            self?.giveUpWaitingForApproval()
        }
        defer { deadline.cancel() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waitingForApproval = continuation
        }
        return !approvalsAsked.isEmpty
    }

    private func giveUpWaitingForApproval() {
        waitingForApproval?.resume()
        waitingForApproval = nil
    }

    private func note(approval approved: Bool) {
        approvalsAsked.append(approved)
        waitingForApproval?.resume()
        waitingForApproval = nil
    }

    private func note(_ state: ConnectionState) {
        guard !state.isConnected else {
            connectedReports += 1
            return
        }
        hangUps += 1
        waitingForHangUp?.resume()
        waitingForHangUp = nil
    }

    // Every hello is accepted unless a test says otherwise (`answersHelloWith`): REQ-SEC-003's own
    // judgement lives in `Authenticator` and is held still elsewhere. What the gates below are about
    // is a connection that never said hello at all, which never reaches this.
    func callbacks() -> MdoroServer.Callbacks {
        MdoroServer.Callbacks(
            authenticate: { [weak self] hello in
                self?.answersHelloWith(hello) ?? .accept(DeviceToken(deviceName: hello.deviceName))
            },
            // REQ-SEC-004: nil is what an upstream with nothing waiting answers, and it is what the
            // Authenticator itself answers a `resolveApproval` it has no held hello for. That it was
            // asked at all is the observation; the answer is beside the point here.
            resolveApproval: { [weak self] approved in
                self?.note(approval: approved)
                return nil
            },
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
            connectionChanged: { [weak self] state in self?.note(state) }
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
//
// REQ-COM-004: `reads` is the read loop's one call into the transport (`ServerLineReading`). Every
// test above leaves it alone and gets the real one; the two at the foot of this file take it, so
// that what the loop does with an ending can be asked without a peer having to produce one.
//
// REQ-ERR-010: `diagnostics` is left out by every test that has nothing to read back, and gets a log
// that was never opened — one that writes nothing, so no file of the reader's is touched. The tests
// about what an ending is written down as hand in a log over a scratch directory instead.
@MainActor
private func raiseServer(
    reads: any ServerLineReading = WebSocketLineReads(), diagnostics: DiagnosticLog? = nil
) async throws -> Bench {
    let upstream = Upstream()
    let server = MdoroServer(diagnostics: diagnostics ?? unopenedLog(), reads: reads)
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

// MARK: - Two messages that differ only in which field carries the word this version does not know

// REQ-PRT-005: **a type this version has never heard of.** Well formed, header and all; the only
// thing about it this Mac cannot do is name it. The clause says to ignore it — that is the whole of
// forward compatibility, and REQ-ERR-009 must not count it as broken, or the first message a later
// version adds starts a run of ten towards hanging up every iPhone that sends it.
private func aTypeThisVersionDoesNotKnow() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "type": "somethingALaterVersionAdded",
        "messageId": UUID().uuidString,
        "sentAt": "2026-01-01T00:00:00Z",
    ], options: [])
}

// REQ-PRT-005: **a value this version cannot make.** The type is known, the field is known, and
// only the value is not — and the exemption above does not reach values. Nothing anywhere lays down
// a response for an `action` outside its set, and reading it as one of the values that *are* in the
// set is forbidden, so the message stays unreadable. REQ-ERR-009 names exactly this as broken.
//
// **These two differ in one word and in which key it sits under.** That is the line the `try?` in
// `MdoroServer.handle` could not draw: one of them decodes to nil and the other throws.
private func aValueThisVersionCannotRead() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "type": "command",
        "messageId": UUID().uuidString,
        "sentAt": "2026-01-01T00:00:00Z",
        "clientRequestId": UUID().uuidString,
        "action": "somethingALaterVersionAdded",
    ], options: [])
}

@Suite("MdoroServer over a line that carries bytes (REQ-COM-004 / REQ-COM-005 / REQ-SEC-003 / REQ-ERR-009)")
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
        // **carried back is not "about the same time"**. A one-second tolerance is far more than a
        // loopback round trip: a Mac answering with its own receipt time —
        // `TimeSyncPayload(t1: t2, ...)` — passes it every single time, which is exactly the value
        // this line exists to catch. Exact equality is what bites, and the instant chosen above is
        // what makes exact equality available.
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

    // REQ-COM-004: **a phone that hangs up is noticed from the read, not from the silence.**
    //
    // `Probe.cancel` closes this line the way the iPhone's own does (`WebSocketLink.cancel` on to
    // `NWConnection.cancel`), and a WebSocket closed cleanly leaves the far end's connection
    // `.ready` — no `.failed`, no `.cancelled` — so the state handler `MdoroServer.accept` installs
    // is never told. **The read is the only place the ending arrives**, which is what `LineRead`
    // is asked in `receive(on:counting:)`.
    //
    // **The bound is the whole of the claim.** `checkHeartbeat` reaches the same conclusion by
    // itself after fifteen seconds of silence (REQ-COM-005), so a test that simply waited would
    // pass against a read loop that heard nothing at all. `arrivalBudget` is ten, and the watch
    // cannot fire before fifteen seconds after the `welcome` that set `lastHeartbeatAt` — so a
    // hang-up seen inside the bound was seen by the read. What the fifteen seconds cost meanwhile
    // is a Mac showing a phone that has gone, and a loop re-arming into a read that comes back
    // empty at once, on the main actor, for every one of them.
    @Test func aPhoneThatHangsUpIsNoticedFromTheReadRatherThanTheSilence() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }
        holds(bench.server.connection != nil && bench.upstream.hangUps == 0,
              "REQ-SEC-001: the probe authenticated and the Mac is not holding a connection (hangUps=\(bench.upstream.hangUps)), so whatever is hung up on below is not the connection this test is about")

        phone.cancel()

        let hungUp = await bench.upstream.waitsForHangUp(upTo: arrivalBudget)
        holds(hungUp,
              "REQ-COM-004: the iPhone closed the line and the Mac did not notice inside \(arrivalBudget). Nothing is coming on that connection ever again, and until REQ-COM-005's silence watch expires at fifteen seconds the Mac says a phone is connected that is gone — while the read loop re-arms through the ending it was told, which on a finished connection comes back at once and with nothing on it.")
        holds(bench.server.connection == nil && bench.server.connectedDeviceName == nil,
              "the Mac reported the connection gone but is still holding it (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")) — the report and the hang-up have come apart, so what the iPhone sees and what the Mac believes no longer agree")
    }

    // REQ-ERR-009: **one broken message is thrown away; ten in a row mean the line is.** The Mac
    // has no reconnect of its own — the iPhone is always the end that dials — so what it does at
    // ten is hang up, and REQ-COM-004 on the other end turns that into the reconnect the clause
    // asks for.
    //
    // Three claims, in one run, because each rests on the one before it:
    //
    //   1. **nine are kept.** The receipt comes back, which says both that the line is here and
    //      that the nine were read off it (see the note at the top of this file for what that
    //      inference rests on). Nine is the count that bites: an implementation that hung up on
    //      the first, or the second, or the fifth, fails here and nowhere else.
    //   2. **a message that decodes starts the run over.** The receipt in step 1 *is* that
    //      message, so nine more — eighteen unreadable messages in all — still leave the line
    //      standing. Without the `reset()` the line is gone by the tenth of those eighteen and the
    //      second receipt never arrives.
    //   3. **the tenth in a row ends it.**
    //
    // REQ-PRT-005 is the other half of step 1, and it is the half with the MUST on it: hanging up
    // before the count is reached is what that clause forbids outright.
    @Test func tenBrokenMessagesInARowEndTheConnectionAndOneThatDecodesStartsTheRunOver() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }

        for _ in 1..<BrokenMessageCounter.limit {
            let unreadable = try aValueThisVersionCannotRead()
            phone.sendRaw(unreadable)
        }
        try await receipt(from: phone, called: "nine unreadable messages in a row")
        holds(bench.upstream.hangUps == 0,
              "REQ-ERR-009 / REQ-PRT-005: the Mac hung up before \(BrokenMessageCounter.limit) unreadable messages had come in a row. REQ-ERR-009 is a SHOULD, but not this point — REQ-PRT-005 forbids in a MUST that a discarded message cost the connection before the count is reached, and the count is what the shared BrokenMessageCounter is for.")

        // The receipt just above decoded, so the run starts over on it. These nine make eighteen.
        for _ in 1..<BrokenMessageCounter.limit {
            let unreadable = try aValueThisVersionCannotRead()
            phone.sendRaw(unreadable)
        }
        try await receipt(from: phone, called: "nine more, after one message that decoded")
        holds(bench.upstream.hangUps == 0,
              "REQ-ERR-009: eighteen unreadable messages with one readable one in the middle cost the connection. The requirement says *in a row*, and a message that decodes is what ends a row — without that the count is a lifetime total and any long-lived connection reaches ten eventually.")

        for _ in 1...BrokenMessageCounter.limit {
            let unreadable = try aValueThisVersionCannotRead()
            phone.sendRaw(unreadable)
        }
        let hungUp = await bench.upstream.waitsForHangUp(upTo: arrivalBudget)
        holds(hungUp,
              "REQ-ERR-009: \(BrokenMessageCounter.limit) unreadable messages in a row and the Mac is still holding the connection. The Mac cannot reconnect — the iPhone is the end that dials — so hanging up is the whole of what it can do, and it is what sets REQ-COM-004's reconnect going on the other end. (\(bench.upstream.hangUps) hang-up(s) seen in all.)")
        holds(bench.server.connection == nil && bench.server.connectedDeviceName == nil,
              "the Mac reported the connection gone but is still holding it (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")) — the report and the hang-up have come apart, so what the iPhone sees and what the Mac believes no longer agree")
    }

    // REQ-PRT-005: **a type this version does not know is ignored, and ignoring is not discarding.**
    // The whole point of the exemption is that a later version may add a message without every
    // older Mac on the LAN falling over; count these as broken and the exemption is worth nothing,
    // because the tenth one hangs up the connection that the clause exists to keep.
    //
    // Twice the limit is sent, so a version of `handle` that counts them is not merely over the
    // line, it is twice over it — and one that counts them and resets on nothing is too. The count
    // is not asked for directly: the receipt afterwards is what says the line is still here, and a
    // line that is not here cannot answer.
    //
    // **This is the test the `try?` in `MdoroServer.handle` could not have passed once the counting
    // was added**, because that expression had no way to tell these bytes from the ones above.
    @Test func aTypeThisVersionDoesNotKnowIsIgnoredAndNotCountedAsBroken() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }

        for _ in 1...(BrokenMessageCounter.limit * 2) {
            let unknownType = try aTypeThisVersionDoesNotKnow()
            phone.sendRaw(unknownType)
        }
        try await receipt(from: phone, called: "twice the limit in messages of a type this version does not know")
        holds(bench.upstream.hangUps == 0,
              "REQ-PRT-005: messages of a type this version does not know were counted as broken and the connection was hung up. That exemption is what lets a later version add a message without older Macs dropping the iPhones that send it — counted, the tenth one ends the very connection the clause is there to keep.")
        holds(bench.server.connectedDeviceName == "Probe iPhone",
              "the Mac is no longer holding the connection it welcomed (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil"))")
    }

    // REQ-ERR-009 / REQ-SEC-003: **a stranger's rubbish is the stranger's.** `handle` is reached
    // before any `source === connection` gate — it has to be, since the hello that makes a
    // connection the one on record arrives through it — so every unreadable byte anyone on this LAN
    // cares to send is read by the same handler that reads the iPhone's. What is asked here is that
    // none of it reaches the iPhone's connection: not the Mac's record of it, and not the line.
    //
    // **One short of the limit, on purpose.** What is watched is the discarding, and stopping at
    // nine keeps the hang-up out of it — a hang-up on the stranger's own line at ten is the right
    // answer, and telling it apart from the wrong one needs an observation this file cannot make
    // (see below). The receipt is taken **on the stranger's own line**, which is the only place it
    // means anything: the ordering the whole file rests on is within one connection.
    //
    // **What this does not catch — and nothing in this file does.**
    //
    // **Move the count off the read loop and onto the server** — one run of ten shared by every
    // connection at once — and this test still passes, as does every other test in this file and in
    // `BrokenMessageCounterTests`. The mutation is a real one: `handle` runs before the gate, so a
    // shared run lets anyone who can reach this port put nine unreadable messages in and have the
    // paired iPhone hung up by the tenth, whoever sends it.
    //
    // **Catching it needs a moment where the stranger's messages are known to have been handled and
    // the run is known to still be standing, and there is no such moment.** Everything the server
    // answers is a message that decodes, so observing arrival resets the very run that would have
    // to be left standing — under that mutation a round trip on *either* line resets the one shared
    // count. And an unreadable message below the limit has no observable effect at all: no reply,
    // no record, nothing. Ordering across two connections is not something this file can establish
    // either; TCP gives it within one line and nothing gives it between two.
    //
    // **So the guard against that mutation is the shape of `receive(on:counting:)` and not a test.**
    // The count is a parameter of the read loop, and `accept` starts one loop per connection — there
    // is no server-wide place for it to be put without changing that signature. Written down here
    // rather than left for the next reader to rediscover.
    @Test func aStrangersUnreadableMessagesAreDiscardedWithoutTouchingTheIPhonesConnection() async throws {
        let bench = try await raiseServer()
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }
        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }

        for _ in 1..<BrokenMessageCounter.limit {
            let unreadable = try aValueThisVersionCannotRead()
            stranger.sendRaw(unreadable)
        }
        // The receipt says those nine were taken off this line and handled before it. It is also a
        // message that decodes, so it starts this connection's run over — nothing below leans on
        // the run still standing, which is the whole of the limitation written up above.
        try await receipt(from: stranger, called: "the stranger's nine unreadable messages")

        holds(bench.upstream.hangUps == 0,
              "REQ-ERR-009 / REQ-SEC-003: nine unreadable messages from a connection that never authenticated cost the iPhone its connection. They are the stranger's to be discarded — the limit was not reached on any line, and nothing in them was the iPhone's.")
        holds(bench.server.connectedDeviceName == "Probe iPhone",
              "the Mac stopped holding the connection it welcomed (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")) while the only thing to arrive was rubbish on somebody else's line")
        // And the line itself, not just the Mac's record of it.
        try await receipt(from: phone, called: "the authenticated connection, after the stranger's nine")
    }
}

// MARK: - The end of a line, handed to the read loop

// REQ-COM-004: **what the read loop does when a read says the line is over.**
//
// Two things, and until `ServerLineReading` existed neither could be observed at all:
//
//   1. **the connection is handed back** — `connection.cancel()` in the `.end` arm. Delete that
//      line and every test in this file above goes on passing: the two they watch
//      (`connectionChanged`, `MdoroServer.connection`) both come from `handleDisconnect`, which
//      runs either way.
//   2. **the loop stops asking.** A read on a finished connection comes back at once and with
//      nothing on it, so a loop that re-armed through the ending turns on the main actor for the
//      fifteen seconds until REQ-COM-005's silence watch expires. **That hot loop is the fault this
//      whole line of work began with**, and nothing asked about it.
//
// **Why these two live in this file rather than a new one.** Everything else about them is
// wire-free — the reads below are made up by the test and no peer sends anything — but claim 1 is
// read off `NWConnection.state`, and a connection that was never started has no state to move: the
// framework updates it from the handler installed at `start(queue:)`. So the line has to be a real
// one that really came up, which is `raiseServer` and `connectedProbe`, which are here. It is the
// same observation `ListenerFoldingTests` makes of a cancelled `NWListener`, on the same footing.
//
// **The line these run against is a stranger's**, and that is the case the `.end` arm's own comment
// singles out: `accept` starts a read loop on every incoming connection, but only an accepted hello
// makes one `self.connection`, so `handleDisconnect` refuses a stranger's line and no other path in
// the class would ever cancel it. If the `.end` arm does not, nobody does — which makes it the one
// line whose cancel can be seen from outside.

// The read loop's one call into the transport, taken. **Nothing is ever completed on its own**: a
// read handed out here stays outstanding until the test delivers it, so a loop that re-armed when
// it should have stopped shows up as a second request and not as a spin.
@MainActor
private final class HeldReads: ServerLineReading {
    private(set) var lines: [NWConnection] = []
    private var outstanding: [ServerLineRead] = []
    private var waiting: (needed: Int, ticket: Int, continuation: CheckedContinuation<Void, Never>)?
    private var tickets = 0

    var timesArmed: Int { lines.count }

    func read(from connection: NWConnection, completion: @escaping ServerLineRead) {
        lines.append(connection)
        outstanding.append(completion)
        if let pending = waiting, lines.count >= pending.needed {
            waiting = nil
            pending.continuation.resume()
        }
    }

    // Wait until the loop has asked for `count` reads in all, or give up. **Nothing is polled** —
    // this is resumed from `read` above, on the main actor, which is the actor the loop needs to ask
    // on at all. Same shape as `Upstream.waitsForHangUp`, and for the same reason.
    //
    // **There is one waiting slot, and a second waiter would take it silently.** The first waiter
    // would then sit there until its own deadline and report a timeout that never had anything to
    // do with the server — a test that fails for a reason nobody can read, which is the shape this
    // repository keeps being caught by. So a second waiter traps here instead, where the line
    // number says which call did it. **A comment saying "do not wait twice" would hold nothing.**
    func waitsForReads(_ count: Int, upTo budget: Duration) async -> Bool {
        if timesArmed >= count { return true }
        if case .some = waiting {
            preconditionFailure("HeldReads has one waiting slot and something is already in it: this call would take it from a waiter that is still suspended, and that waiter would then run out its own budget and blame the server for it. Wait for one thing at a time, or give this double a queue of waiters.")
        }
        tickets += 1
        let ticket = tickets
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            self?.giveUpWaiting(ticket)
        }
        defer { deadline.cancel() }
        // The deadline sleeps before it can resume anything, so the registration below is always in
        // place first — there is no window in which a resumption is lost.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting = (count, ticket, continuation)
        }
        return timesArmed >= count
    }

    // **The ticket is which wait this deadline was started for.** `deadline.cancel()` is asked for
    // when a wait returns and is not instant, so a deadline belonging to a wait that is already
    // over could otherwise arrive and cut short the next one — a wait that ends early reads as the
    // loop never arming, which is the same unreadable failure the precondition above is against.
    private func giveUpWaiting(_ ticket: Int) {
        guard let pending = waiting, pending.ticket == ticket else { return }
        waiting = nil
        pending.continuation.resume()
    }

    // Answer the oldest read still outstanding, in `NWConnection.receiveMessage`'s own four values.
    // What they mean is not decided here: they go to `LineRead.of` through the loop, by way of this
    // target's own `webSocketFrame` translation, exactly as a read off the wire would.
    func deliver(
        data: Data? = nil, frame: NWProtocolWebSocket.Opcode? = nil, isComplete: Bool = true
    ) -> Bool {
        guard !outstanding.isEmpty else { return false }
        let completion = outstanding.removeFirst()
        let context = frame.map {
            NWConnection.ContentContext(
                identifier: "delivered", metadata: [NWProtocolWebSocket.Metadata(opcode: $0)]
            )
        }
        completion(data, context, isComplete, nil)
        return true
    }
}

// Cancellation is asked for on one queue and settles on another, so it is waited for rather than
// read straight after — the same wait `ListenerFoldingTests` makes of a listener. The bound below is
// far longer than it should take and short enough to fail a run rather than hang it.
//
// **What running out means is two things, and this cannot tell them apart** — so the message at the
// call site names both, in the order they are worth looking at, and it reads the bound from here so
// that raising the number cannot leave the sentence saying the old one.
private let cancelBound = Duration.seconds(2)

private func settlesAsCancelled(_ connection: NWConnection) async -> Bool {
    let deadline = ContinuousClock.now + cancelBound
    while ContinuousClock.now < deadline {
        if case .cancelled = connection.state { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    // Asked once more after the bound: a sleep that overran is not an answer.
    if case .cancelled = connection.state { return true }
    return false
}

@Suite("What the read loop does with the end of a line (REQ-COM-004)")
@MainActor
struct ServerReadLoopEndingTests {

    // Both halves of the `.end` arm, in one run, because the second rests on the first having been
    // reached. **`holds` records and carries on**, so a mutation that breaks one is not hidden by
    // the other failing first.
    @Test func anEndingHangsTheLineUpAndStopsTheLoop() async throws {
        let reads = HeldReads()
        let bench = try await raiseServer(reads: reads)
        defer { bench.server.stop() }

        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }
        // Every line this loop was given, handed back before the test returns. The one below is
        // cancelled by the code under test; this is for the run where it is not.
        defer { for opened in reads.lines { opened.cancel() } }

        let armed = await reads.waitsForReads(1, upTo: arrivalBudget)
        guard armed else {
            throw Wrong(diagnose("REQ-COM-004: a connection reached the listener and went ready, and the server never asked to read from it inside \(arrivalBudget) — `accept` starts the read loop, so nothing below has a loop to observe"))
        }
        let line = try #require(reads.lines.first, "the read loop was armed without a connection")

        // REQ-COM-004: a completed read carrying no frame and no bytes. It is the ending as the
        // transport reports it when there was no close frame to hand over, and `LineRead.of` is what
        // says so — this test states the read, not the answer.
        holds(reads.deliver(), "no read was outstanding to answer — the loop had already stopped asking before it was told anything")

        let cancelled = await settlesAsCancelled(line)
        holds(cancelled,
              "REQ-COM-004: \(describe(cancelBound)) after the read said this line was over, the connection has not reached `.cancelled`. **Two things put it here and this observation cannot tell them apart. Read them in this order.** (a) **The `.end` arm no longer calls `connection.cancel()`.** That is where to look first and it is the likely one: this line never said hello, so `handleDisconnect` refuses it and `checkHeartbeat` and `stop` reach only the connection the Mac is holding — no other path in MdoroServer would ever cancel it, and an `NWConnection` nobody cancels keeps its endpoint and its path monitor for as long as it is held. (b) The `cancel()` is still there and `NWConnection.state` did not settle on `.cancelled` within the bound. **Nothing on record says how long that takes**: `docs/PLATFORM.md` has no entry for it, and this is the first test in the project to stand on that transition — `ListenerFoldingTests` makes the same observation of an `NWListener`, which is a different type and says nothing about this one. **So read the `.end` arm before touching the bound.** If the `cancel()` is gone, (a) is the answer and the bound is innocent; if it is still there, (b) is what is left and it is worth writing down in `docs/PLATFORM.md` rather than absorbing here.")

        // **The ending has been acted on by the time this is read.** Either the cancel settled, or
        // the whole of `cancelBound` went by with the main actor free — and a re-arm is the next
        // statement after the `.end` arm, not something that arrives late. So this stands whichever
        // way the observation above went, which is why it is a separate `holds` and not a follow-on.
        holds(reads.timesArmed == 1,
              "REQ-COM-004: the loop was told the line was over and asked for another read (\(reads.timesArmed) asked for in all). On a finished connection that read comes back at once and with nothing on it, so this is a turn on the main actor for every one of the fifteen seconds until REQ-COM-005's silence watch expires — which is the backstop for this, not a substitute.")
    }

    // **A loop that stopped asking for every read would pass the test above.** So the other side has
    // to be shown: a read that is not an ending arms it again. This one is a ping — the transport
    // answers those itself, and `LineRead.of` reads it as neither a message nor an ending — so it
    // travels the `.skip` arm without anything being handed upward.
    @Test func aReadThatIsNotAnEndingArmsTheLoopAgain() async throws {
        let reads = HeldReads()
        let bench = try await raiseServer(reads: reads)
        defer { bench.server.stop() }

        let stranger = try await strangerProbe(on: bench)
        defer { stranger.cancel() }
        defer { for opened in reads.lines { opened.cancel() } }

        let armed = await reads.waitsForReads(1, upTo: arrivalBudget)
        guard armed else {
            throw Wrong(diagnose("REQ-COM-004: a connection reached the listener and went ready, and the server never asked to read from it inside \(arrivalBudget)"))
        }
        let line = try #require(reads.lines.first, "the read loop was armed without a connection")

        holds(reads.deliver(frame: .ping), "no read was outstanding to answer")

        let armedAgain = await reads.waitsForReads(2, upTo: arrivalBudget)
        holds(armedAgain,
              "REQ-COM-004: a ping was read off the line and the loop stopped reading (\(reads.timesArmed) read(s) asked for in all). The transport answers pings by itself and nothing is handed upward, so a line that is perfectly healthy goes deaf — and REQ-COM-005's silence watch then hangs it up fifteen seconds later, with everything else green.")

        var stillUp = true
        if case .cancelled = line.state { stillUp = false }
        holds(stillUp,
              "REQ-COM-004: a ping hung the connection up. `LineRead.of` reads a ping as neither a message nor an ending, and the transport has already answered it — hanging up here would end a healthy line at the first ping the peer sends.")
    }
}

// MARK: - Why a connection ended, in the log

// REQ-ERR-010 / Decision 0018: **which ending each way out of a connection is written down as.**
//
// The reader of the diagnostic log is a stranger seeing it pasted into an issue, and every ending
// used to reach them as the one line `conn up=no` — a phone that had gone quiet for fifteen seconds
// (REQ-COM-005), a line the transport ended (REQ-COM-004), a token the user revoked (REQ-SEC-002),
// ten unreadable messages in a row (REQ-ERR-009) and a fold of the listener all wrote that same
// line and nothing else. No clause asks for these lines; the reader Decision 0018 wrote the log for
// is the whole of why they exist, which is the same footing `ServerRefusalLogTests` stands on.
//
// **Why they live in this file.** Every one of them needs a connection the Mac has accepted, and
// `MdoroServer.connection` is set in one place only — `settle`, reached from a hello that arrived on
// a real incoming connection. The bench that provides one is here, and so is the seam
// (`HeldReads`) that can hand the read loop an ending without a peer having to produce one. The
// words themselves, and the number in `silent`, are checked without any of this in
// `ConnectionEndingTests`.
//
// **What is read is the file, not the fields handed in** — the same way `ServerRefusalLogTests`
// reads a refusal, because what a reader on an issue gets is the file.

// One event per line: `timestamp LEVEL code key=value ...`. Header lines start with `#`.
private struct LoggedLine {
    let level: String
    let code: String
    let fields: [String: String]

    init?(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, !line.hasPrefix("#") else { return nil }
        level = parts[1]
        code = parts[2]
        fields = parts.dropFirst(3).reduce(into: [:]) { result, part in
            guard let separator = part.firstIndex(of: "=") else { return }
            result[String(part[part.startIndex..<separator])] = String(part[part.index(after: separator)...])
        }
    }
}

// A log of this test's own, over a scratch directory, so the file can be read back without the log
// the user collects being touched.
@MainActor
private struct Recording {
    let log: DiagnosticLog
    let directory: URL

    init() {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MdoroConnectionEndings-\(UUID().uuidString)", isDirectory: true)
        log = DiagnosticLog(directory: directory)
        log.open(preset: Preset.standard(), settings: AppSettings())
    }

    var text: String {
        (try? String(
            contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
            encoding: .utf8
        )) ?? ""
    }

    var lines: [LoggedLine] { text.split(separator: "\n").compactMap { LoggedLine(String($0)) } }

    var endings: [LoggedLine] { lines.filter { $0.code == ConnectionEndingLine.code } }

    // REQ-SEC-004: the line written when a connection request's own line ended before the user
    // answered. A code of its own, so it is counted apart from the endings above.
    var approvalWithdrawals: [LoggedLine] {
        lines.filter { $0.code == ConnectionEndingLine.approvalWithdrawnCode }
    }

    func discard() { try? FileManager.default.removeItem(at: directory) }
}

// One ending, and the reason it says. Every test below asks the same three questions of it, so a
// second line nobody expected — two paths writing for one ending — fails rather than being read
// past.
@MainActor
private func theOneEnding(
    in recording: Recording, is expected: ConnectionEnding, _ context: String
) throws -> LoggedLine {
    let endings = recording.endings
    guard endings.count == 1 else {
        throw Wrong(diagnose("REQ-ERR-010: \(context) — the log holds \(endings.count) `\(ConnectionEndingLine.code)` line(s), not one. Written: [\(endings.map { $0.fields[ConnectionEndingLine.howKey] ?? "?" }.joined(separator: ", "))]. An ending with no line leaves `conn up=no` as the whole of what a reader gets; two lines for one ending means two paths are writing for it. **A `\(ConnectionEnding.heartbeatTimeout.rawValue)` in that list is this run taking longer than REQ-COM-005's fifteen seconds** — these probes send no `heartbeat`, so the silence watch reaches them in the end — and it says nothing about the path under test."))
    }
    let ending = endings[0]
    holds(ending.fields[ConnectionEndingLine.howKey] == expected.rawValue,
          "REQ-ERR-010: \(context) — the log says `\(ConnectionEndingLine.howKey)=\(ending.fields[ConnectionEndingLine.howKey] ?? "nothing")`, not `\(expected.rawValue)`. The word is the whole of what tells this ending from the others, so a reader on an issue is now being told the wrong thing rather than nothing.")
    holds(ending.level == expected.level.rawValue,
          "REQ-ERR-010: \(context) — written at \(ending.level), not \(expected.level.rawValue). A reader scanning for trouble reads that column; a routine ending marked WARN teaches them to skip it.")
    return ending
}

// REQ-COM-005: the seconds in `silent`, read back as a number. A field that is missing, or that
// holds something that is not a number, is not a smaller fault than a wrong one — it is the field
// not being there at all.
@MainActor
private func silentSeconds(of ending: LoggedLine, _ context: String) throws -> Double {
    let written = ending.fields[ConnectionEndingLine.silentKey]
    guard let written, let seconds = Double(written) else {
        throw Wrong(diagnose("REQ-COM-005 / REQ-ERR-010: \(context) — `\(ConnectionEndingLine.silentKey)` reads `\(written ?? "nothing")`. How long the phone had been quiet is the one thing `lastHeartbeatAt` can say and the only value the clean-up in `handleDisconnect` destroys, so if it is not on this line it is nowhere."))
    }
    return seconds
}

@Suite("What the log says about how a connection ended (REQ-ERR-010)")
@MainActor
struct ConnectionEndingLogTests {

    // REQ-COM-005: **the ending the author's own log could not explain.** On 2026-09-19 a
    // disconnection left one line, `conn up=no`, and a heartbeat that had stopped fifteen seconds
    // earlier read exactly the same as a line the network had dropped.
    //
    // **The seconds are the half that is easy to lose.** `handleDisconnect` clears
    // `lastHeartbeatAt` — at the moment an ending needs explaining — so a line written a line later
    // says `unset`, and one that reads the clock afresh says `0.0` while claiming a timeout. The
    // ageing here is 120 seconds, so either mistake is a failure and not a rounding.
    @Test func aPhoneThatWentQuietSaysSoAndSaysForHowLong() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let bench = try await raiseServer(diagnostics: recording.log)
        defer { bench.server.stop() }

        let deviceName = "UNIQUEENDINGDEVICENAME"
        let phone = try await authenticatedProbe(named: deviceName, on: bench)
        defer { phone.cancel() }

        // REQ-COM-005: fifteen seconds of silence, without fifteen seconds being spent. `now` is
        // the judgement's, and the line is supposed to carry that same `now`.
        let aged: TimeInterval = 120
        bench.server.checkHeartbeat(now: Date().addingTimeInterval(aged))

        holds(bench.server.connection == nil,
              "REQ-COM-005: the silence watch was given a `now` \(aged)s past the last beat and did not hang up. Nothing below is about an ending that happened.")
        let ending = try theOneEnding(in: recording, is: .heartbeatTimeout, "a phone that stopped beating")
        let seconds = try silentSeconds(of: ending, "a phone that stopped beating")
        holds(seconds > aged - 5 && seconds < aged + 5,
              "REQ-COM-005 / REQ-ERR-010: the beat was last heard \(aged)s before the judgement and the line says \(seconds)s. Two things put it here: the record is written after `handleDisconnect` has cleared `lastHeartbeatAt` (which reads as `unset`, so it would not be a number at all), or it measures against a clock of its own instead of the `now` the judgement used — and then the reason says a timeout while the number says the phone had just beaten.")

        // Decision 0018: what is written is a word and a number. The device name is in the
        // server's hands throughout — `connectedDeviceName` is set from the hello — and must not be
        // in the file.
        holds(!recording.text.contains(deviceName),
              "REQ-ERR-010: `\(deviceName)` appears in the diagnostic log. The endings carry a fixed word and numbers precisely so that nothing of the user's has a route in.")
    }

    // REQ-COM-004: **the ending a read reports.** A close frame, a read that failed, or a completed
    // read with neither frame nor bytes on it all mean the line is over, and a peer that closes
    // politely leaves the connection `.ready` — so this is the only place it is heard, and the log
    // has to be able to say that is what happened.
    //
    // The reads are taken through the seam, so the ending is handed over rather than waited for.
    // The hello goes in the same way: with `reads` held, nothing off the wire reaches the server.
    @Test func aLineThatTheReadSaidWasOverIsWrittenDownAsThat() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let reads = HeldReads()
        let bench = try await raiseServer(reads: reads, diagnostics: recording.log)
        defer { bench.server.stop() }

        let deviceName = "iPhone that hung up"
        let phone = try await connectedProbe(to: bench, called: deviceName)
        defer { phone.cancel() }
        defer { for opened in reads.lines { opened.cancel() } }

        guard await reads.waitsForReads(1, upTo: arrivalBudget) else {
            throw Wrong(diagnose("REQ-COM-004: a connection reached the listener and went ready, and the server never asked to read from it inside \(arrivalBudget) — there is no read loop to hand an ending to."))
        }

        let hello = try MessageCoder.encode(Envelope(body: ClientMessage.hello(HelloPayload(deviceName: deviceName))))
        holds(reads.deliver(data: hello, frame: .text), "no read was outstanding to hand the hello to")
        // The loop arms again after it has dispatched, so a second read being asked for is what says
        // the hello has been through `settle`.
        guard await reads.waitsForReads(2, upTo: arrivalBudget), bench.server.connection != nil else {
            throw Wrong(diagnose("REQ-SEC-003: the hello was handed to the read loop and the Mac is holding no connection (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")). `handleDisconnect` refuses a line the Mac never accepted, so nothing below would be about an ending it writes down."))
        }
        holds(recording.endings.isEmpty,
              "REQ-ERR-010: an ending was written before anything ended. Accepting a hello is not an ending, and a line saying otherwise sends a reader looking for a disconnection that never happened.")

        // REQ-COM-004: a completed read carrying no frame and no bytes. What it means is
        // `LineRead.of`'s to say; this states the read.
        holds(reads.deliver(), "no read was outstanding to answer — the loop had stopped asking before it was told anything")
        guard await bench.upstream.waitsForHangUp(upTo: arrivalBudget) else {
            throw Wrong(diagnose("REQ-COM-004: the read said the line was over and the Mac is still holding the connection. Nothing below is about an ending that happened."))
        }

        _ = try theOneEnding(in: recording, is: .lineEnded, "a read that said the line was over")
    }

    // REQ-ERR-009: **ten unreadable messages in a row, and the log says how long the run was.** The
    // number is what separates this from every other ending for a reader who is being told the Mac
    // hung up on their phone: nine of these leave no line at all, by REQ-PRT-005's MUST.
    @Test func aRunOfBrokenMessagesIsWrittenDownWithTheLengthOfTheRun() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let bench = try await raiseServer(diagnostics: recording.log)
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }

        for _ in 1...BrokenMessageCounter.limit {
            let unreadable = try aValueThisVersionCannotRead()
            phone.sendRaw(unreadable)
        }
        guard await bench.upstream.waitsForHangUp(upTo: arrivalBudget) else {
            throw Wrong(diagnose("REQ-ERR-009: \(BrokenMessageCounter.limit) unreadable messages in a row and the Mac is still holding the connection (\(bench.upstream.hangUps) hang-up(s) seen). Nothing below is about an ending that happened."))
        }

        let ending = try theOneEnding(in: recording, is: .brokenMessageRun, "a run of unreadable messages")
        holds(ending.fields[ConnectionEndingLine.brokenKey] == String(BrokenMessageCounter.limit),
              "REQ-ERR-009 / REQ-ERR-010: the run that ended the line reads `\(ConnectionEndingLine.brokenKey)=\(ending.fields[ConnectionEndingLine.brokenKey] ?? "nothing")`, and the limit is \(BrokenMessageCounter.limit). **The counter cannot be asked for this after the fact** — it starts over at the tenth by design, so its count is zero by the time the line is written, and the number has to come from the limit itself.")
    }

    // REQ-SEC-002 / Decision 0040: **a revocation is an ending too, and it is not a failure.** The
    // user pressed a button; the log saying so is what keeps a reader from hunting for a network
    // fault at that timestamp.
    @Test func aRevokedTokenTakesItsConnectionDownAndSaysThatIsWhy() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let bench = try await raiseServer(diagnostics: recording.log)
        defer { bench.server.stop() }

        let phone = try await authenticatedProbe(named: "Probe iPhone", on: bench)
        defer { phone.cancel() }

        let token = try #require(bench.server.connectedTokenValue,
                                 "REQ-SEC-002: the hello was accepted and the server is holding no token for it, so there is nothing a revocation could find")
        bench.server.disconnect(tokenValue: token)

        holds(bench.server.connection == nil,
              "REQ-SEC-002: the token this connection authenticated with was revoked and the connection is still up. Nothing below is about an ending that happened.")
        _ = try theOneEnding(in: recording, is: .tokenRevoked, "a revoked token")
    }

    // **The two endings that make no `connectionChanged` callback at all**, which is why they are
    // the two that reached the log as nothing whatsoever rather than as `conn up=no`:
    //
    //   - REQ-SEC-004: a second phone's hello is accepted and the standing line is folded to make
    //     room. The Mac never stops being connected, so nothing is reported upward.
    //   - `stop()`: the connection goes with the listener. `stopServer()` writes `server.stop`
    //     beside it, but **the fold at the top of `start()` writes nothing**, and a rename goes
    //     through that fold.
    //
    // Both in one bench, because the first leaves a connection standing for the second to end.
    @Test func aLineFoldedToMakeRoomAndOneFoldedWithTheListenerBothSayWhichTheyWere() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let bench = try await raiseServer(diagnostics: recording.log)
        // The folds below are the test's own; this one is for the run that throws before reaching
        // them, and it holds nothing by the time they have run.
        defer { bench.server.stop() }

        let first = try await authenticatedProbe(named: "First iPhone", on: bench)
        defer { first.cancel() }
        let second = try await authenticatedProbe(named: "Second iPhone", on: bench)
        defer { second.cancel() }

        let displaced = try theOneEnding(in: recording, is: .displacedByNewHello,
                                        "a standing line folded to make room for a new hello")
        _ = try silentSeconds(of: displaced, "a standing line folded to make room for a new hello")
        holds(bench.upstream.hangUps == 0,
              "REQ-SEC-004: the Mac reported itself disconnected while accepting a second phone. The accept folds the standing line on its way in and stays connected throughout — this test's reading of the line above rests on that, and so does the `conn up=no` a reader will not find next to it.")

        bench.server.stop()

        let endings = recording.endings
        guard endings.count == 2 else {
            throw Wrong(diagnose("REQ-ERR-010: the listener was folded over a live connection and the log holds \(endings.count) ending line(s), not 2. Written: [\(endings.map { $0.fields[ConnectionEndingLine.howKey] ?? "?" }.joined(separator: ", "))]. `stop()` makes no callback, so this line is the only trace the fold leaves — the rename that goes through the fold at the top of `start()` writes nothing else at all."))
        }
        holds(endings[1].fields[ConnectionEndingLine.howKey] == ConnectionEnding.serverStopped.rawValue,
              "REQ-ERR-010: the fold is written as `\(endings[1].fields[ConnectionEndingLine.howKey] ?? "nothing")`, not `\(ConnectionEnding.serverStopped.rawValue)`.")

        // A second fold with nothing connected is silent: there is no ending to explain, and a line
        // for it would put a disconnection in the log where none happened. `stop()` is reached this
        // way on every path that raises a listener.
        bench.server.stop()
        holds(recording.endings.count == 2,
              "REQ-ERR-010: folding a server that holds no connection wrote an ending (\(recording.endings.count) in all). Every `start()` folds first, so a line here would report a disconnection at every launch.")
    }
}

// MARK: - A connection request whose line ended before it was answered

// REQ-SEC-004 / REQ-UIX-004: **the phone that was asking went away while the banner was up.**
//
// `pendingApproval` holds a connection the Mac has *not* accepted, so `handleDisconnect`'s
// `closed === connection` refuses its ending — and nothing else releases the question but the
// user's answer and the 60-second timeout. Before `foldPendingApproval` the record outlived the
// line, and an "Allow" pressed afterwards ran `settle(.accept)` on a finished connection: it became
// `self.connection`, the Mac reported itself connected, no read ever came back, and the lie stood
// until REQ-COM-005's silence watch noticed fifteen seconds later.
//
// **Two ways in, and they are separate tests because they are separate code paths.** A read can
// say the line is over (`.end`, the only place a polite close is heard — the connection stays
// `.ready`), or the transport can move the connection to `.failed` / `.cancelled` and tell the
// state handler `accept` installed. A fix that only watched the read loop would leave the second
// one exactly as it was.
//
// **These live in this file for the same reason `ConnectionEndingLogTests` does**: reaching
// `pendingApproval` at all takes a hello over an incoming connection, and the bench that provides
// one — with the seam that can hand the read loop bytes and endings without a peer producing them —
// is here.

// One withdrawal, and the word it carries. Asked the same way `theOneEnding` is, and for the same
// reason: a second line means two paths are writing for one event, and none at all means the
// reader of a pasted log is told nothing about a banner that vanished on its own.
@MainActor
private func theOneWithdrawal(
    in recording: Recording, is expected: ConnectionEnding, _ context: String
) throws -> LoggedLine {
    let written = recording.approvalWithdrawals
    guard written.count == 1 else {
        throw Wrong(diagnose("REQ-SEC-004 / REQ-ERR-010: \(context) — the log holds \(written.count) `\(ConnectionEndingLine.approvalWithdrawnCode)` line(s), not one. Written: [\(written.map { $0.fields[ConnectionEndingLine.howKey] ?? "?" }.joined(separator: ", "))]. The banner coming down without the user touching it leaves no other trace of any kind: the question was never accepted, so no `\(ConnectionEndingLine.code)` and no `conn up=no` is written for it either."))
    }
    let line = written[0]
    holds(line.fields[ConnectionEndingLine.howKey] == expected.rawValue,
          "REQ-SEC-004 / REQ-ERR-010: \(context) — the log says `\(ConnectionEndingLine.howKey)=\(line.fields[ConnectionEndingLine.howKey] ?? "nothing")`, not `\(expected.rawValue)`. How the line went is the whole of what this line adds to the fact that the question is gone.")
    holds(line.level == expected.level.rawValue,
          "REQ-SEC-004 / REQ-ERR-010: \(context) — written at \(line.level), not \(expected.level.rawValue). The level is the ending's own (`ConnectionEnding.level`): a transport that failed under a pending line failed just as it would under a held one, and a reader scanning that column should not have to know which line it was.")
    holds(recording.endings.isEmpty,
          "REQ-ERR-010: \(context) — a `\(ConnectionEndingLine.code)` was written for a line the Mac never held (\(recording.endings.count) in all). That line is written beside `conn up=no` and says why the connection *the Mac was holding* ended, and it carries `\(ConnectionEndingLine.silentKey)`, which is read from `lastHeartbeatAt` — the authenticated connection's stamp, not this line's. A reader would count a disconnection that never happened, with a number describing a different connection.")
    return line
}

// REQ-SEC-004: a hello that the Mac answers by asking the user, handed to the read loop through the
// seam. **Both ends of the asking line are returned**: `line` is the server's, which is what the
// tests below end, and `asking` is this test's own, which the caller hands back — an `NWConnection`
// nobody cancels goes on holding its endpoint and its path monitor for the rest of the run.
@MainActor
private func aQuestionWaitingOn(
    _ bench: Bench, reads: HeldReads, from deviceName: String
) async throws -> (asking: Probe, line: NWConnection) {
    bench.upstream.answersHelloWith = { .needsUserApproval(requestingDeviceName: $0.deviceName) }
    let asking = try await connectedProbe(to: bench, called: deviceName)
    guard await reads.waitsForReads(1, upTo: arrivalBudget) else {
        asking.cancel()
        throw Wrong(diagnose("REQ-COM-004: a connection reached the listener and went ready, and the server never asked to read from it inside \(arrivalBudget) — there is no read loop to hand a hello to."))
    }
    let hello = try MessageCoder.encode(Envelope(body: ClientMessage.hello(HelloPayload(deviceName: deviceName))))
    holds(reads.deliver(data: hello, frame: .text), "no read was outstanding to hand the hello to")
    // The loop arms again only after `dispatch` has returned, so a second read being asked for is
    // what says the hello has been through `settle`.
    guard await reads.waitsForReads(2, upTo: arrivalBudget), bench.server.hasPendingApproval else {
        asking.cancel()
        throw Wrong(diagnose("REQ-SEC-004: the hello was handed to the read loop and no question is waiting (hasPendingApproval=\(bench.server.hasPendingApproval), connection held=\(bench.server.connection != nil)). Nothing below would be about a banner that is up."))
    }
    guard bench.server.connection == nil else {
        asking.cancel()
        throw Wrong(diagnose("REQ-SEC-004: the hello that was answered with a question was accepted as well — the Mac is holding the connection (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")). Nothing is issued and nothing is held while the answer is `ask the user`."))
    }
    guard let line = reads.lines.first else {
        asking.cancel()
        throw Wrong(diagnose("the read loop was armed without a connection — `HeldReads` recorded \(reads.timesArmed) read(s) and no line to go with them"))
    }
    return (asking, line)
}

@Suite("A connection request whose line ends before it is answered (REQ-SEC-004)")
@MainActor
struct PendingApprovalEndingTests {

    // **The fault as it was reported, end to end**: the line ends, and then Allow is pressed.
    @Test func aReadThatSaysTheLineIsOverTakesTheQuestionWithIt() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let reads = HeldReads()
        let bench = try await raiseServer(reads: reads, diagnostics: recording.log)
        defer { bench.server.stop() }
        defer { for opened in reads.lines { opened.cancel() } }

        let question = try await aQuestionWaitingOn(bench, reads: reads, from: "iPhone that asked and left")
        defer { question.asking.cancel() }

        // REQ-COM-004: a completed read carrying no frame and no bytes — the ending as the transport
        // reports it when there was no close frame. What it means is `LineRead.of`'s to say.
        holds(reads.deliver(), "no read was outstanding to answer — the loop had stopped asking before it was told anything")
        guard await bench.upstream.waitsForApprovalSettled(upTo: arrivalBudget) else {
            throw Wrong(diagnose("REQ-SEC-004: the read said the asking line was over and the question was never settled (hasPendingApproval=\(bench.server.hasPendingApproval)). **`handleDisconnect` refuses this line — it is not the connection the Mac believed in — so the ending has to be heard somewhere else**, and `foldPendingApproval` is the only place it is. Left standing, the banner offers an Allow that lands on a finished connection."))
        }
        holds(bench.upstream.approvalsAsked == [false],
              "REQ-SEC-004: the question was settled as \(bench.upstream.approvalsAsked) rather than a single refusal. `resolveApproval(false)` is what lowers the banner and drops the hello the Authenticator is holding, and the two have to go together or the next device's hello is settled against this one's.")
        holds(!bench.server.hasPendingApproval,
              "REQ-SEC-004: the question is still waiting after the line it arrived on ended.")

        _ = try theOneWithdrawal(in: recording, is: .lineEnded, "a read that said the asking line was over")

        // **And now the press that used to be believed.** Nothing is waiting, so this is the same
        // no-op as pressing Allow twice; before the fold it reached `settle(.accept)` with a
        // finished connection and the Mac went on to report itself connected.
        bench.server.resolvePendingApproval(approved: true)
        holds(bench.server.connection == nil,
              "REQ-COM-013 / REQ-UIX-004: Allow was pressed after the asking line had ended and the Mac is now holding that line (connectedDeviceName=\(bench.server.connectedDeviceName ?? "nil")). No read will ever come back off it — nobody re-armed the loop — so this stands until REQ-COM-005's silence watch expires fifteen seconds later, with the screen saying `Connected` throughout.")
        holds(bench.upstream.connectedReports == 0,
              "REQ-UIX-004: the Mac was told it is connected (\(bench.upstream.connectedReports) time(s)) over a line that had ended. That report is what the screen and the menu bar read, and there is nothing at the other end of it.")
        holds(bench.upstream.approvalsAsked == [false],
              "REQ-SEC-004: pressing Allow on a question that is no longer there settled something (\(bench.upstream.approvalsAsked)). The Authenticator's held hello went with the line; issuing against it now would hand a token to a device that is gone.")
    }

    // **The other way a line ends, and the one a fix aimed at the read loop would miss.** The
    // transport moves the connection to `.cancelled` and tells the state handler `accept` installed;
    // no read is ever answered here, so the `.end` arm is not reached at all.
    @Test func aTransportThatEndsTheLineTakesTheQuestionWithItToo() async throws {
        let recording = Recording()
        defer { recording.discard() }
        let reads = HeldReads()
        let bench = try await raiseServer(reads: reads, diagnostics: recording.log)
        defer { bench.server.stop() }
        defer { for opened in reads.lines { opened.cancel() } }

        let question = try await aQuestionWaitingOn(bench, reads: reads, from: "iPhone the network dropped")
        defer { question.asking.cancel() }

        // The connection the question is waiting on, ended underneath it. **Nothing is delivered to
        // the read loop**, so the only account of this ending is the state handler's.
        question.line.cancel()
        guard await bench.upstream.waitsForApprovalSettled(upTo: arrivalBudget) else {
            throw Wrong(diagnose("REQ-SEC-004: the asking line was ended by the transport and the question was never settled (hasPendingApproval=\(bench.server.hasPendingApproval), reads asked for: \(reads.timesArmed)). **The read loop never heard this one** — no read was answered — so a fold that only watches the `.end` arm leaves this route exactly as it was: the banner stays up over a connection that is gone."))
        }
        holds(!bench.server.hasPendingApproval,
              "REQ-SEC-004: the question is still waiting after the transport ended the line it arrived on.")
        _ = try theOneWithdrawal(in: recording, is: .transportCancelled,
                                 "a line the transport ended while the question waited")
    }
}
