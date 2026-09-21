import Testing
import Foundation
import MdoroCore
@testable import MdoroiOS

// REQ-PER-011 / REQ-PER-010: **the state read back off the disk is called unsynced from the moment
// it goes on the screen, whatever route the launch took.**
//
// The half that was missing: `isAwaitingFirstSync` was raised in `MdoroiOSApp`'s notification handler
// and nowhere else, so a user who opened the app without going through a notification was shown a
// restored state with nothing saying it was not settled — how old it was could be read off the
// received-at time beside it and nowhere else. REQ-NTF-011 (SHOULD) covers the notification route;
// REQ-PER-011 (MUST) covers this one.
//
// **This reads the flag off a real `ClientModel`**, which is why it lives here rather than in
// MdoroCore: `swift test` cannot link the app. `ARestoredStateSaysItIsNotSyncedTests` over there
// reads the same rule off the source, because this suite needs a simulator and CI runs neither it
// nor any other build of the iPhone side.

// REQ-SEC-001: this suite runs inside `MdoroiOS.app` under its own bundle identifier, so the
// Keychain seam is taken and nothing here reads or writes the reader's own.
private struct NoTokenHere: TokenStoring {
    func load(serverId: ServerID) -> String? { nil }
    func save(_ token: String, serverId: ServerID) {}
    func delete(serverId: ServerID) {}
}

// REQ-PER-010: a store of this suite's own. **`UserDefaults.standard` here is the user's own phone**
// — writing a snapshot into it would put a state of this test's invention in front of them at the
// next launch, and clearing it would throw away the one they last received.
private func emptyStore(_ name: String) throws -> UserDefaults {
    let store = try #require(UserDefaults(suiteName: name))
    store.removePersistentDomain(forName: name)
    return store
}

// The keys `ClientModel` files its snapshot under. **Private over there**, so they are spelled again
// here — and a spelling that stops matching does not quietly pass: the restore then finds nothing,
// and every `#require(model.snapshot)` below fails.
private let snapshotKey = "lastStateSnapshot"
private let snapshotAtKey = "lastStateSnapshotAt"

private func storeWithASnapshot(_ name: String, receivedAt: Date) throws -> UserDefaults {
    let store = try emptyStore(name)
    let snapshot = StateSnapshot(
        timer: .idle(now: receivedAt),
        task: TaskContext(),
        settings: .default,
        presets: .initial(),
        connection: ConnectionState(isConnected: true, peerDeviceName: "Mac")
    )
    let encoded = try MessageCoder.encoder.encode(snapshot)
    store.set(encoded, forKey: snapshotKey)
    store.set(receivedAt, forKey: snapshotAtKey)
    return store
}

// Nothing in these tests connects, so no `stateSnapshot` ever arrives and no Live Activity, Bonjour
// browse or notification is asked for: `restoreLastSnapshot()` is reached on its own, which is what
// `start()` does with it before any of that.
@Suite("A restored state is not synced yet (REQ-PER-011)")
@MainActor
struct ARestoredStateIsNotSyncedYetTests {

    // **The failure itself.** No notification was tapped; the app was simply opened.
    @Test func openingTheAppOnAStoredSnapshotSaysItIsNotSyncedYet() async throws {
        let store = try storeWithASnapshot("ARestoredStateIsNotSyncedYetTests.stored",
                                           receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let model = ClientModel(tokens: NoTokenHere(), defaults: store)

        model.restoreLastSnapshot()

        _ = try #require(model.snapshot, "REQ-PER-010: the stored snapshot was not restored at all")
        _ = try #require(model.snapshotReceivedAt, "REQ-PER-011: the time it was received was not restored")
        let awaiting = model.isAwaitingFirstSync
        #expect(awaiting,
                "REQ-PER-011: a restored state is on the screen and nothing says it is not synced yet")
    }

    // **And it is the flag the screen reads**, not a second one: `ConnectionBanner` shows the words
    // for `isAwaitingFirstSync`, and this is the same property.
    @Test func theRestoredStateIsNotReportedAsConnectedEither() async throws {
        let store = try storeWithASnapshot("ARestoredStateIsNotSyncedYetTests.notConnected",
                                           receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let model = ClientModel(tokens: NoTokenHere(), defaults: store)

        model.restoreLastSnapshot()

        let connected = model.isConnected
        #expect(!connected, "a model that has dialled nothing reports itself connected")
        let status = model.connectionStatus
        #expect(status == .disconnected, "\(status)")
    }

    // **Only a state that is on the screen is called old.** A phone that has never been connected has
    // nothing restored to call unsynced, and REQ-UIX-046 keeps the banner for what needs attention.
    @Test func aLaunchWithNothingStoredSaysNothingAboutSyncing() async throws {
        let store = try emptyStore("ARestoredStateIsNotSyncedYetTests.empty")
        let model = ClientModel(tokens: NoTokenHere(), defaults: store)

        model.restoreLastSnapshot()

        let restored = model.snapshot
        #expect(restored == nil, "something was restored from a store with nothing in it")
        let awaiting = model.isAwaitingFirstSync
        #expect(!awaiting, "REQ-UIX-046: a sync of nothing is being waited for")
    }

    // REQ-NTF-011: **the notification route still reaches the same flag.** It is the one that covers
    // a tap on a phone with nothing stored to restore, so it is read here with nothing stored.
    @Test func aNotificationTapStillSaysItIsNotSyncedYet() async throws {
        let store = try emptyStore("ARestoredStateIsNotSyncedYetTests.notification")
        let model = ClientModel(tokens: NoTokenHere(), defaults: store)

        model.markAwaitingSync()

        let awaiting = model.isAwaitingFirstSync
        #expect(awaiting, "REQ-NTF-011: a launch from a notification no longer says it is not synced")
    }

    // REQ-PER-010: **the store it was handed is the one it read.** The seam is what keeps the tests
    // above off the reader's own defaults, and a seam that is accepted and then ignored looks exactly
    // like one that works — the restore would find the user's real snapshot and the flag would go up
    // all the same. The received-at time is the evidence: it is the one this suite stored, which no
    // phone's own store holds.
    @Test func theStoreItWasGivenIsTheOneItReads() async throws {
        let receivedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let store = try storeWithASnapshot("ARestoredStateIsNotSyncedYetTests.ownStore", receivedAt: receivedAt)
        let model = ClientModel(tokens: NoTokenHere(), defaults: store)

        model.restoreLastSnapshot()

        let at = try #require(model.snapshotReceivedAt)
        let sameSecond = abs(at.timeIntervalSince(receivedAt)) < 1
        #expect(sameSecond, "the time restored is \(at), not the \(receivedAt) this suite stored")
    }
}
