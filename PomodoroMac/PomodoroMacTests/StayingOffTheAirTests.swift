import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-COM-003 (v2.26): **a Mac that cannot read who it is does not go on the air.**
//
// Decision 0040 settled that the `id` is made once and never again, and said nothing about the
// launch that could not read it. What the code did was make a new one — which is the very symptom
// 0040 exists to remove, arriving through a different door: the Mac is a stranger, every paired
// iPhone is asked for a six-digit code, and the token issued in reply is filed under an id that is
// gone at the next launch. Orphans on both ends.
//
// The record of issued tokens is the same story from the other side. A launch that could not read
// it holds nothing, so every returning iPhone is refused with `unknownDeviceToken` — and the
// iPhone throws its own token away on being refused (`MdoroClient`). The Mac's records survive
// that; the iPhone's do not.
//
// **Nothing here raises a listener or puts a name on the LAN.** That is the whole point of what is
// being checked: the decision is taken before either happens, so a test of the decision reaches
// neither. `ListenerFoldingTests` is the suite that binds ports, and it never advertises.

// A store that answers what the case tells it to.
private final class FixedTokenStore: DeviceTokenStoring, @unchecked Sendable {
    private let answer: DeviceTokenRecords
    private(set) var saved: [[DeviceToken]] = []

    init(_ answer: DeviceTokenRecords) { self.answer = answer }

    func load() -> DeviceTokenRecords { answer }
    func save(_ tokens: [DeviceToken]) -> ErrorCode? {
        saved.append(tokens)
        return nil
    }
    func eraseLeftoverPlaintext() {}
}

private let keychainRefused = ErrorCode(domain: NSOSStatusErrorDomain, code: -25308)

// A scratch folder of the reader's own, and the identity file inside it. POL-047: the suite is
// hosted by MdoroMac.app under its bundle identifier, so `ServerIdentityFile.inApplicationSupport()`
// would resolve to the container the reader's own Mdoro uses.
private func scratchDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroOffTheAir-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func discard(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
}

// Build a model that touches nothing of the reader's, run the body, and hand back the lines the
// diagnostic log ended up with.
@MainActor
private func recording(
    tokens: DeviceTokenRecords,
    identityFile: (() throws -> ServerIdentityFile)? = nil,
    _ body: (AppModel) async throws -> Void
) async throws -> [String] {
    let directory = try scratchDirectory()
    defer { discard(directory) }
    let model = AppModel(
        store: InMemoryStateStore(),
        diagnostics: DiagnosticLog(directory: directory),
        bookmarks: VaultBookmarks(),
        notifications: RecordedNotifications(),
        idleSleep: RecordedSleepGuard(),
        deviceTokens: FixedTokenStore(tokens),
        identityFile: identityFile ?? {
            ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        }
    )
    model.diagnostics.open(preset: Preset.standard(), settings: .default)
    try await body(model)
    let text = (try? String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )) ?? ""
    return text.split(separator: "\n").map(String.init)
}

private func line(_ lines: [String], code: String) -> String? {
    lines.first { $0.contains(" \(code) ") || $0.hasSuffix(" \(code)") }
}

@Suite("A Mac that cannot read who it is stays off the air (REQ-COM-003 v2.26)")
@MainActor
struct StayingOffTheAirTests {

    // The ordinary case, so the three below can be told apart from a Mac that never had an
    // identity to advertise in the first place.
    @Test func aMacThatCanReadBothRecordsGoesOnTheAir() async throws {
        var advertised: ServerID?
        _ = try await recording(tokens: .onRecord([])) { model in
            model.adoptStoredDeviceTokens()
            advertised = model.identityToAdvertise()
            #expect(model.serverStartError == nil)
            // Read once and kept for the life of the process (Decision 0040).
            #expect(model.identityToAdvertise() == advertised)
        }
        #expect(advertised != nil, "a Mac with an id and a readable record has nothing to stay off the air for")
    }

    // **The one this requirement is about.** The file was not handed over, so there may be an id
    // sitting in it, intact and unread. Making one and advertising it unpairs every iPhone.
    @Test func anIdentityThatCouldNotBeReadKeepsTheMacOffTheAir() async throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        let kept = try #require(file.loadOrCreate().id, "the identity has to exist to be unreadable")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.fileURL.path)
        try #require(
            (try? Data(contentsOf: file.fileURL)) == nil,
            "the file system must actually refuse, or this proves nothing"
        )

        var advertised: ServerID?
        var message: String?
        var hint: String?
        let lines = try await recording(tokens: .onRecord([]), identityFile: { file }) { model in
            model.adoptStoredDeviceTokens()
            advertised = model.identityToAdvertise()
            message = model.serverStartError
            hint = model.serverStartHint
        }

        #expect(advertised == nil, "REQ-COM-003: an id was invented and the Mac went on the air as a stranger")
        #expect(advertised != kept)
        // REQ-COM-003: the reason is on the screen, not only in the log.
        #expect(message != nil, "nothing on the screen said why the iPhone cannot find this Mac")
        // The two questions the reader will have. Neither answer is bad news, and both have to be
        // in the words — a sentence that only says it failed leaves them re-pairing for nothing.
        let said = ((message ?? "") + " " + (hint ?? "")).lowercased()
        #expect(said.contains("nothing was deleted"), "the reader is left thinking the pairing is gone")
        #expect(said.contains("again"), "the reader is left with nothing to try")
        // REQ-ERR-010 / Decision 0034: the log gets a code, in the one shape.
        let read = try #require(line(lines, code: "identity.load"), "a refused read left no trace")
        #expect(read.contains("ERROR"))
        #expect(read.contains("why=unreadable("))
        let refused = try #require(line(lines, code: "server.offTheAir"), "staying off the air left no trace")
        #expect(refused.contains("ERROR"))
        #expect(refused.contains("why=unreadable("))

        // And it is not permanent: the next launch reads the file and advertises the id that was
        // there all along.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.fileURL.path)
        _ = try await recording(tokens: .onRecord([]), identityFile: { file }) { model in
            model.adoptStoredDeviceTokens()
            #expect(model.identityToAdvertise() == kept, "the id that survived was not the one advertised")
            #expect(model.serverStartError == nil)
        }
    }

    // The same discipline from the other side. **The Mac's records survive a launch like this;
    // the iPhone's do not** — it is refused with `unknownDeviceToken` and throws its token away.
    @Test func aRecordOfIssuedTokensThatCouldNotBeReadKeepsTheMacOffTheAir() async throws {
        var advertised: ServerID?
        var message: String?
        let lines = try await recording(tokens: .unreadable(keychainRefused)) { model in
            model.adoptStoredDeviceTokens()
            advertised = model.identityToAdvertise()
            message = model.serverStartError
        }

        #expect(
            advertised == nil,
            "REQ-COM-003: the Mac went on the air holding no tokens, and every paired iPhone threw its own away"
        )
        #expect(message != nil, "nothing on the screen said why the iPhone cannot find this Mac")
        let refused = try #require(line(lines, code: "server.offTheAir"), "staying off the air left no trace")
        #expect(refused.contains("why=tokensUnreadable(NSOSStatusErrorDomain:-25308)"))
    }

    // REQ-COM-003: **the server as well as the advertisement.** The question is asked at the top of
    // `startServer()` and not inside `advertise`, because a Mac listening on a port that no
    // Bonjour record points at is no better off — it is still a Mac that does not know what it has.
    //
    // **This is the only test in the suite that calls `startServer()`, and it calls it in the one
    // state where `startServer()` raises nothing.** Everything that would otherwise bind a port or
    // put a name on the reader's LAN is on the far side of the line being checked (POL-047).
    @Test func startingTheServerAsksBeforeItRaisesAnything() async throws {
        // **Both answers are withheld, not one.** Either guard on its own is enough to keep this
        // launch off the air, and a mutation that drops one of them has to leave a suite that
        // still raises nothing on the reader's LAN while it is being measured.
        _ = try await recording(
            tokens: .unreadable(keychainRefused),
            identityFile: { throw NSError(domain: NSCocoaErrorDomain, code: 257) }
        ) { model in
            model.adoptStoredDeviceTokens()
            await model.startServer()
            #expect(
                model.serverStartError != nil,
                "REQ-COM-003: the listener went up for a Mac that could not read what it has issued"
            )
            #expect(model.websocketPortForInfo == 0, "REQ-COM-003: a port was bound anyway")
        }
    }

    // Decision 0036's line, applied to identity: **being unreadable and being broken are not the
    // same thing.** An item that was handed over and held nothing this version knows loses nothing
    // by being replaced, and refusing to advertise for it would leave the Mac unable to pair for
    // good, with a sentence on the screen the reader could do nothing about.
    @Test func aFileHoldingNothingWeKnowIsReplacedAndTheMacGoesOnTheAir() async throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        try Data("{\"id\":\"Mdoro (2)\"}".utf8).write(to: file.fileURL)

        var advertised: ServerID?
        let lines = try await recording(tokens: .onRecord([]), identityFile: { file }) { model in
            model.adoptStoredDeviceTokens()
            advertised = model.identityToAdvertise()
            #expect(model.serverStartError == nil)
        }
        #expect(advertised != nil, "a file with nothing readable in it left the Mac unable to pair at all")
        // REQ-ERR-010: replaced is still a failure, and it is still written down.
        let read = try #require(line(lines, code: "identity.load"))
        #expect(read.contains("why=notKept(Mdoro:12)"))
        #expect(line(lines, code: "server.offTheAir") == nil, "a broken file was treated as an unreadable one")
    }

    // Application Support could not be reached at all, so what is in the file is unknown — and
    // **unknown is not empty.** Inventing an id here is the same failure one step further back.
    @Test func aFolderThatCouldNotBeReachedIsNotAMacWithNoIdentity() async throws {
        var advertised: ServerID?
        let lines = try await recording(
            tokens: .onRecord([]),
            identityFile: { throw NSError(domain: NSCocoaErrorDomain, code: 513) }
        ) { model in
            model.adoptStoredDeviceTokens()
            advertised = model.identityToAdvertise()
            #expect(model.serverStartError != nil)
        }
        #expect(advertised == nil, "REQ-COM-003: an id was invented for a folder nobody could look in")
        let refused = try #require(line(lines, code: "server.offTheAir"))
        #expect(refused.contains("why=unreadable(NSCocoaErrorDomain:513)"))
    }
}
