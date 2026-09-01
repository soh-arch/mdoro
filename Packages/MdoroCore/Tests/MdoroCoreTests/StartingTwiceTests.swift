import Testing
import Foundation
@testable import MdoroCore

// POL-114 / REQ-COM-002 / REQ-COM-003: **the Mac advertised itself several times over.**
//
// Measured on the reader's machine: two `MdoroMac` processes, five `_mdoro._tcp` registrations
// (`Lychee`, then `Lychee (2)` through `(5)`). Pairing did not complete, three attempts running —
// the iPhone kept reaching a registration whose process was not the one holding the code, and got
// back `pairingModeNotActive`.
//
// Two faults met. `AppModel.start()` is called from a view's `.task`, which runs again every time
// that view appears, so reopening the main window started the app again; and neither
// `MdoroServer.start()` nor `InfoHTTPServer.start()` cancelled the listener it was replacing, so
// each of those starts left the previous one listening and advertising. mDNSResponder renames a
// colliding registration rather than refusing it, so the leak shows up as numbers rather than as
// an error (`docs/PLATFORM.md`).
//
// These live here because `swift test` is what CI runs, and it cannot link the app targets — the
// same route `TestHostTests` and `ColorLiteralTests` take to rules that are kept outside this
// package. **The app targets carry the half that actually starts a listener and watches the old
// one go**; they do not run in CI, and this does.

private let macServer = "PomodoroMac/PomodoroMac/Server/MdoroServer.swift"
private let infoServer = "PomodoroMac/PomodoroMac/Server/ServerInfo.swift"
private let appModel = "PomodoroMac/PomodoroMac/AppModel.swift"

// **A scan whose anchor has been renamed finds nothing to object to, and passes.** That is the one
// failure these scans exist to prevent, arriving through the scans themselves, so a missing anchor
// is an error rather than an absence — the same reason `swiftFiles(under:)` refuses a directory
// that moved.
private struct MissingAnchor: Error, CustomStringConvertible {
    let path: String
    let anchor: String
    var description: String {
        "\(path) no longer contains `\(anchor)` — it was renamed, and this scan was watching nothing"
    }
}

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

@Suite("Starting twice leaves one of everything (POL-114)")
struct StartingTwiceTests {

    // **Overwriting `self.listener` does not take the old one down.** Network.framework holds a
    // started listener for its queue; the port stays bound and the Bonjour name stays on the LAN
    // until something calls `cancel()`. Both servers now fold the previous listener first, and they
    // do it by calling the `stop()` each of them already had — a second copy of that tidying up is
    // a second copy to fall behind.
    @Test func neitherServerBindsBeforeFoldingWhatIsAlreadyUp() throws {
        let anchors = [
            (macServer, "func start(callbacks: Callbacks) async throws -> UInt16 {"),
            (infoServer, "func start() async throws -> UInt16 {"),
        ]
        for (path, signature) in anchors {
            let prelude = try beforeItBinds(path, signature)
            #expect(
                prelude.contains("stop()"),
                "POL-114: \(path) binds a listener without folding the one already up, so the old port stays bound and its Bonjour registration stays on the network"
            )
        }
    }

    // The two above are every listener the Mac raises. A third would be a third registration, and
    // the fold is not something the next author can be expected to know about, so it cannot be
    // added without this saying something about it.
    @Test func theMacRaisesNoListenerThisHasNotLookedAt() throws {
        let files = try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true)
        #expect(!files.isEmpty, "PomodoroMac/PomodoroMac could not be read; it moved, or its name changed")
        let binding = files
            .filter { $0.value.contains("NWListener(") }
            .keys
            .sorted()
        #expect(
            binding == ["MdoroServer.swift", "ServerInfo.swift"],
            "POL-114: the listeners the Mac raises are now \(binding) — a new one has to fold its predecessor too, or the reader gets another Bonjour registration"
        )
    }

    // The listener the `/info` server holds is the one carrying the Bonjour registration
    // (`advertise` sets its `.service`), and `startServer()` does not replace that listener — it
    // replaces the whole `InfoHTTPServer`. **A dropped object cancels nothing**, so folding it is
    // the caller's to do; the new instance's own `start()` cannot reach the old instance.
    @Test func theInfoServerIsFoldedBeforeItIsReplaced() throws {
        let body = try text(of: appModel)
        let opening = try #require(
            body.range(of: "func startServer() async {"),
            "\(appModel) no longer has startServer()"
        )
        let rest = body[opening.upperBound...]
        let construction = try #require(
            rest.range(of: "InfoHTTPServer("),
            "\(appModel): startServer() no longer builds an InfoHTTPServer"
        )
        #expect(
            rest[rest.startIndex..<construction.lowerBound].contains("infoServer?.stop()"),
            "POL-114: \(appModel) replaces the /info server without cancelling the old one, so its Bonjour registration stays on the network for the life of the process"
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
            "POL-114: \(appModel) does `\(opening)` before asking whether it has already started"
        )
        let body = try text(of: appModel)
        #expect(
            body.contains("hasStarted = true"),
            "POL-114: nothing ever sets the flag, so the guard above never closes"
        )
    }

    // Refusing repetition is not the same as refusing a restart. What `stop()` took down may be
    // raised again, and if the flag stayed set the app could never come back up.
    @Test func stoppingLetsTheAppBeStartedAgain() throws {
        let body = try text(of: appModel)
        let opening = try #require(body.range(of: "func stop() {"), "\(appModel) no longer has stop()")
        #expect(
            body[opening.upperBound...].prefix(400).contains("hasStarted = false"),
            "POL-114: \(appModel) stops without clearing the flag, so nothing can start it again"
        )
    }
}
