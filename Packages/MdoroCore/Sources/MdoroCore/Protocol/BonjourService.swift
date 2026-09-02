import Foundation

// REQ-COM-003 / REQ-PRT-001: what goes on the air, written once for the side that advertises and
// the side that browses.
//
// The service type and the TXT keys used to be spelled out at both ends, in two files that never
// see each other. **A key spelled differently on one side is not a build error** — it is a Mac
// that answers and cannot be paired with, which is exactly the failure Decision 0040 is about.
public enum BonjourService {
    // Decision 0024: renamed with everything else.
    public static let type = "_mdoro._tcp"

    // The port the sync WebSocket listens on. REQ-COM-002 (v2.25): `GET /info` is gone, and the
    // registration rides the WebSocket listener itself now, so this is the advertising listener's
    // own port — the browsing side keeps reading it from the TXT record either way.
    public static let websocketPortKey = "ws"
    // REQ-PRT-004: so a version that cannot speak to this one is visible before a connection.
    public static let versionKey = "v"
    // Decision 0040: the only value on the air that identifies this Mac.
    public static let identityKey = "id"

    // Decision 0040 (judgement 5): mDNSResponder renames a colliding registration rather than
    // refusing it (`docs/platform/0008` — ` (2)` and so on), so the name that actually went on
    // the air is the one piece of evidence that another Mdoro shares this LAN. Non-nil is that
    // evidence; nil says the requested name is the registered one.
    public static func alternateRegisteredName(registered: String, requested: String) -> String? {
        registered == requested ? nil : registered
    }

    public static func txtEntries(websocketPort: UInt16, serverId: ServerID) -> [String: String] {
        [
            websocketPortKey: String(websocketPort),
            versionKey: String(PomodoroProtocol.version),
            identityKey: serverId.value,
        ]
    }
}
