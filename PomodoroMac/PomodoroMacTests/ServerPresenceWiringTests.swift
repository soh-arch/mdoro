import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-COM-003 (v2.25) / Decision 0040: the server exists only while a pairing does — or while the
// pairing screen is open, raising one. The rule itself is held still in `ServerPresenceTests`
// (MdoroCore, which is what CI runs); **this is the wiring**: that the launch asks, that the
// pairing screen opening is what makes an unpaired Mac try, and that the screen closing folds
// what nothing needs any more.
//
// **Nothing here raises a listener or puts a name on the LAN.** The "it starts" halves
// run against records that keep the Mac off the air on purpose — an identity that cannot be read
// is refused before any listener is built — so what is observed is the *attempt* (the refusal it
// ends in), never the server. The "it does not start" halves observe that not even the identity
// file was touched.
//
// **`server.stop` carries whether anything was listening when the fold ran**, and in this file the
// answer is always no — nothing here raises a listener. That half of the line is asserted where
// the fold happens, because it is the only place in the suite where a listener's absence is
// written down rather than merely true.

private final class FixedTokenStore: DeviceTokenStoring, @unchecked Sendable {
    private let answer: DeviceTokenRecords
    init(_ answer: DeviceTokenRecords) { self.answer = answer }
    func load() -> DeviceTokenRecords { answer }
    func save(_ tokens: [DeviceToken]) -> ErrorCode? { nil }
    func eraseLeftoverPlaintext() {}
}

private func scratchDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroPresence-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func model(
    in directory: URL,
    tokens: DeviceTokenRecords,
    identityFile: (() throws -> ServerIdentityFile)? = nil
) -> AppModel {
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
    model.adoptStoredDeviceTokens()
    return model
}

private func logText(in directory: URL) -> String {
    (try? String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )) ?? ""
}

// The screen-driven starts run through a Task of their own, so their observable end is waited
// for rather than read straight after.
@MainActor
private func settles(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

@Suite("The server exists only while a pairing does (REQ-COM-003 v2.25)")
@MainActor
struct ServerPresenceWiringTests {

    // Decision 0040: the user this is all for. A launch with nothing paired raises nothing — and
    // pays nothing: not even the identity file is created, because the id exists to be advertised
    // and nothing is being advertised.
    @Test func aLaunchWithNothingPairedRaisesNothingAndTouchesNothing() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = model(in: directory, tokens: .onRecord([]))

        await model.startServerIfNeeded()

        #expect(model.advertisedWebsocketPort == 0, "REQ-COM-003: a Mac with nothing paired went on the air")
        #expect(model.serverStartError == nil, "not starting is the normal state, not a failure")
        #expect(
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent("identity.json").path),
            "an identity was made for a Mac that has nothing to advertise it to"
        )
    }

    // REQ-COM-003 / REQ-PLT-007: the pairing screen opening is what makes an unpaired Mac try.
    // The identity file here refuses to load, so the attempt is refused before any listener is
    // built — the refusal reaching the screen is the proof the attempt was made, and the same
    // launch without the screen (above, with a readable file; here the guard is one step further
    // in) makes no attempt at all.
    @Test func openingThePairingScreenIsWhatMakesAnUnpairedMacTry() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = model(
            in: directory,
            tokens: .onRecord([]),
            identityFile: { throw NSError(domain: NSCocoaErrorDomain, code: 257) }
        )

        // The launch: nothing paired, so not even the unreadable identity is reached for.
        await model.startServerIfNeeded()
        #expect(model.serverStartError == nil, "REQ-COM-003: an unpaired Mac tried to go on the air at launch")

        // The screen: now it tries, and the refusal is what says so.
        model.pairingScreenOpened()
        let tried = await settles { model.serverStartError != nil }
        #expect(tried, "REQ-COM-003: opening the pairing screen did not make the Mac try to go on the air")
        #expect(model.advertisedWebsocketPort == 0, "the refused attempt still went on the air")
    }

    // REQ-COM-003: closing the screen takes down what nothing needs, and ends the pairing window
    // whose code has no screen to be read from (REQ-SEC-001). The fold is visible in the log and
    // in the failure line being over — and the line says the fold found nothing listening, which
    // is the truth about this fixture: the identity refuses to load, so no listener was ever
    // built. The failure line has to be standing first, or its absence afterwards would be the
    // absence of something that was never there.
    @Test func closingTheScreenUnpairedFoldsTheServerAndThePairingWindow() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = model(
            in: directory,
            tokens: .onRecord([]),
            identityFile: { throw NSError(domain: NSCocoaErrorDomain, code: 257) }
        )

        model.pairingScreenOpened()
        let tried = await settles { model.serverStartError != nil }
        #expect(tried, "nothing was standing to be folded, so the fold below is unobservable")
        model.beginPairing()
        #expect(model.pairingCode != nil)

        model.pairingScreenClosed()
        #expect(model.pairingCode == nil, "REQ-SEC-001: the code outlived the screen it is read from")
        #expect(model.serverStartError == nil, "a deliberate fold left a failure line standing")
        #expect(model.advertisedWebsocketPort == 0)
        #expect(logText(in: directory).contains("server.stop"), "the fold left no trace in the log")
        #expect(
            logText(in: directory).contains("server.stop listening=no"),
            "a fold that found nothing listening was written down as though a listener had stopped"
        )
    }

    // REQ-COM-003: with a pairing on record the closed screen changes nothing — the fold asks
    // first. (`server.stop` in the log is the fold's trace, so its absence is the assertion.
    // The screen is never opened here, because opening it would start a real server for this
    // pairable Mac; `pairingScreenClosed` asks `serverShouldRun`, which is what is being tested.)
    @Test func closingTheScreenPairedFoldsNothing() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = DeviceToken(deviceName: "iPhone", issuedAt: Date())
        let model = model(in: directory, tokens: .onRecord([record]))

        model.pairingScreenClosed()

        #expect(!logText(in: directory).contains("server.stop"), "REQ-COM-003: a paired Mac left the air because a screen closed")
    }
}
