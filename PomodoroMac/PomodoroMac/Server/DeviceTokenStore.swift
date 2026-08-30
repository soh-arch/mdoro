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
protocol DeviceTokenStoring: Sendable {
    func load() -> [DeviceToken]
    func save(_ tokens: [DeviceToken])
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

    func load() -> [DeviceToken] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let tokens = try? MessageCoder.decoder.decode([DeviceToken].self, from: data)
        else { return [] }
        return tokens
    }

    func save(_ tokens: [DeviceToken]) {
        guard let data = try? MessageCoder.encoder.encode(tokens) else { return }
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        // The Mac has to authenticate a returning iPhone whenever it is running, and it can be
        // running before anyone unlocks the screen. Not `ThisDeviceOnly` for the same reason the
        // iPhone's is: this one is not on iCloud Keychain to begin with (no `kSecAttrSynchronizable`),
        // and a Mac restored from a backup that has forgotten its pairings is the state Decision
        // 0040 already accepts.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
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
    func load() -> [DeviceToken] { [] }
    func save(_ tokens: [DeviceToken]) {}
}
