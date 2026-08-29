import SwiftUI
import AppKit
import MdoroCore

// REQ-PRS / 9.2: プリセットの編集。
// REQ-UIX-009: 「次のセッションから適用される」項目と「即座に適用される」項目を視覚的に区別する（9.5）。
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
                Text("Choose a preset").foregroundStyle(.secondary).padding()
            }
        }
        // 設定は macOS 側でいつでも変わる。開くたびに見に行く。
        .task { await model.refreshNotificationPermission() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(model.presets.presets, id: \.id, selection: $selectedId) { preset in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                        if preset.id == model.presets.activePresetId {
                            Text("In use").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(Format.presetShape(preset)).font(.caption).foregroundStyle(.secondary)
                }
                .tag(preset.id)
            }
            Divider()
            HStack(spacing: 4) {
                // REQ-PRS-003: 上限 10 件。
                Button { create() } label: { Image(systemName: "plus") }
                    .disabled(model.presets.presets.count >= 10)
                    .help(model.presets.presets.count >= 10 ? "Up to 10 presets" : "Add")
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(selected == nil)
                // REQ-PRS-004: 使用中のプリセットと最後の1件は削除できない。
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
                // 9.5 C 群
                groupNote("Applies immediately. The log keeps the name from when the session started.")
            }

            Section {
                // REQ-COL-010 / 011: 種別には `-text` のみ。名前を併記するので色だけに頼らない。
                minuteStepper("Focus", binding(preset, \.workSeconds), range: 1...180, role: .sessionFocus)
                minuteStepper("Short Break", binding(preset, \.shortBreakSeconds), range: 1...60, role: .sessionShortBreak)
                minuteStepper("Long Break", binding(preset, \.longBreakSeconds), range: 1...60, role: .sessionLongBreak)
            } header: {
                Text("Session lengths")
            } footer: {
                // REQ-UIX-009 / 9.5 A 群: 実行中の sessionEndAt は変えない。
                groupNote("Applies **from the next session**. The end time of a running session does not change.")
            }

            Section {
                // REQ-UIX-047: 「ラベル・数値・増減・単位」の並びに揃える。
                countStepper("Long break every", binding(preset, \.longBreakInterval),
                             range: 2...12, unit: "loops")
                minuteStepper("Each extension", binding(preset, \.extendSeconds), range: 1...30)
                // REQ-TIM-011（SHOULD）は未実装。**実装していない機能の操作盤を出さない。**
                // 実装するときは REQ-TIM-043 と一緒に戻すこと。
            } header: {
                Text("Flow")
            } footer: {
                // 9.5 B 群
                groupNote("Applies **immediately, including to a running session**.")
            }

            Section {
                // 素の HStack だと Form の中で上端に張り付く。`LabeledContent` で行の中心に揃える。
                LabeledContent {
                    HStack {
                        // Decision 0020: 音色の選択は Mac 専用。
                        Picker("", selection: binding(preset, \.notificationSound)) {
                            ForEach(NotificationSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        // Decision 0019: 本番と同じ経路で通知を1件送る。
                        Button("Send a test") { model.sendNotificationSoundTest(preset) }
                            .help("Sends one notification with this setting")
                    }
                } label: {
                    Text("Mac notification sound")
                }
                groupNote("Chosen from the macOS system sounds. **This choice only affects the Mac.** iPhone uses the iOS default sound. Silent applies to both.")
                // 鳴らない理由がアプリの外にあるなら、アプリが言う。
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

    // REQ-NTF-020: 予告通知のトリガは 0〜2 個。
    @ViewBuilder
    private func preNotificationEditor(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heads-up (\(preset.preNotifications.count) / 2)").font(.callout)

            ForEach(Array(preset.preNotifications.enumerated()), id: \.offset) { index, trigger in
                HStack {
                    Text(describe(trigger, in: preset))
                    // REQ-NTF-021: 発火時刻がセッション開始以前になる場合はスケジュールされない旨を示す。
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
                    // Decision 0012: 残り1〜15分を1分単位。
                    Menu("By time left") {
                        ForEach(1...15, id: \.self) { minutes in
                            Button("\(minutes) min left") { addTrigger(preset, .beforeEnd(seconds: minutes * 60)) }
                        }
                    }
                    // 経過 50〜95% を5刻み。
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

    // 追加メニューの項目（`Button` の題）と同じ鍵になるよう、同じ書き方で組む。
    private func describe(_ trigger: PreNotification, in preset: Preset) -> LocalizedStringKey {
        switch trigger {
        case let .beforeEnd(seconds): return "\(seconds / 60) min left"
        case let .atElapsedPercent(percent): return "at \(percent)% elapsed"
        }
    }

    // REQ-NTF-021: 発火時刻がセッション開始時刻以前になるものは鳴らない。
    private func canFire(_ trigger: PreNotification, in preset: Preset) -> Bool {
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(preset.workSeconds))
        return !PreNotificationSchedule.fireDates(
            for: [trigger], sessionStartedAt: start, sessionEndAt: end, now: start
        ).isEmpty
    }

    // REQ-UIX-009: 適用タイミング（9.5 の A / B / C 群）の注記。
    // **`LocalizedStringKey` で受ける。** `String` を `LocalizedStringKey(_:)` に通すと
    // 実行時に鍵が組まれ、Xcode の抽出対象から外れる（Decision 0022）。
    private func groupNote(_ markdown: LocalizedStringKey) -> some View {
        Text(markdown)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: - 編集の適用

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
        // REQ-CFG-011 / 012: UI は分単位、内部は秒。直接入力とステッパーの両方を出す。
        HStack {
            // REQ-COL-011: 使ってよいのは `-graphic` と `-text` だけ。**帯は使えない。**
            // 色付きの文字だけでは弱いので図形を添える。
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
            Text("min").foregroundStyle(.secondary)
        }
    }

    // 分ではない数値（周回など）。並びは minuteStepper と揃える。
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
            Text(unit).foregroundStyle(.secondary)
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
        // **保存される値であって画面の文言ではない。** 利用者はこの場で改名でき、以後この文字列は
        // プリセットの中身として持ち回られる（`Preset.standard()` の "Standard" と同じ扱い）。
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
