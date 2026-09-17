import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-SEC-002 / Decision 0040: what `AppModel` does with the answer the Keychain gave.
//
// The Keychain carries a failure the plist never had: a read can be refused while the records are
// sitting there intact. Fold every such refusal into `[]` and the save that follows the next
// pairing writes one record over all of them — every paired iPhone refused with
// `unknownDeviceToken` on the next launch, throwing away its own token in reply, with nothing on
// the screen or in the log to say why.
//
// **The Keychain itself is not exercised here.** This suite runs inside MdoroMac.app under its
// bundle identifier, so an item it wrote would land in the reader's own login keychain and stay
// there. The store is the seam; what is checked is the policy built on top of it.
// `DeviceTokenStorageTests` in MdoroCore holds the shape of the calls themselves.

// A store that answers what the case tells it to, and keeps what it was asked to keep.
private final class RecordedTokenStore: DeviceTokenStoring, @unchecked Sendable {
    private let answer: DeviceTokenRecords
    private let refusal: ErrorCode?
    private(set) var saved: [[DeviceToken]] = []
    private(set) var erasures = 0

    init(_ answer: DeviceTokenRecords, refusing refusal: ErrorCode? = nil) {
        self.answer = answer
        self.refusal = refusal
    }

    func load() -> DeviceTokenRecords { answer }

    func save(_ tokens: [DeviceToken]) -> ErrorCode? {
        saved.append(tokens)
        return refusal
    }

    func eraseLeftoverPlaintext() { erasures += 1 }
}

private func token(_ value: String) -> DeviceToken {
    DeviceToken(value: value, deviceName: "iPhone", issuedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

// The two statuses used below, as the OS hands them over: one refusal that leaves the records
// where they are, and one failure to write.
private let keychainRefused = ErrorCode(domain: NSOSStatusErrorDomain, code: -25308)
private let keychainWriteFailed = ErrorCode(domain: NSOSStatusErrorDomain, code: -34018)

// Build a model that touches nothing of the reader's, run the body, and hand back the lines the
// diagnostic log ended up with.
@MainActor
private func recording(_ store: RecordedTokenStore, _ body: (AppModel) -> Void) throws -> [String] {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroKeychainPolicy-\(UUID().uuidString)", isDirectory: true)
    let model = AppModel(
        store: InMemoryStateStore(),
        diagnostics: DiagnosticLog(directory: directory),
        bookmarks: VaultBookmarks(),
        notifications: RecordedNotifications(),
        idleSleep: RecordedSleepGuard(),
        deviceTokens: store
    )
    model.diagnostics.open(preset: Preset.standard(), settings: .default)
    body(model)
    // The file is made by the first line written to it, and the ordinary cases below write none.
    // No file is no lines, which is the answer those cases are asking for.
    let text = (try? String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )) ?? ""
    try? FileManager.default.removeItem(at: directory)
    return text.split(separator: "\n").map(String.init)
}

private func line(_ lines: [String], code: String) -> String? {
    lines.first { $0.contains(" \(code) ") || $0.hasSuffix(" \(code)") }
}

@Suite("Records that could not be read are not written over (REQ-SEC-002 / Decision 0040)")
@MainActor
struct KeychainRecordPolicyTests {

    // The ordinary case, so the two below can be told apart from a save that never happens.
    @Test func recordsThatWereReadGoBackAsTheyAre() throws {
        let store = RecordedTokenStore(.onRecord([token("a"), token("b")]))
        _ = try recording(store) { model in
            model.adoptStoredDeviceTokens()
            model.saveIssuedDeviceTokens()
        }
        #expect(store.saved.count == 1)
        #expect(store.saved.first?.map(\.value) == ["a", "b"])
    }

    // **The one that destroys them when this is got wrong.** A refusal is not an empty Keychain.
    @Test func aKeychainThatWouldNotAnswerIsNeverWrittenOver() throws {
        let store = RecordedTokenStore(.unreadable(keychainRefused))
        let lines = try recording(store) { model in
            model.adoptStoredDeviceTokens()
            model.saveIssuedDeviceTokens()
        }
        #expect(
            store.saved.isEmpty,
            "Decision 0040: the records the Keychain would not hand over were written over anyway"
        )
        // REQ-ERR-010 / Decision 0034: both the read and the refusal to write leave a code behind.
        let read = try #require(line(lines, code: "tokens.load"), "losing every pairing left no trace")
        #expect(read.contains("ERROR"))
        #expect(read.contains("why=unreadable(NSOSStatusErrorDomain:-25308)"))
        let write = try #require(line(lines, code: "tokens.save"), "the save that did not happen left no trace")
        #expect(write.contains("ERROR"))
        #expect(write.contains("why=notWritten(NSOSStatusErrorDomain:-25308)"))
    }

    // An item that was handed over and held nothing this version can read is a different answer.
    // **Nothing usable is in it**, so refusing to write would leave the Mac unable to pair for
    // good — with no screen anywhere saying why.
    @Test func anItemNothingCanBeReadOutOfIsReplaced() throws {
        let store = RecordedTokenStore(.unintelligible(ErrorCode(domain: NSCocoaErrorDomain, code: 4864)))
        let lines = try recording(store) { model in
            model.adoptStoredDeviceTokens()
            model.saveIssuedDeviceTokens()
        }
        #expect(store.saved.count == 1, "an item holding nothing readable can never be replaced")
        let read = try #require(line(lines, code: "tokens.load"))
        #expect(read.contains("why=unintelligible(NSCocoaErrorDomain:4864)"))
    }

    // REQ-ERR-010: throw `SecItemAdd`'s `OSStatus` away and a write that fails after the delete
    // preceding it leaves no records and no line.
    @Test func aWriteThatFailedSaysSo() throws {
        let store = RecordedTokenStore(.onRecord([token("a")]), refusing: keychainWriteFailed)
        let lines = try recording(store) { model in
            model.adoptStoredDeviceTokens()
            model.saveIssuedDeviceTokens()
        }
        let write = try #require(line(lines, code: "tokens.save"), "a failed write left no trace")
        #expect(write.contains("ERROR"))
        #expect(write.contains("why=saveFailed(NSOSStatusErrorDomain:-34018)"))
    }

    // Nothing is written when the read succeeded and there was nothing to read: that is a Mac
    // that has never been paired, and it is not a failure.
    @Test func anEmptyKeychainIsQuiet() throws {
        let store = RecordedTokenStore(.onRecord([]))
        let lines = try recording(store) { model in
            model.adoptStoredDeviceTokens()
        }
        #expect(line(lines, code: "tokens.load") == nil, "an unpaired Mac reports a failure at every launch")
    }

    // The plist is emptied through the store, so a test run empties a store that is not the
    // reader's. `UserDefaults.standard` here is their own settings.
    @Test func theLeftoverPlistIsEmptiedThroughTheStore() throws {
        let store = RecordedTokenStore(.onRecord([]))
        _ = try recording(store) { model in
            model.adoptStoredDeviceTokens()
        }
        #expect(store.erasures == 1, "the leftover plist is erased somewhere outside the seam")
    }
}
