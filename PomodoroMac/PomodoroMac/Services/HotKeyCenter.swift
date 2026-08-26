import AppKit
import Carbon.HIToolbox
import PomodoroCore

// REQ-UIX-033: グローバルショートカット。
//
// `RegisterEventHotKey`（Carbon）を使う。**アクセシビリティ権限を要求しない**のが理由。
// `NSEvent.addGlobalMonitorForEvents` は権限が要り、タイマーを一時停止したいだけの機能に
// 「このアプリにコンピュータの制御を許可しますか」を出すのは釣り合わない。
@MainActor
final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?

    private static let signature: OSType = 0x504F_4D44 // 'POMD'

    func update(binding: HotKeyBinding?, onPress: @escaping () -> Void) {
        unregister()
        // 既定は無効。割り当てが無ければ何も登録しない。
        guard let binding, binding.hasModifier else { return }
        self.onPress = onPress
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            Self.carbonModifiers(from: binding.modifierFlags),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        // 他アプリが同じ組み合わせを押さえている場合はここで失敗する。
        // 黙って無効になるので、呼び出し側が結果を見て UI に出す。
        hotKeyRef = (status == noErr) ? ref : nil
    }

    var isRegistered: Bool { hotKeyRef != nil }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onPress?() }
                return noErr
            },
            1, &spec, context, &handlerRef
        )
    }

    // NSEvent.ModifierFlags -> Carbon の修飾マスク。
    private static func carbonModifiers(from flags: UInt) -> UInt32 {
        let modifiers = NSEvent.ModifierFlags(rawValue: flags)
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    // 表示用の記号。設定画面で「いま何が割り当てられているか」を読めるようにする。
    static func displayName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }

        if let characters, let first = characters.uppercased().first, first.isLetter || first.isNumber {
            text.append(first)
        } else {
            text += Self.specialKeyNames[keyCode] ?? "Key \(keyCode)"
        }
        return text
    }

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
}
