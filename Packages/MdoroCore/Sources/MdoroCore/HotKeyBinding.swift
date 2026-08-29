import Foundation

// REQ-UIX-033 / Decision 0016: global shortcuts. **Off by default**; the user picks the assignment.
public struct HotKeyBinding: Equatable, Sendable, Codable, Hashable {
    public var keyCode: UInt16
    // The rawValue of NSEvent.ModifierFlags (the device-independent bits only).
    public var modifierFlags: UInt
    // The display name as recorded ("⌘⌥P" and the like), which saves carrying a key code table.
    public var displayName: String

    public init(keyCode: UInt16, modifierFlags: UInt, displayName: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayName = displayName
    }

    // A binding without a modifier is refused: taking a bare key away stops the user typing.
    public var hasModifier: Bool {
        let command: UInt = 1 << 20
        let option: UInt = 1 << 19
        let control: UInt = 1 << 18
        let shift: UInt = 1 << 17
        return modifierFlags & (command | option | control | shift) != 0
    }
}
