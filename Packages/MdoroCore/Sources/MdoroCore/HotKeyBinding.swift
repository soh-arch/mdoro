import Foundation

// REQ-UIX-033 / Decision 0016: グローバルショートカット。**既定は無効**で、割り当てはユーザーが決める。
public struct HotKeyBinding: Equatable, Sendable, Codable, Hashable {
    public var keyCode: UInt16
    // NSEvent.ModifierFlags の rawValue（デバイス非依存のぶんのみ）
    public var modifierFlags: UInt
    // 記録した時点の表示名（"⌘⌥P" など）。キーコード表を持たずに済ませる。
    public var displayName: String

    public init(keyCode: UInt16, modifierFlags: UInt, displayName: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayName = displayName
    }

    // 修飾キーなしの割り当ては受け付けない。単独キーを奪うと文字入力ができなくなる。
    public var hasModifier: Bool {
        let command: UInt = 1 << 20
        let option: UInt = 1 << 19
        let control: UInt = 1 << 18
        let shift: UInt = 1 << 17
        return modifierFlags & (command | option | control | shift) != 0
    }
}
