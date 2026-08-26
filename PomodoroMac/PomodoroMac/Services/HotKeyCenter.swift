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
    // 割り当てられる操作。増やすときは id が重ならないようにする。
    enum Slot: UInt32, CaseIterable {
        case pauseResume = 1
        case showWindow = 2
    }

    private var refs: [Slot: EventHotKeyRef] = [:]
    private var handlers: [Slot: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x504F_4D44 // 'POMD'

    func update(_ slot: Slot, binding: HotKeyBinding?, onPress: @escaping () -> Void) {
        unregister(slot)
        // 既定は無効。割り当てが無ければ何も登録しない。
        guard let binding, binding.hasModifier else { return }
        handlers[slot] = onPress
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            Self.carbonModifiers(from: binding.modifierFlags),
            EventHotKeyID(signature: Self.signature, id: slot.rawValue),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        // 他アプリが同じ組み合わせを押さえている場合はここで失敗する。
        // 黙って無効になるので、呼び出し側が結果を見て UI に出す。
        if status == noErr, let ref {
            refs[slot] = ref
        }
    }

    func isRegistered(_ slot: Slot) -> Bool { refs[slot] != nil }

    func unregister(_ slot: Slot) {
        if let ref = refs.removeValue(forKey: slot) {
            UnregisterEventHotKey(ref)
        }
        handlers[slot] = nil
    }

    func unregisterAll() {
        for slot in Slot.allCases { unregister(slot) }
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
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                guard let slot = Slot(rawValue: id.id) else { return noErr }
                DispatchQueue.main.async { center.handlers[slot]?() }
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
