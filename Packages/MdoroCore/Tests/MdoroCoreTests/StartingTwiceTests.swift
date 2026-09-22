import Testing
import Foundation
@testable import MdoroCore

// **The Mac advertises itself exactly once**: `start()` runs once per process, and no listener
// is replaced without being folded first.
//
// Measured on the reader's machine: two `MdoroMac` processes, five `_mdoro._tcp` registrations
// (the Mac's own name, then that name `(2)` through `(5)` — the name itself is held back, the
// count is not). Pairing did not complete, three attempts running — the iPhone kept reaching a
// registration whose process was not the one holding the code, and got back `pairingModeNotActive`.
//
// Two faults met. `AppModel.start()` is called from a view's `.task`, which runs again every time
// that view appears, so reopening the main window started the app again; and `MdoroServer.start()`
// (like the `/info` server's, while `GET /info` existed — REQ-COM-002 v2.25 removed it) did not
// cancel the listener it was replacing, so each of those starts left the previous one listening
// and advertising. mDNSResponder renames a colliding registration rather than refusing it, so the
// leak shows up as numbers rather than as an error (`docs/PLATFORM.md`).
//
// These live here because `swift test` is what CI runs, and it cannot link the app targets — the
// same route `TestHostTests` and `ColorLiteralTests` take to rules that are kept outside this
// package. **The app targets carry the half that actually starts a listener and watches the old
// one go**; they do not run in CI, and this does.

private let macServer = "PomodoroMac/PomodoroMac/Server/MdoroServer.swift"
private let appModel = "PomodoroMac/PomodoroMac/AppModel.swift"

// A scan whose anchor has been renamed finds nothing to object to, and passes: every lookup here
// goes through `MissingAnchor` in `RepositorySources.swift`, which says which anchor is gone.

private func text(of path: String) throws -> String {
    withoutComments(try source(path))
}

// Everything a function does between its opening brace and the first `NWListener(` it builds.
private func beforeItBinds(_ path: String, _ signature: String) throws -> String {
    let body = try text(of: path)
    guard let opening = body.range(of: signature) else {
        throw MissingAnchor(path: path, anchor: signature)
    }
    let rest = body[opening.upperBound...]
    guard let bind = rest.range(of: "NWListener(") else {
        throw MissingAnchor(path: path, anchor: "NWListener( after \(signature)")
    }
    return String(rest[rest.startIndex..<bind.lowerBound])
}

// The first statement of a function, comments already gone.
private func firstStatement(_ path: String, _ signature: String) throws -> String {
    let body = try text(of: path)
    guard let opening = body.range(of: signature) else {
        throw MissingAnchor(path: path, anchor: signature)
    }
    return body[opening.upperBound...]
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .first { !$0.isEmpty } ?? ""
}

@Suite("Starting twice leaves one of everything")
struct StartingTwiceTests {

    // **Overwriting `self.listener` does not take the old one down.** Network.framework holds a
    // started listener for its queue; the port stays bound and the Bonjour name stays on the LAN
    // until something calls `cancel()`. Both servers now fold the previous listener first, and they
    // do it by calling the `stop()` each of them already had — a second copy of that tidying up is
    // a second copy to fall behind.
    @Test func theServerDoesNotBindBeforeFoldingWhatIsAlreadyUp() throws {
        let prelude = try beforeItBinds(macServer, "func start(callbacks: Callbacks) async throws -> UInt16 {")
        #expect(
            prelude.contains("stop()"),
            "\(macServer) binds a listener without folding the one already up, so the old port stays bound and its Bonjour registration stays on the network"
        )
    }

    // That is the only listener the Mac raises — the Bonjour registration rides it (REQ-COM-002
    // v2.25 removed `GET /info` and the listener that answered it). A second would be a second
    // registration, and the fold is not something the next author can be expected to know about,
    // so one cannot be added without this saying something about it.
    @Test func theMacRaisesNoListenerThisHasNotLookedAt() throws {
        let files = try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true)
        #expect(!files.isEmpty, "PomodoroMac/PomodoroMac could not be read; it moved, or its name changed")
        let binding = files
            .filter { $0.value.contains("NWListener(") }
            .keys
            .sorted()
        #expect(
            binding == ["MdoroServer.swift"],
            "the listeners the Mac raises are now \(binding) — a new one has to fold its predecessor too, or the reader gets another Bonjour registration"
        )
    }

    // REQ-COM-002 (v2.25): the Mac holds no HTTP server. `GET /info` was the only one, it was
    // never called, and the unauthenticated answer it gave is gone with it — everything it said
    // is in the TXT record or arrives on connecting.
    @Test func theMacAnswersNoHTTP() throws {
        for (name, body) in try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true) {
            #expect(
                !withoutComments(body).contains("HTTP/1.1"),
                "REQ-COM-002: \(name) writes an HTTP response, and the spec says the Mac has no HTTP server"
            )
        }
    }

    // REQ-COM-003: `advertisedWebsocketPort` is how `readvertise()` knows the Mac is on the air, and
    // `stop()` is reachable from production now (the pairing screen closing folds the server). A
    // fold that leaves the old port on record lets a later rename advertise a listener that no
    // longer exists — a TXT record on the LAN pointing at a dead port.
    @Test func foldingTheServerForgetsThePortItAdvertised() throws {
        let body = try text(of: appModel)
        let opening = try #require(
            body.range(of: "private func stopServer() {"),
            "\(appModel) no longer has stopServer()"
        )
        // The body, not a count of characters: see `bracedBody`.
        let fold = try bracedBody(openedBy: body[opening.upperBound...], "private func stopServer() {")
        #expect(
            fold.contains("advertisedWebsocketPort = 0"),
            "\(appModel) folds the server and keeps the advertised port on record, so a rename after the fold re-advertises a dead port"
        )
    }

    // `.task` belongs to a view, and a view appears again every time its window is opened. Making
    // each step safe on its own is not enough on its own: `start()` ends by awaiting `startServer()`,
    // so two calls in the same turn would both be past every guarded step before either had a
    // listener to guard. **The refusal has to be decided before anything suspends**, which means the
    // first statement of the function.
    @Test func theAppRefusesToStartASecondTime() throws {
        let opening = try firstStatement(appModel, "func start() {")
        #expect(
            opening == "guard !hasStarted else { return }",
            "\(appModel) does `\(opening)` before asking whether it has already started"
        )
        let body = try text(of: appModel)
        #expect(
            body.contains("hasStarted = true"),
            "nothing ever sets the flag, so the guard above never closes"
        )
    }

    // Refusing repetition is not the same as refusing a restart. What `stop()` took down may be
    // raised again, and if the flag stayed set the app could never come back up.
    @Test func stoppingLetsTheAppBeStartedAgain() throws {
        let body = try text(of: appModel)
        let opening = try #require(body.range(of: "func stop() {"), "\(appModel) no longer has stop()")
        // The body, not a count of characters: see `bracedBody`.
        let stopBody = try bracedBody(openedBy: body[opening.upperBound...], "func stop() {")
        #expect(
            stopBody.contains("hasStarted = false"),
            "\(appModel) stops without clearing the flag, so nothing can start it again"
        )
    }
}
