import Foundation
import Security
import MdoroCore

// REQ-SEC-001 / 002 / Decision 0040: everything the client asks of the Keychain, so a test can
// stand where the OS does.
//
// **The same seam as `SessionNotifying` and `IdleSleepGuarding` on the Mac side:** a protocol, a
// real implementation that is the default, and a substitute chosen where the model is built. The
// suite runs inside MdoroiOS.app, under its bundle identifier, so an item a test writes lands in
// the reader's own Keychain and outlives the run (POL-047 is the same shape).
//
// **Every entry point takes a `ServerID`.** That is the whole of the fix: the account name used to
// be a `String` that callers filled with whatever "server name" was nearest — the Bonjour instance
// name at the saving end, `welcome.serverName` at the reading end — and mDNSResponder renaming a
// registration to `Mdoro (2)` turned a paired Mac into an unknown one. A display name cannot be
// passed here any more, because it is a `String` and this is not.
protocol TokenStoring: Sendable {
    func load(serverId: ServerID) -> String?
    func save(_ token: String, serverId: ServerID)
    func delete(serverId: ServerID)
}

// REQ-SEC-001: the device token is kept in the Keychain.
// Put in UserDefaults, it could be carried off in a backup or a settings export.
struct TokenKeychain: TokenStoring {
    private let service = "com.sohta.Mdoro.deviceToken"

    func load(serverId: ServerID) -> String? {
        var query = baseQuery(serverId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String, serverId: ServerID) {
        let query = baseQuery(serverId)
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(token.utf8)
        // Decision 0040: **this device and no other.** Without it the token rides along in an
        // encrypted backup, so a phone restored from one authenticates as the phone that was
        // paired — and the Mac, which knows only that the token is one it issued, lets it in.
        // Unlocked rather than after-first-unlock: nothing here runs in the background.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    func delete(serverId: ServerID) {
        SecItemDelete(baseQuery(serverId) as CFDictionary)
    }

    private func baseQuery(_ serverId: ServerID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            // Decision 0040: the id from the TXT record. Never a name.
            kSecAttrAccount as String: serverId.value,
        ]
    }
}
