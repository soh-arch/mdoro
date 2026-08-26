import Foundation

// REQ-SEC-002: 発行済みトークンを再起動をまたいで覚えておく。
// これが消えると、iPhone は毎回ペアリングからやり直しになる。
enum DeviceTokenStore {
    private static let key = "issuedDeviceTokens"

    static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func save(_ tokens: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(tokens), forKey: key)
    }
}
