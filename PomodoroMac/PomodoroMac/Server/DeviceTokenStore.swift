import Foundation
import Security
import MdoroCore

// REQ-SEC-002 / Decision 0040: everything `AppModel` asks of the place tokens are kept, so a test
// can stand where the Keychain does.
//
// **The same seam as `SessionNotifying` and `IdleSleepGuarding`, deliberately.** One pattern to
// learn: a protocol, a real implementation that is the default, and an inert one chosen where the
// model is built. The app carries no branch saying "unless this is a test". The boundary matters
// for the same reason theirs do — the suite runs inside MdoroMac.app, under its bundle identifier,
// so an item it writes goes into the reader's own login keychain and stays there after the run.
//
// **Both answers carry their failures.** REQ-ERR-010: an `OSStatus` that goes unread is a record
// that vanished with nothing said, and that is exactly what happened here.
protocol DeviceTokenStoring: Sendable {
    func load() -> DeviceTokenRecords
    // nil when the records are on file. Non-nil is the reason they are not.
    func save(_ tokens: [DeviceToken]) -> ErrorCode?
    // Decision 0040: the plaintext array the tokens used to sit in. **Part of this seam and not a
    // free function**, because `UserDefaults.standard` under this bundle identifier is the
    // reader's own settings — the same reason the rest of the protocol exists (POL-047 / 053).
    func eraseLeftoverPlaintext()
}

// REQ-SEC-002 / REQ-ERR-010: what came back, and whether it is the whole answer.
//
// **"Nothing on record" and "could not be read" used to be the same answer.** `load()` folded
// every `OSStatus` other than `errSecSuccess` into `[]`, so one refusal from the Keychain left the
// authenticator holding nothing — and the next pairing wrote that one record over all of them.
enum DeviceTokenRecords: Equatable {
    // What is on file. Empty is a complete answer: nothing has been paired yet.
    case onRecord([DeviceToken])
    // The item was handed over and held nothing this version can read. **Nothing usable is in it**,
    // so nothing usable is lost by replacing it.
    case unintelligible(ErrorCode)
    // **The Keychain did not hand it over.** The records may be sitting there intact and unread,
    // so writing a fresh set over them is how a pairing disappears.
    case unreadable(ErrorCode)

    var tokens: [DeviceToken] {
        if case let .onRecord(tokens) = self { tokens } else { [] }
    }

    // REQ-ERR-010 / Decision 0034: `case(domain:code)`, the one shape every failure is written in.
    var diagnosticSummary: String? {
        switch self {
        case .onRecord: nil
        case let .unintelligible(code): code.summary("unintelligible")
        case let .unreadable(code): code.summary("unreadable")
        }
    }

    // Why what is on file must not be written over, or nil when it may be.
    var unreadableBecause: ErrorCode? {
        if case let .unreadable(code) = self { code } else { nil }
    }
}

// REQ-SEC-002 / Decision 0040: **the records, in the Keychain.**
//
// What stood here was `UserDefaults.stringArray(forKey: "issuedDeviceTokens")`: the values in
// plain text in a plist, and the device name and the issue date dropped on the way in. Both halves
// were wrong — a secret written where anything can read it, and a record with nothing in it to
// identify what to revoke.
//
// One item holds all of them as JSON rather than one item per token. The token values are the
// secret, and the Keychain protects an item's *data*; `kSecAttrAccount` and the rest of the
// attributes are metadata and are not encrypted, so a value must never be one.
struct KeychainDeviceTokenStore: DeviceTokenStoring {
    private let service = "com.sohta.Mdoro.issuedDeviceTokens"
    private let account = "issued"

    func load() -> DeviceTokenRecords {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // Nothing has been paired yet. That is an answer, not a failure.
        if status == errSecItemNotFound { return .onRecord([]) }
        guard status == errSecSuccess else { return .unreadable(Self.problem(status)) }
        guard let data = item as? Data else { return .unreadable(.deviceTokensUnreadable) }
        do {
            return .onRecord(try MessageCoder.decoder.decode([DeviceToken].self, from: data))
        } catch {
            return .unintelligible(ErrorCode(error))
        }
    }

    // REQ-SEC-002 / REQ-ERR-010: **nothing is removed on the way to writing.**
    //
    // This was `SecItemDelete` and then `SecItemAdd` with its `OSStatus` thrown away. An add that
    // failed left the reader with no records at all and no trace of why: every paired iPhone was
    // refused with `unknownDeviceToken` on the next launch, and threw away its own token in reply.
    // An item that is already there is updated in place, so a failure now leaves what was on file
    // exactly where it was.
    func save(_ tokens: [DeviceToken]) -> ErrorCode? {
        let data: Data
        do {
            data = try MessageCoder.encoder.encode(tokens)
        } catch {
            return ErrorCode(error)
        }
        let query = baseQuery()
        // The Mac has to authenticate a returning iPhone whenever it is running, and it can be
        // running before anyone unlocks the screen. Not `ThisDeviceOnly` for the same reason the
        // iPhone's is: this one is not on iCloud Keychain to begin with (no `kSecAttrSynchronizable`),
        // and a Mac restored from a backup that has forgotten its pairings is the state Decision
        // 0040 already accepts. Set on the update as well, so an item an older build left behind
        // ends up with the same protection as one written today.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return nil }
        guard updated == errSecItemNotFound else { return Self.problem(updated) }

        var insert = query
        insert.merge(attributes) { _, new in new }
        let added = SecItemAdd(insert as CFDictionary, nil)
        return added == errSecSuccess ? nil : Self.problem(added)
    }

    func eraseLeftoverPlaintext() {
        LeftoverPlaintextTokens.erase()
    }

    // REQ-ERR-010 / Decision 0034: an `OSStatus` is already a domain and a code.
    // `SecCopyErrorMessageString` would give a sentence in the reader's language, and a sentence
    // is the one thing that must not reach the diagnostic log.
    private static func problem(_ status: OSStatus) -> ErrorCode {
        ErrorCode(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// Decision 0040: the plaintext array this used to be kept in.
//
// **Not a migration.** Nothing is read out of it — the tokens it names were issued under the old
// protocol version and no iPhone can present one any more (REQ-PRT-004). It is erased because
// leaving secrets behind in a plist is worse than leaving a key nobody looks at, and erasing one
// exact key needs no guess about what is in there.
//
// **Reached only through `KeychainDeviceTokenStore`.** `UserDefaults.standard` here is the
// reader's own settings, and a static call sitting outside the seam is a call a test makes.
enum LeftoverPlaintextTokens {
    static let key = "issuedDeviceTokens"

    static func erase(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

// POL-047 / Decision 0040: where the Keychain would be, when this process is hosting a test bundle.
//
// The app builds its model before any view exists, so the guard in `.task` is too late to stop
// what that model holds — the same reason `SilentNotifications` and `SleepLeftAlone` exist.
struct TokensKeptNowhere: DeviceTokenStoring {
    func load() -> DeviceTokenRecords { .onRecord([]) }
    func save(_ tokens: [DeviceToken]) -> ErrorCode? { nil }
    func eraseLeftoverPlaintext() {}
}
