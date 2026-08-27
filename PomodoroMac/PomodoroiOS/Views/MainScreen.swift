import SwiftUI
import PomodoroCore

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
            .navigationTitle("Pomodoro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // REQ-UIX-013: 通常画面からの明示操作で集中表示ビューへ。
                    Button {
                        model.isFocusViewPresented = true
                    } label: {
                        Label("集中表示", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(timer.runState == .idle)
                }
            }
        }
        .environment(\.theme, theme)
        .fullScreenCover(isPresented: Bindable(model).isFocusViewPresented) {
            FocusView()
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
                Text("同期待ち")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // REQ-COM-013: 切断中は操作系 UI を無効化する。
    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch timer.runState {
            case .idle:
                Button("Focus を開始") { model.send(.startWork) }
                    .buttonStyle(.borderedProminent)
                Button("休憩を開始") {
                    model.send(.startBreak, params: CommandParams(sessionType: nextBreak))
                }
            case .running:
                Button("一時停止") { model.send(.pause) }.buttonStyle(.borderedProminent)
                extendButton
                Button("スキップ") { model.send(.skip) }
                Button("中断") { model.send(.abort) }
            case .paused:
                Button("再開") { model.send(.resume) }.buttonStyle(.borderedProminent)
                extendButton
                Button("中断") { model.send(.abort) }
            case .finished:
                Button("次を開始") { startNext() }.buttonStyle(.borderedProminent)
                extendButton
                Button("中断") { model.send(.abort) }
            case .pendingDecision:
                EmptyView()
            }
            Spacer()
        }
        .disabled(!model.isConnected)
        .buttonStyle(.bordered)
    }

    // REQ-TIM-044: 休憩に延長はない。REQ-TIM-046: 窓の外では無効。
    @ViewBuilder
    private var extendButton: some View {
        if timer.sessionType == .work {
            Button("延長 +\(preset.extendSeconds / 60)分") { model.send(.extend) }
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
        HStack(spacing: 8) {
            Text("プリセット").font(.footnote).foregroundStyle(theme.textTertiary)
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
                Text("一時停止中").font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("\(loopDisplay) / \(longBreakInterval)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("周回 \(loopDisplay) / \(longBreakInterval)")
        }
    }
}
