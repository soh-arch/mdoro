import SwiftUI
import PomodoroCore

// REQ-UIX-001: メインウィンドウでは全機能（設定、タスク選択、タイマー操作）を提供する。
struct MainWindowView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(AppModel.self) private var model

    // 時計はモデルが進める。ビュー側の Timer は発火せず表示が固まった。
    private var now: Date { model.displayNow }

    private var theme: Theme { Theme(appearance: model.settings.appearance, systemScheme: systemScheme) }
    private var preset: Preset { model.presets.activePreset ?? Preset.standard() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // REQ-UIX-036: PENDING_DECISION の確認 UI。ほかの操作より前に出す。
            if model.timer.runState == .pendingDecision, let pending = model.timer.pendingDecision {
                PendingDecisionView(pending: pending)
            }

            SessionHeaderView(
                sessionType: model.timer.sessionType,
                runState: model.timer.runState,
                loopDisplay: model.timer.displayLoop(longBreakInterval: preset.longBreakInterval),
                longBreakInterval: preset.longBreakInterval
            )

            timerReadout
            controls
            PresetBarView()
            Divider().overlay(theme.borderSubtle)
            TaskListView()
            Spacer(minLength: 0)
            statusBar
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 560)
        .background(theme.background)
        .environment(\.theme, theme)
        // REQ-COL-003: 設定でライト固定・ダーク固定も選べる。
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // REQ-UIX-006: 残り時間は VoiceOver で「残り12分30秒」のように読み上げる。
    private var timerReadout: some View {
        let remaining = model.remainingSeconds(at: now)
        return Text(Format.clock(remaining))
            .font(.system(size: 64, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(theme.textPrimary)
            .accessibilityLabel(Format.spokenRemaining(remaining))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var controls: some View {
        let state = model.timer.runState
        HStack(spacing: 10) {
            switch state {
            case .idle:
                Button("Focus を開始") { model.send(.startWork(presetId: preset.id, taskSnapshot: model.tasks.selectedTaskSnapshot)) }
                    .buttonStyle(.borderedProminent)
                Button("休憩を開始") { model.send(.startBreak(type: model.timer.nextSessionType == .work ? .shortBreak : model.timer.nextSessionType, presetId: preset.id)) }
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
    }

    // REQ-TIM-044: 休憩に延長はない。
    // REQ-TIM-046: 受付ウィンドウ外はボタンを無効化する（押しても extendWindowClosed になるため）。
    @ViewBuilder
    private var extendButton: some View {
        if model.timer.sessionType == .work {
            Button("延長 +\(preset.extendSeconds / 60)分") { model.send(.extend) }
                .disabled(!TimerEngine.isWithinExtensionWindow(model.timer, now: now))
                .help("延長できるのは終了5分前から終了1分後までです")
        }
    }

    private func startNext() {
        let next = model.timer.nextSessionType
        if next == .work {
            model.send(.startWork(presetId: preset.id, taskSnapshot: model.tasks.selectedTaskSnapshot))
        } else {
            model.send(.startBreak(type: next, presetId: preset.id))
        }
    }

    // REQ-UIX-004: 接続状態を常時視認できること。
    private var statusBar: some View {
        HStack(spacing: 8) {
            let status = model.connection
            Image(systemName: status.symbolName)
            Text(status.label)
            if model.pendingLogCount > 0 {
                Divider().frame(height: 12)
                Text("未書き込み \(model.pendingLogCount) 件")
                    .foregroundStyle(theme.color(.warning, .text))
            }
            if let at = model.lastLogWriteAt {
                Divider().frame(height: 12)
                Text("最終書き込み \(at.formatted(date: .omitted, time: .standard))")
            }
            if model.logWriteFailed {
                Divider().frame(height: 12)
                Label(model.lastLogError ?? "ログを書き込めていません", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(theme.color(.warning, .text))
                    .textSelection(.enabled)
                    .help(model.lastLogError ?? "")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(theme.textSecondary)
    }
}

// REQ-UIX-036 / REQ-PER-003(d) / REQ-PER-005: 不在中に終わっていたセッションの確認。
struct PendingDecisionView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let pending: PendingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "questionmark.circle")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text(detail)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 10) {
                if pending.reason == .pausedTooLong {
                    Button("再開する") { model.send(.confirmRestoredSession(.continueSession)) }
                        .buttonStyle(.borderedProminent)
                }
                Button("完了として記録") { model.send(.confirmRestoredSession(.complete)) }
                Button("中断として記録") { model.send(.confirmRestoredSession(.discard)) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // REQ-COL-011: バナー表現（-subtle の地に -line の枠）は warning に予約されている。
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        pending.reason == .restoredAfterEnd ? "セッションは終了していました" : "長時間の一時停止を検出しました"
    }

    private var detail: String {
        let minutes = pending.elapsedSeconds / 60
        let time = pending.endedAt.formatted(date: .abbreviated, time: .shortened)
        return pending.reason == .restoredAfterEnd
            ? "\(time) に終了しています（実経過 \(minutes) 分）。完了として記録しますか？"
            : "\(time) から停止したままです（実経過 \(minutes) 分）。"
    }
}
