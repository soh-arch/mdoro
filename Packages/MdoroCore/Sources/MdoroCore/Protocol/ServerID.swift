import Foundation

// REQ-COM-003 / REQ-SEC-002 / Decision 0040: **what identifies a Mac is this, and never its name.**
//
// Three names used to stand in for one identity: the Bonjour instance name, which mDNSResponder
// rewrites to `Mdoro (2)` on a collision (`docs/PLATFORM.md`); `welcome.serverName`, which the
// user sets and two Macs can share; and `hello.deviceName`, which belongs to the other end
// entirely. All three were `String`, all three were called some form of "server name", and the
// iPhone keyed its Keychain on one of them — so the OS renaming a registration read as an
// unknown Mac.
//
// A type of its own is the point. `TokenKeychain.load(serverId:)` cannot be handed a display
// name any more, because a display name is a `String` and this is not.
public struct ServerID: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    // Only a UUID gets in. The value arrives in a TXT record, which anyone on the LAN can write,
    // and becomes a Keychain account name on the iPhone — so the shape is settled here rather
    // than wherever it is read.
    public init?(_ text: String) {
        guard let uuid = UUID(uuidString: text) else { return nil }
        self.value = uuid.uuidString
    }

    private init(uuid: UUID) {
        self.value = uuid.uuidString
    }

    // Decision 0040: made once and never again. Making one is this call; keeping it is
    // `ServerIdentityFile`.
    public static func generate() -> ServerID {
        ServerID(uuid: UUID())
    }

    public var description: String { value }
}

// One string, not an object with a field in it: this rides in a TXT record and in a file that
// holds nothing else.
extension ServerID: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ServerID(text) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "not a UUID")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
