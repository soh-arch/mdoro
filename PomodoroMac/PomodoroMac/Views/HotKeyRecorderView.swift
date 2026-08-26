import SwiftUI
import AppKit
import PomodoroCore

// REQ-UIX-033: ホットキーの割り当て UI。
// 既定は未割り当て。押されたキーをその場で記録する。
struct HotKeyRecorderView: View {
    @Binding var binding: HotKeyBinding?
    let isActive: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 90, alignment: .trailing)
                .monospaced()

            Button(isRecording ? "キャンセル" : "変更…") {
                isRecording ? stopRecording() : startRecording()
            }
            if binding != nil {
                Button("解除") {
                    stopRecording()
                    binding = nil
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return "キーを押す" }
        guard let binding else { return "未設定" }
        // 他アプリに取られている場合は、割り当ててあるのに効かない。それを隠さない。
        return isActive ? binding.displayName : "\(binding.displayName)（使用できません）"
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])

            // ⎋ で取りやめ。
            if event.keyCode == 53, modifiers.isEmpty {
                stopRecording()
                return nil
            }
            // 修飾キーなしは受け付けない。単独キーを奪うと文字入力ができなくなる。
            guard !modifiers.isEmpty else { return nil }

            binding = HotKeyBinding(
                keyCode: event.keyCode,
                modifierFlags: modifiers.rawValue,
                displayName: HotKeyCenter.displayName(
                    keyCode: event.keyCode,
                    modifiers: modifiers,
                    characters: event.charactersIgnoringModifiers
                )
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
