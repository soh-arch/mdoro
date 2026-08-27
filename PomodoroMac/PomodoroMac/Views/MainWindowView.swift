import SwiftUI
import MdoroCore

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
            // REQ-SEC-004: 接続要求の確認。タイマーの操作より前に出す。
            if let requester = model.pendingConnectionRequest {
                ConnectionRequestBanner(deviceName: requester)
            }

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
        VStack(alignment: .leading, spacing: 6) {
            // REQ-UIX-045: 無効にした操作には、無効である理由を示す。
            // ツールチップは「気づいた人にしか届かない」ので、画面に出す。
            controlRow(state)
            if let reason = extendDisabledReason {
                Text(reason).font(.caption).foregroundStyle(theme.textTertiary)
            }
        }
        // REQ-UIX-044: ボタンの色は役割名から引く。OS の既定に委ねない。
        .buttonStyle(.bordered)
        .tint(theme.color(.accentPrimary, .text))
    }

    // REQ-TIM-046: 受付ウィンドウ（残り5分〜終了後1分）の外では押せない。
    private var extendDisabledReason: String? {
        guard model.timer.sessionType == .work, model.timer.runState != .idle else { return nil }
        guard !TimerEngine.isWithinExtensionWindow(model.timer, now: now) else { return nil }
        return "Extending opens in the last 5 minutes"
    }

    @ViewBuilder
    private func controlRow(_ state: RunState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .idle:
                Button("Start Focus") { model.send(.startWork(presetId: preset.id, taskSnapshot: model.tasks.selectedTaskSnapshot)) }
                    .buttonStyle(.borderedProminent)
                Button("Start Break") { model.send(.startBreak(type: model.timer.nextSessionType == .work ? .shortBreak : model.timer.nextSessionType, presetId: preset.id)) }
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
        // **ボタンの文字を折り返させない。**
        .lineLimit(1)
    }

    // REQ-TIM-044: 休憩に延長はない。
    // REQ-TIM-046: 受付ウィンドウ外はボタンを無効化する（押しても extendWindowClosed になるため）。
    @ViewBuilder
    private var extendButton: some View {
        if model.timer.sessionType == .work {
            Button("Extend +\(preset.extendSeconds / 60)m") { model.send(.extend) }
                .disabled(!TimerEngine.isWithinExtensionWindow(model.timer, now: now))
                .help("You can extend from 5 minutes before the end until 1 minute after")
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
                Text("\(model.pendingLogCount) not yet written")
                    .foregroundStyle(theme.color(.warning, .text))
            }
            if let at = model.lastLogWriteAt {
                Divider().frame(height: 12)
                Text("Last written \(at.formatted(date: .omitted, time: .standard))")
            }
            if model.logWriteFailed {
                Divider().frame(height: 12)
                Label(model.lastLogError ?? "The session log is not being written", systemImage: "exclamationmark.triangle")
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
                    Button("Resume it") { model.send(.confirmRestoredSession(.continueSession)) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Record as completed") { model.send(.confirmRestoredSession(.complete)) }
                Button("Record as stopped") { model.send(.confirmRestoredSession(.discard)) }
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
        pending.reason == .restoredAfterEnd ? "The session had already ended" : "A long pause was detected"
    }

    private var detail: String {
        let minutes = pending.elapsedSeconds / 60
        let time = pending.endedAt.formatted(date: .abbreviated, time: .shortened)
        return pending.reason == .restoredAfterEnd
            ? "It ended at \(time) (actual \(minutes) min). Record it as completed?"
            : "It has been paused since \(time) (actual \(minutes) min)."
    }
}
