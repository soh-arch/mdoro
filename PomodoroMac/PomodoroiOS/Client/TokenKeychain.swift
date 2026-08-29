import Foundation
import Security

// REQ-SEC-001: the device token is kept in the Keychain.
// Put in UserDefaults, it could be carried off in a backup or a settings export.
enum TokenKeychain {
    private static let service = "com.sohta.Mdoro.deviceToken"

    static func load(serverName: String) -> String? {
        var query = baseQuery(serverName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, serverName: String) {
        let query = baseQuery(serverName)
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func delete(serverName: String) {
        SecItemDelete(baseQuery(serverName) as CFDictionary)
    }

    private static func baseQuery(_ serverName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverName,
        ]
    }
}
