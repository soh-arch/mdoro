import SwiftUI
import AppKit
import MdoroCore

// REQ-PRS / 9.2: editing the presets.
// REQ-UIX-009: the items that "apply from the next session" and the items that "apply immediately"
// are told apart by eye (9.5).
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var selectedId: String?
    @State private var errorMessage: String?

    private var selected: Preset? {
        selectedId.flatMap { model.presets.preset(id: $0) } ?? model.presets.activePreset
    }

    var body: some View {
        HSplitView {
            list
            if let preset = selected {
                editor(for: preset)
            } else {
                Text("Choose a preset").foregroundStyle(theme.textSecondary).padding()
            }
        }
        // The settings can change on the macOS side at any moment. They are read again every time this opens.
        .task { await model.refreshNotificationPermission() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(model.presets.presets, id: \.id, selection: $selectedId) { preset in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                        if preset.id == model.presets.activePresetId {
                            Text("In use").font(.caption2).foregroundStyle(theme.textSecondary)
                        }
                    }
                    Text(Format.presetShape(preset)).font(.caption).foregroundStyle(theme.textSecondary)
                }
                .tag(preset.id)
            }
            Divider()
            HStack(spacing: 4) {
                // REQ-PRS-003: at most 10.
                Button { create() } label: { Image(systemName: "plus") }
                    .disabled(model.presets.presets.count >= 10)
                    .help(model.presets.presets.count >= 10 ? "Up to 10 presets" : "Add")
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(selected == nil)
                // REQ-PRS-004: the preset in use and the last one left cannot be deleted.
                Button { delete() } label: { Image(systemName: "minus") }
                    .disabled(!canDelete)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .frame(minWidth: 180, maxWidth: 240)
    }

    private var canDelete: Bool {
        guard let selected else { return false }
        return selected.id != model.presets.activePresetId && model.presets.presets.count > 1
    }

    @ViewBuilder
    private func editor(for preset: Preset) -> some View {
        Form {
            // REQ-COL-001 / 002: the role, not the hue. The edit was refused, so `danger`.
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(theme.color(.danger, .text))
            }

            Section {
                TextField("Name", text: binding(preset, \.name))
            } header: {
                Text("Identity")
            } footer: {
                // 9.5 group C
                groupNote("Applies immediately. The log keeps the name from when the session started.")
            }

            Section {
                // REQ-COL-010 / 011: only `-text` for a session type. The name is written alongside, so
                // nothing rides on colour alone.
                minuteStepper("Focus", binding(preset, \.workSeconds), range: 1...180, role: .sessionFocus)
                minuteStepper("Short Break", binding(preset, \.shortBreakSeconds), range: 1...60, role: .sessionShortBreak)
                minuteStepper("Long Break", binding(preset, \.longBreakSeconds), range: 1...60, role: .sessionLongBreak)
            } header: {
                Text("Session lengths")
            } footer: {
                // REQ-UIX-009 / 9.5 group A: the sessionEndAt of a running session is not changed.
                groupNote("Applies **from the next session**. The end time of a running session does not change.")
            }

            Section {
                // REQ-UIX-047: laid out in the order label, value, stepper, unit.
                countStepper("Long break every", binding(preset, \.longBreakInterval),
                             range: 2...12, unit: "loops")
                minuteStepper("Each extension", binding(preset, \.extendSeconds), range: 1...30)
                // REQ-TIM-011 (SHOULD) is not implemented. **No controls are shown for a feature that
                // is not there.** When it is implemented, bring this back together with REQ-TIM-043.
            } header: {
                Text("Flow")
            } footer: {
                // 9.5 group B
                groupNote("Applies **immediately, including to a running session**.")
            }

            Section {
                // A bare HStack sticks to the top edge inside a Form. `LabeledContent` centres it in the row.
                LabeledContent {
                    HStack {
                        // Decision 0020: choosing the sound is for the Mac alone.
                        Picker("", selection: binding(preset, \.notificationSound)) {
                            ForEach(NotificationSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        // Decision 0019: send one notification down the same path production uses.
                        Button("Send a test") { model.sendNotificationSoundTest(preset) }
                            .help("Sends one notification with this setting")
                    }
                } label: {
                    Text("Mac notification sound")
                }
                groupNote("Chosen from the macOS system sounds. **This choice only affects the Mac.** iPhone uses the iOS default sound. Silent applies to both.")
                // If the reason nothing sounds lies outside the app, the app is the one that says so.
                // REQ-COL-001 / 002: the role, not the hue. Both lines say the same thing —
                // notifications may not reach you, and the fix is outside this app — so they
                // keep one role between them. `warning`: the timer itself runs either way.
                if let problem = model.notificationPermission?.problem {
                    Text(problem).font(.footnote).foregroundStyle(theme.color(.warning, .text))
                }
                if let error = model.notificationAuthorizationError {
                    Text(error).font(.footnote).foregroundStyle(theme.color(.warning, .text))
                }
                Toggle("Notify during Focus modes", isOn: binding(preset, \.timeSensitiveNotifications))
                preNotificationEditor(preset)
            } header: {
                Text("Notifications")
            } footer: {
                groupNote("Applies **immediately, including to a running session**.")
            }
        }
        .formStyle(.grouped)
    }

    // REQ-NTF-020: zero to two pre-notification triggers.
    @ViewBuilder
    private func preNotificationEditor(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heads-up (\(preset.preNotifications.count) / 2)").font(.callout)

            ForEach(Array(preset.preNotifications.enumerated()), id: \.offset) { index, trigger in
                HStack {
                    Text(describe(trigger, in: preset))
                    // REQ-NTF-021: show that a trigger whose fire time falls at or before the session
                    // start is not scheduled.
                    if !canFire(trigger, in: preset) {
                        // REQ-COL-001 / 002: the role, not the hue. `warning`: the trigger is
                        // valid, it just cannot fire while the session is this short.
                        Label("Will not fire at this session length", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(theme.color(.warning, .text))
                    }
                    Spacer()
                    Button { removeTrigger(preset, at: index) } label: {
                        Text("Remove").foregroundStyle(theme.color(.danger, .text))
                    }
                    .buttonStyle(.plain)
                }
            }

            if preset.preNotifications.count < 2 {
                Menu("Add a trigger") {
                    // Decision 0012: one to fifteen minutes left, in steps of a minute.
                    Menu("By time left") {
                        ForEach(1...15, id: \.self) { minutes in
                            Button("\(minutes) min left") { addTrigger(preset, .beforeEnd(seconds: minutes * 60)) }
                        }
                    }
                    // 50% to 95% elapsed, in steps of five.
                    Menu("By percent elapsed") {
                        ForEach(Array(stride(from: 50, through: 95, by: 5)), id: \.self) { percent in
                            Button("at \(percent)% elapsed") { addTrigger(preset, .atElapsedPercent(percent)) }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    // Written the same way as the items in the add menu (the `Button` titles), so that it makes the same key.
    private func describe(_ trigger: PreNotification, in preset: Preset) -> LocalizedStringKey {
        switch trigger {
        case let .beforeEnd(seconds): return "\(seconds / 60) min left"
        case let .atElapsedPercent(percent): return "at \(percent)% elapsed"
        }
    }

    // REQ-NTF-021: one whose fire time falls at or before the session start time never sounds.
    private func canFire(_ trigger: PreNotification, in preset: Preset) -> Bool {
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(preset.workSeconds))
        return !PreNotificationSchedule.fireDates(
            for: [trigger], sessionStartedAt: start, sessionEndAt: end, now: start
        ).isEmpty
    }

    // REQ-UIX-009: the note on when a change applies (groups A / B / C of 9.5).
    // **Taken as a `LocalizedStringKey`.** Put a `String` through `LocalizedStringKey(_:)` and the key
    // is built at run time, which takes it outside what Xcode extracts (Decision 0022).
    private func groupNote(_ markdown: LocalizedStringKey) -> some View {
        Text(markdown)
            .font(.footnote)
            .foregroundStyle(theme.textSecondary)
    }

    // MARK: - Applying an edit

    private func binding<V>(_ preset: Preset, _ keyPath: WritableKeyPath<Preset, V>) -> Binding<V> {
        Binding(
            get: { preset[keyPath: keyPath] },
            set: { newValue in
                var updated = preset
                updated[keyPath: keyPath] = newValue
                apply(updated)
            }
        )
    }

    private func minuteStepper(
        _ title: LocalizedStringKey, _ seconds: Binding<Int>, range: ClosedRange<Int>, role: ColorRole? = nil
    ) -> some View {
        // REQ-CFG-011 / 012: the UI is in minutes, the inside is in seconds. Both direct entry and a
        // stepper are offered.
        HStack {
            // REQ-COL-011: only `-graphic` and `-text` may be used. **The banner treatment is not
            // available.** Coloured text on its own is too weak, so a shape goes with it.
            if let role {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.color(role, .graphic))
                    .frame(width: 4, height: 18)
            }
            Text(title)
                .fontWeight(role == nil ? .regular : .medium)
                .foregroundStyle(role.map { theme.color($0, .text) } ?? theme.textPrimary)
            Spacer()
            TextField("", value: Binding(
                get: { seconds.wrappedValue / 60 },
                set: { seconds.wrappedValue = min(max($0, range.lowerBound), range.upperBound) * 60 }
            ), format: .number)
            .frame(width: 52)
            .multilineTextAlignment(.trailing)
            Stepper("") {
                seconds.wrappedValue = min(seconds.wrappedValue + 60, range.upperBound * 60)
            } onDecrement: {
                seconds.wrappedValue = max(seconds.wrappedValue - 60, range.lowerBound * 60)
            }
            .labelsHidden()
            Text("min").foregroundStyle(theme.textSecondary)
        }
    }

    // A value that is not in minutes (loops and the like). The layout matches minuteStepper.
    private func countStepper(
        _ title: LocalizedStringKey, _ value: Binding<Int>, range: ClosedRange<Int>, unit: LocalizedStringKey
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
            ), format: .number)
            .frame(width: 52)
            .multilineTextAlignment(.trailing)
            Stepper("") {
                value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
            } onDecrement: {
                value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
            }
            .labelsHidden()
            Text(unit).foregroundStyle(theme.textSecondary)
        }
    }

    private func addTrigger(_ preset: Preset, _ trigger: PreNotification) {
        var updated = preset
        updated.preNotifications.append(trigger)
        apply(updated)
    }

    private func removeTrigger(_ preset: Preset, at index: Int) {
        var updated = preset
        updated.preNotifications.remove(at: index)
        apply(updated)
    }

    private func apply(_ updated: Preset) {
        errorMessage = message(for: model.send(.updatePreset(updated)))
    }

    private func create() {
        var new = Preset.standard(id: UUID().uuidString)
        // **A value that gets saved, not wording on the screen.** The user can rename it right here, and
        // from then on this string is carried around as the content of the preset (treated the same as
        // "Standard" in `Preset.standard()`).
        new.name = "New Preset"
        new.isBuiltInDefault = false
        errorMessage = message(for: model.send(.createPreset(new)))
        selectedId = new.id
    }

    private func duplicate() {
        guard let selected else { return }
        errorMessage = message(for: model.send(.duplicatePreset(id: selected.id)))
    }

    private func delete() {
        guard let selected else { return }
        errorMessage = message(for: model.send(.deletePreset(id: selected.id)))
        selectedId = model.presets.activePresetId
    }

    private func message(for error: TimerError?) -> String? {
        switch error {
        case nil: return nil
        case .presetNameConflict: return String(localized: "Another preset already has that name.")
        case .presetLimitReached: return String(localized: "Up to 10 presets.")
        case .cannotDeleteActivePreset: return String(localized: "The preset in use cannot be deleted.")
        case .cannotDeleteLastPreset: return String(localized: "The last preset cannot be deleted.")
        case .settingOutOfRange: return String(localized: "That is outside the allowed range.")
        default: return String(localized: "That action was not accepted.")
        }
    }
}
