import Foundation

// REQ-SEC-002: the tokens that have been issued are remembered across a restart.
enum DeviceTokenStore {
    private static let key = "issuedDeviceTokens"

    static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func save(_ tokens: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(tokens), forKey: key)
    }
}
