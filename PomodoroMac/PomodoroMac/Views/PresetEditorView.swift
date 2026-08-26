import SwiftUI
import AppKit
import PomodoroCore

// REQ-PRS / 9.2: プリセットの編集。
// REQ-UIX-009: 「次のセッションから適用される」項目と「即座に適用される」項目を視覚的に区別する（9.5）。
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
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
                Text("プリセットを選んでください").foregroundStyle(.secondary).padding()
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(model.presets.presets, id: \.id, selection: $selectedId) { preset in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                        if preset.id == model.presets.activePresetId {
                            Text("使用中").font(.caption2).foregroundStyle(.secondary)
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
                    .help(model.presets.presets.count >= 10 ? "プリセットは10件までです" : "追加")
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
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }

            Section {
                TextField("名前", text: binding(preset, \.name))
            } header: {
                Text("識別")
            } footer: {
                // 9.5 C 群
                groupNote("即座に反映されます。ログには開始時点の名前が残ります。")
            }

            Section {
                minuteStepper("Focus", binding(preset, \.workSeconds), range: 1...180)
                minuteStepper("短い休憩", binding(preset, \.shortBreakSeconds), range: 1...60)
                minuteStepper("長い休憩", binding(preset, \.longBreakSeconds), range: 1...60)
            } header: {
                Text("セッションの長さ")
            } footer: {
                // REQ-UIX-009 / 9.5 A 群: 実行中の sessionEndAt は変えない。
                groupNote("**次に開始されるセッションから**適用されます。実行中のセッションの終了時刻は変わりません。")
            }

            Section {
                Stepper(value: binding(preset, \.longBreakInterval), in: 2...12) {
                    Text("長い休憩を挟む間隔：\(preset.longBreakInterval) 回")
                }
                minuteStepper("延長1回あたり", binding(preset, \.extendSeconds), range: 1...30)
                Toggle("終了後に自動で次へ進む", isOn: binding(preset, \.autoAdvance))
                if preset.autoAdvance {
                    // REQ-TIM-043: autoAdvance は猶予を放棄することを意味する。
                    groupNote("自動で次が始まるため、終了後の猶予（延長・中断を選べる1分）はなくなります。")
                }
            } header: {
                Text("進行")
            } footer: {
                // 9.5 B 群
                groupNote("**実行中のセッションにも即座に**適用されます。")
            }

            Section {
                HStack {
                    Picker("通知音", selection: binding(preset, \.notificationSound)) {
                        ForEach(NotificationSound.allCases, id: \.self) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    // 選ぶ前に聞けないと、名前だけでは違いが分からない。
                    Button("試聴") { preview(preset.notificationSound) }
                        .disabled(preset.notificationSound.isSilent)
                }
                groupNote("macOS のシステムサウンドを使います。無音を選ぶと音は鳴りません。")
                Toggle("集中モード中も通知する", isOn: binding(preset, \.timeSensitiveNotifications))
                preNotificationEditor(preset)
            } header: {
                Text("通知")
            } footer: {
                groupNote("**実行中のセッションにも即座に**適用されます。")
            }
        }
        .formStyle(.grouped)
    }

    // REQ-NTF-020: 予告通知のトリガは 0〜2 個。
    @ViewBuilder
    private func preNotificationEditor(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("予告通知（\(preset.preNotifications.count) / 2）").font(.callout)

            ForEach(Array(preset.preNotifications.enumerated()), id: \.offset) { index, trigger in
                HStack {
                    Text(describe(trigger, in: preset))
                    // REQ-NTF-021: 発火時刻がセッション開始以前になる場合はスケジュールされない旨を示す。
                    if !canFire(trigger, in: preset) {
                        Label("このセッション長では鳴りません", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("削除") { removeTrigger(preset, at: index) }.buttonStyle(.link)
                }
            }

            if preset.preNotifications.count < 2 {
                Menu("トリガを追加") {
                    // 承認済みの刻み（Decision 0012）: 残り1〜15分を1分単位。
                    Menu("残り時間で指定") {
                        ForEach(1...15, id: \.self) { minutes in
                            Button("残り \(minutes) 分") { addTrigger(preset, .beforeEnd(seconds: minutes * 60)) }
                        }
                    }
                    // 経過 50〜95% を5刻み。
                    Menu("経過割合で指定") {
                        ForEach(Array(stride(from: 50, through: 95, by: 5)), id: \.self) { percent in
                            Button("\(percent)% 経過時") { addTrigger(preset, .atElapsedPercent(percent)) }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    private func describe(_ trigger: PreNotification, in preset: Preset) -> String {
        switch trigger {
        case let .beforeEnd(seconds): return "残り \(seconds / 60) 分"
        case let .atElapsedPercent(percent): return "\(percent)% 経過時"
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

    private func preview(_ sound: NotificationSound) {
        guard !sound.isSilent else { return }
        guard let fileName = sound.systemSoundFileName else {
            NSSound.beep()
            return
        }
        NSSound(named: NSSound.Name((fileName as NSString).deletingPathExtension))?.play()
    }

    // REQ-UIX-009: 適用タイミング（9.5 の A / B / C 群）を視覚的に区別するための注記。
    private func groupNote(_ markdown: String) -> some View {
        Text(.init(markdown))
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

    private func minuteStepper(_ title: String, _ seconds: Binding<Int>, range: ClosedRange<Int>) -> some View {
        // REQ-CFG-011 / 012: UI は分単位、内部は秒。直接入力とステッパーの両方を出す。
        HStack {
            Text(title)
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
            Text("分").foregroundStyle(.secondary)
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
        new.name = "新しいプリセット"
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
        case .presetNameConflict: return "同じ名前のプリセットがあります。"
        case .presetLimitReached: return "プリセットは10件までです。"
        case .cannotDeleteActivePreset: return "使用中のプリセットは削除できません。"
        case .cannotDeleteLastPreset: return "最後の1件は削除できません。"
        case .settingOutOfRange: return "設定できる範囲を超えています。"
        default: return "この操作は受け付けられませんでした。"
        }
    }
}
