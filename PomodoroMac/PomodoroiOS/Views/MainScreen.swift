import SwiftUI
import MdoroCore

// REQ-UIX-001: iPhone の通常画面では全機能（設定、タスク選択、タイマー操作）を提供する。
struct MainScreen: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(ClientModel.self) private var model

    private var theme: Theme {
        Theme(appearance: model.snapshot?.settings.appearance ?? .system, systemScheme: systemScheme)
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
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.snapshot?.settings.appearance ?? .system {
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
        VStack(alignment: .leading, spacing: 6) {
            buttonRow
            // REQ-UIX-045: 無効にした操作には、無効である理由を示す。
            if let reason = extendDisabledReason {
                Text(reason).font(.caption).foregroundStyle(theme.textTertiary)
            }
        }
        .buttonStyle(.bordered)
        .tint(theme.color(.accentPrimary, .text))
    }

    // REQ-TIM-046: 受付ウィンドウの外では押せない。押せない理由は上に出す。
    private var extendDisabledReason: String? {
        guard timer.sessionType == .work, timer.runState != .idle else { return nil }
        guard !TimerEngine.isWithinExtensionWindow(timer, now: model.displayNow) else { return nil }
        return "Extending opens in the last 5 minutes"
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack(spacing: 10) {
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
            Button("Extend +\(preset.extendSeconds / 60)m") { model.send(.extend) }
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

            // Decision 0020: 音色の選択は Mac 専用で、iPhone には効かない。
            // 共通の設定に見えるので、効かない側に書いておく。
            if preset.notificationSound != .silent {
                Text("iPhone uses the iOS default sound. The choice of tone is Mac only.")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
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
        HStack(spacing: 10) {
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
