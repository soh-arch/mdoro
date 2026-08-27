import SwiftUI
import MdoroCore

// REQ-UIX-001: iPhone の通常画面では全機能（設定、タスク選択、タイマー操作）を提供する。
struct MainScreen: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(ClientModel.self) private var model
    @State private var isAppearancePresented = false

    // Decision 0027: 外観は Mac の設定ではなく、**この端末の設定**に従う。
    private var theme: Theme {
        Theme(appearance: model.appearance, systemScheme: systemScheme)
    }
    private var preset: Preset { model.snapshot?.presets.activePreset ?? Preset.standard() }
    private var timer: TimerContext { model.snapshot?.timer ?? .idle(now: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ConnectionBanner()

                    if let pending = timer.pendingDecision, timer.runState == .pendingDecision {
                        // REQ-UIX-036 / REQ-PER-005
                        PendingDecisionCard(pending: pending)
                    }

                    SessionHeader(
                        sessionType: timer.sessionType,
                        runState: timer.runState,
                        loopDisplay: timer.displayLoop(longBreakInterval: preset.longBreakInterval),
                        longBreakInterval: preset.longBreakInterval
                    )
                    timerReadout
                    controls
                    presetRow
                    Divider().overlay(theme.borderSubtle)
                    TaskListSectionView()
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle("Mdoro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAppearancePresented = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                // iOS 26 は隣り合うツールバー項目を1つの枠にまとめる。
                // **役割が違うので、分けて見せる。**
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    // REQ-UIX-013: 通常画面からの明示操作で集中表示ビューへ。
                    Button {
                        model.isFocusViewPresented = true
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(timer.runState == .idle)
                }
            }
        }
        .environment(\.theme, theme)
        // REQ-COL-003: 設定でライト固定・ダーク固定も選べる。**Mac 側にはあり、ここに無かった。**
        // 無いと、地と文字は自前のパレット、ナビゲーションバーと標準コントロールは OS の外観、
        // という食い違いが起きる。実機では**タイトルが白く飛び、有効なボタンが無効に見えた**
        // （2026-08-27、スクリーンショットで確認）。
        .preferredColorScheme(preferredScheme)
        .fullScreenCover(isPresented: Bindable(model).isFocusViewPresented) {
            FocusView()
        }
        .sheet(isPresented: $isAppearancePresented) {
            DeviceSettingsSheet().environment(\.theme, theme)
        }
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var timerReadout: some View {
        let remaining = model.remainingSeconds()
        return VStack(spacing: 4) {
            Text(Format.clock(remaining))
                .font(.system(size: 68, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
                .accessibilityLabel(Format.spokenRemaining(remaining))
            // REQ-COM-012: 00:00 に達しても完了を確定しない。「同期待ち」と示す。
            if model.isAwaitingSync {
                Text("Waiting for sync")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // REQ-COM-013: 切断中は操作系 UI を無効化する。
    // REQ-UIX-044: ボタンの色は役割名から引く。**OS の既定に委ねない。**
    // 委ねていたために、有効な副次ボタンと無効なボタンが同じ見た目になっていた（2026-08-27、実機）。
    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // REQ-UIX-045 は Mac に限る（Decision 0028）。
            // **iPhone の画面は一等地であり、説明で埋めない。**
            // 押せない理由は Mac の設定画面と、読み上げのラベルが持つ。
            buttonRow
        }
        .buttonStyle(.bordered)
        .tint(theme.color(.accentPrimary, .text))
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack(spacing: 8) {
            switch timer.runState {
            case .idle:
                Button("Start Focus") { model.send(.startWork) }
                    .buttonStyle(.borderedProminent)
                Button("Start Break") {
                    model.send(.startBreak, params: CommandParams(sessionType: nextBreak))
                }
            case .running:
                Button("Pause") { model.send(.pause) }.buttonStyle(.borderedProminent)
                extendButton
                Button("Skip") { model.send(.skip) }
                Button("Stop") { model.send(.abort) }.tint(theme.color(.danger, .text))
            case .paused:
                Button("Resume") { model.send(.resume) }.buttonStyle(.borderedProminent)
                extendButton
                Button("Stop") { model.send(.abort) }.tint(theme.color(.danger, .text))
            case .finished:
                Button("Start Next") { startNext() }.buttonStyle(.borderedProminent)
                extendButton
                Button("Stop") { model.send(.abort) }.tint(theme.color(.danger, .text))
            case .pendingDecision:
                EmptyView()
            }
            Spacer()
        }
        // **ボタンの文字を折り返させない。** 折れると行の高さが揃わず、押す場所が読めなくなる。
        .lineLimit(1)
        .disabled(!model.isConnected)
    }

    // REQ-TIM-044: 休憩に延長はない。REQ-TIM-046: 窓の外では無効。
    @ViewBuilder
    private var extendButton: some View {
        if timer.sessionType == .work {
            Button("+\(preset.extendSeconds / 60) min") { model.send(.extend) }
                .accessibilityLabel("Extend by \(preset.extendSeconds / 60) minutes")
                .disabled(!TimerEngine.isWithinExtensionWindow(timer, now: model.displayNow))
        }
    }

    private var nextBreak: SessionType {
        timer.nextSessionType == .work ? .shortBreak : timer.nextSessionType
    }

    private func startNext() {
        if timer.nextSessionType == .work {
            model.send(.startWork)
        } else {
            model.send(.startBreak, params: CommandParams(sessionType: timer.nextSessionType))
        }
    }

    // REQ-UIX-007 / 008: 有効なプリセット名を常時表示し、2件以上なら2タップ以内で切り替える。
    @ViewBuilder
    private var presetRow: some View {
        let presets = model.snapshot?.presets.presets ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Preset").font(.footnote).foregroundStyle(theme.textTertiary)
                if presets.count >= 2 {
                    Menu("\(preset.name)（\(Format.presetShape(preset))）") {
                        ForEach(presets) { candidate in
                            Button("\(candidate.name)（\(Format.presetShape(candidate))）") {
                                model.send(.selectPreset, params: CommandParams(presetId: candidate.id))
                            }
                        }
                    }
                    .disabled(!model.isConnected)
                } else {
                    // REQ-PRS-013: 1件のときは切替 UI を出さない。追加は Mac 側で行う。
                    Text("\(preset.name)（\(Format.presetShape(preset))）")
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()
            }
            .font(.callout)

        }
    }
}

// REQ-UIX-002 / 003: 種別を色と文言の両方で示し、周回を n / interval で表示する。
struct SessionHeader: View {
    @Environment(\.theme) private var theme
    let sessionType: SessionType
    let runState: RunState
    let loopDisplay: Int
    let longBreakInterval: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(lineWidth: 3)
                .frame(width: 14, height: 14)
                .foregroundStyle(theme.color(sessionType.colorRole, .graphic))
            Text(Format.sessionLabel(sessionType))
                .font(.headline)
                .foregroundStyle(theme.color(sessionType.colorRole, .text))
            if runState == .paused {
                Text("Paused").font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("\(loopDisplay) / \(longBreakInterval)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("Loop \(loopDisplay) of \(longBreakInterval)")
        }
    }
}

// この端末の設定。**Mac の設定ではない。**
// 外観（Decision 0027）と、ペアリングの解除だけを置く。
struct DeviceSettingsSheet: View {
    @Environment(ClientModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // **ラベル行を出さない。** 出すと選べる項目が4つあるように見える。
                    Picker("Appearance", selection: Binding(
                        get: { model.appearance },
                        set: { model.setAppearance($0) }
                    )) {
                        Text("System").tag(AppearancePreference.system)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Dark").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Applies to this iPhone only. The Mac keeps its own.")
                }

                // decisions/0021: 支援リンクはここに1つだけ。Mac の About と同じ並びにする（REQ-UIX-047）。
                Section {
                    LabeledContent("Version", value: AppInfo.version())
                    LabeledContent("License", value: AppInfo.license)
                    Button { openURL(AppInfo.sourceURL) } label: {
                        LabeledContent("Source") {
                            Text(AppInfo.sourceLabel)
                                .foregroundStyle(theme.color(.accentPrimary, .text))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(AppInfo.sourceLabel) in Safari")
                    // 開く前にリンク先を見せる。REQ-COL-002: ラベルを自分で塗り、素のボタンにする。
                    Button { openURL(AppInfo.supportURL) } label: {
                        Text(AppInfo.supportLabel)
                            .foregroundStyle(theme.color(.accentPrimary, .text))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(AppInfo.supportLabel) in Safari")
                } header: {
                    Text(AppInfo.name)
                } footer: {
                    // REQ-NFR-008
                    Text("No ads, no in-app purchases, no analytics. The link opens in Safari.")
                }

                if let paired = model.pairedServerName {
                    Section {
                        Button("Forget \(paired)", role: .destructive) { isConfirmingForget = true }
                    } header: {
                        Text("Pairing")
                    } footer: {
                        Text("Removes this device's registration. Pairing again takes a six-digit code.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Forget this Mac?", isPresented: $isConfirmingForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    model.forgetPairedMac()
                    dismiss()
                }
            }
        }
    }
}
