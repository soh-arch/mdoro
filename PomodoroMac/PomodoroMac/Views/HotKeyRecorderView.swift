import SwiftUI
import AppKit
import MdoroCore

// REQ-UIX-033: the UI for binding a hot key. Unbound by default.
struct HotKeyRecorderView: View {
    @Environment(\.theme) private var theme
    @Binding var binding: HotKeyBinding?
    let isActive: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(isRecording ? theme.textSecondary : theme.textPrimary)
                .frame(minWidth: 90, alignment: .trailing)
                .monospaced()

            Button(isRecording ? "Cancel" : "Change…") {
                isRecording ? stopRecording() : startRecording()
            }
            if binding != nil {
                Button("Clear") {
                    stopRecording()
                    binding = nil
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return String(localized: "Press a key") }
        guard let binding else { return String(localized: "Not set") }
        // Taken by another app, a binding is there and does nothing. That is not hidden.
        // **The key name is the combination the user pressed, and the value saved into the settings.**
        // It is not something to translate.
        return isActive ? binding.displayName : String(localized: "\(binding.displayName) (unavailable)")
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])

            // ⎋ cancels.
            if event.keyCode == 53, modifiers.isEmpty {
                stopRecording()
                return nil
            }
            // A combination with no modifier is not accepted. Take a bare key and typing text stops working
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
