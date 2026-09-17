import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// Decision 0040 (judgement 4): the Mac can end a pairing it made. What is watched here is the
// wiring — the record leaving, the Keychain being told, the displays and the server noticing —
// never a listener: **nothing in this file goes on the air**. The fold
// decisions are read from the diagnostic log (`server.stop`), the same trace
// `ServerPresenceWiringTests` reads, and the "server up" halves run against an identity that
// refuses to load, so the attempt is real and the LAN is never touched.

// The Keychain seam, answering what it is told to. `save` failing is the one seam failure the
// revocation screen has to say something about.
private final class ScriptedTokenStore: DeviceTokenStoring, @unchecked Sendable {
    private let records: DeviceTokenRecords
    private let saveAnswer: ErrorCode?
    init(_ records: DeviceTokenRecords, saveFails: ErrorCode? = nil) {
        self.records = records
        self.saveAnswer = saveFails
    }
    func load() -> DeviceTokenRecords { records }
    func save(_ tokens: [DeviceToken]) -> ErrorCode? { saveAnswer }
    func eraseLeftoverPlaintext() {}
}

private func scratchDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroRevocation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func model(
    in directory: URL,
    tokens: [DeviceToken],
    saveFails: ErrorCode? = nil
) -> AppModel {
    let model = AppModel(
        store: InMemoryStateStore(),
        diagnostics: DiagnosticLog(directory: directory),
        bookmarks: VaultBookmarks(),
        notifications: RecordedNotifications(),
        idleSleep: RecordedSleepGuard(),
        deviceTokens: ScriptedTokenStore(.onRecord(tokens), saveFails: saveFails),
        // Refuses to load, so no attempt to go on the air can raise a listener.
        identityFile: { throw NSError(domain: NSCocoaErrorDomain, code: 257) }
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

@MainActor
private func settles(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

@Suite("Revoking a pairing (Decision 0040)")
@MainActor
struct RevocationTests {

    // REQ-UIX-004: the deletion has a visible result — the record leaves the list and the
    // connection display leaves with the last record. The trace in the log carries a count and
    // no name (Decision 0018).
    @Test func revokingTheLastRecordTakesTheConnectionDisplayWithIt() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = DeviceToken(deviceName: "iPhone", issuedAt: Date())
        let model = model(in: directory, tokens: [record])
        #expect(model.showsConnectionState)

        model.revokeDeviceToken(record)

        #expect(model.issuedDeviceTokens.isEmpty, "the record is still on the list")
        #expect(!model.showsConnectionState,
                "REQ-UIX-004: the last pairing left and the connection display stayed")
        #expect(model.revocationProblem == nil, "a removal that saved reported a problem")
        #expect(logText(in: directory).contains("tokens.revoke"), "the revocation left no trace")
        #expect(!logText(in: directory).contains("iPhone"), "Decision 0018: a device name reached the log")
    }

    // REQ-COM-003 / Decision 0040: the fold after the last revocation goes through the same gate
    // as the closing screen — so while the pairing screen (where the Remove button lives) is
    // open, the server stays up, and closing the screen is what folds it.
    @Test func theFoldAfterTheLastRevocationWaitsForTheScreenToClose() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = DeviceToken(deviceName: "iPhone", issuedAt: Date())
        let model = model(in: directory, tokens: [record])

        // The screen is open; the attempt to go on the air was made and refused (unreadable
        // identity), which is what keeps this test off the LAN.
        model.pairingScreenOpened()
        let tried = await settles { model.serverStartError != nil }
        #expect(tried, "the pairing screen did not make the Mac try")

        model.revokeDeviceToken(record)
        #expect(!logText(in: directory).contains("server.stop"),
                "REQ-COM-003: the fold did not wait for the pairing screen to close")

        model.pairingScreenClosed()
        #expect(logText(in: directory).contains("server.stop"),
                "REQ-COM-003: the last pairing is gone and the closed screen folded nothing")
    }

    // REQ-COM-003: away from the pairing screen, the last revocation folds at once — nothing is
    // left that needs a server.
    @Test func awayFromTheScreenTheLastRevocationFoldsAtOnce() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = DeviceToken(deviceName: "iPhone", issuedAt: Date())
        let model = model(in: directory, tokens: [record])

        model.revokeDeviceToken(record)

        #expect(logText(in: directory).contains("server.stop"),
                "REQ-COM-003: the last pairing was deleted and nothing folded")
    }

    // Decision 0040 (judgement 4) / REQ-ERR-010: a removal whose save failed may not stick, and
    // that is said on the screen, not only in the log.
    @Test func aRemovalThatCouldNotBeSavedSaysSo() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = DeviceToken(deviceName: "iPhone", issuedAt: Date())
        let model = model(
            in: directory, tokens: [record],
            saveFails: ErrorCode(domain: NSOSStatusErrorDomain, code: -25299)
        )

        model.revokeDeviceToken(record)

        #expect(model.issuedDeviceTokens.isEmpty, "the in-memory removal still happened")
        #expect(model.revocationProblem != nil,
                "REQ-ERR-010: the save failed and the screen was told nothing")
        #expect(logText(in: directory).contains("tokens.save"), "the failure left no code in the log")
    }
}

@Suite("The approval banner falls with its question (REQ-SEC-004)")
@MainActor
struct ApprovalBannerTests {

    // REQ-SEC-004: the confirmation the clause asks the Mac to show is this banner, and the clause
    // gives it a 60-second timeout that resolves as a denial through the same callback the user's
    // click uses. A confirmation that has timed out is no longer one — that step is a reading, not
    // the letter. Leave it standing and it says "Denied automatically after 60 seconds" over an
    // Allow button that answers nothing.
    @Test func aTimedOutApprovalTakesItsBannerDown() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let standing = DeviceToken(deviceName: "iPhone A", issuedAt: Date())
        let asking = DeviceToken(deviceName: "iPhone B", issuedAt: Date())
        let model = model(in: directory, tokens: [standing, asking])
        let callbacks = model.serverCallbacks()

        callbacks.connectionChanged(ConnectionState(isConnected: true, peerDeviceName: "iPhone A"))
        let decision = callbacks.authenticate(HelloPayload(deviceToken: asking.value, deviceName: "iPhone B"))
        #expect(decision == .needsUserApproval(requestingDeviceName: "iPhone B"))
        #expect(model.pendingConnectionRequest == "iPhone B", "the question raised no banner")

        // What the 60-second timeout calls (`MdoroServer.resolvePendingApproval(approved: false)`).
        _ = callbacks.resolveApproval(false)

        #expect(model.pendingConnectionRequest == nil,
                "the request was denied and the banner kept standing")
    }
}
