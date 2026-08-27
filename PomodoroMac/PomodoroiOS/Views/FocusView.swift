import SwiftUI
import PomodoroCore

// REQ-UIX-010〜014: 集中表示ビュー。
//
// v1.0 の「StandBy モード」を実現可能な形に置き換えたもの（Decision 0005）。
// **視界に入る情報を極限まで減らす**のが目的なので、副次情報を足さないこと。
struct FocusView: View {
    @Environment(ClientModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // REQ-UIX-014: 焼き付き防止のため 5 分ごとに ±8pt 平行移動させる。
    @State private var drift: CGSize = .zero
    @State private var driftTimer: Task<Void, Never>?

    private let theme = Theme(focusView: true)

    private var timer: TimerContext { model.snapshot?.timer ?? .idle(now: Date()) }
    private var preset: Preset { model.snapshot?.presets.activePreset ?? Preset.standard() }

    var body: some View {
        GeometryReader { geometry in
            // REQ-UIX-010: 残り時間は画面短辺の 40% 以上の文字高。
            let shortEdge = min(geometry.size.width, geometry.size.height)
            let timeHeight = shortEdge * 0.40
            // 副次情報は残り時間の 1/4 以下（＝残り時間が副次情報の4倍以上）。
            let secondaryHeight = timeHeight / 4

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: secondaryHeight * 0.4) {
                    secondary(height: secondaryHeight)

                    Text(Format.clock(model.remainingSeconds()))
                        // OPEN-002 待ち: 書体は Mac のメインウィンドウと同じ指定を使っている。
                        .font(.system(size: timeHeight, weight: .medium, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityLabel(Format.spokenRemaining(model.remainingSeconds()))

                    controls(height: secondaryHeight)
                }
                .offset(drift)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            // REQ-UIX-011: 通常画面へ戻るのは明示操作。
            .onTapGesture(count: 2) { dismiss() }
        }
        .statusBarHidden()
        .onAppear {
            // REQ-UIX-012: 自動画面ロックを抑止する。
            UIApplication.shared.isIdleTimerDisabled = true
            startDrift()
        }
        .onDisappear {
            // **必ず解除する。** 付けっぱなしにすると画面が永久に消えなくなる。
            UIApplication.shared.isIdleTimerDisabled = false
            driftTimer?.cancel()
            driftTimer = nil
        }
    }

    // REQ-UIX-010: 副次情報はセッション種別・タスク名・周回数・接続状態のみ。
    private func secondary(height: CGFloat) -> some View {
        VStack(spacing: height * 0.2) {
            HStack(spacing: 8) {
                Text(Format.sessionLabel(timer.sessionType))
                    .foregroundStyle(theme.color(timer.sessionType.colorRole, .text))
                Text("\(timer.displayLoop(longBreakInterval: preset.longBreakInterval)) / \(preset.longBreakInterval)")
                    .foregroundStyle(theme.textSecondary)
                Image(systemName: model.connectionStatus.symbolName)
                    .foregroundStyle(theme.color(model.connectionStatus.colorRole, .text))
            }
            .font(.system(size: height, weight: .medium))

            if let task = model.snapshot?.task.selectedTaskSnapshot, !task.isEmpty {
                Text(task)
                    .font(.system(size: height * 0.8))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            if model.isAwaitingSync {
                // REQ-COM-012: 00:00 でも完了扱いにしない。
                Text("同期待ち")
                    .font(.system(size: height * 0.7))
                    .foregroundStyle(theme.color(.warning, .text))
            }
        }
    }

    // REQ-UIX-011: 操作は「一時停止 / 再開」と「延長」に絞る。
    private func controls(height: CGFloat) -> some View {
        HStack(spacing: 24) {
            switch timer.runState {
            case .running:
                Button("一時停止") { model.send(.pause) }
            case .paused:
                Button("再開") { model.send(.resume) }
            default:
                EmptyView()
            }
            // 延長は WORK 以外では非表示（REQ-TIM-040 により休憩に延長はない）。
            if timer.sessionType == .work {
                Button("延長 +\(preset.extendSeconds / 60)分") { model.send(.extend) }
                    .disabled(!TimerEngine.isWithinExtensionWindow(timer, now: model.displayNow))
            }
        }
        .font(.system(size: height * 0.8))
        .buttonStyle(.bordered)
        .tint(theme.color(.accentPrimary, .text))
        .disabled(!model.isConnected)
    }

    // REQ-UIX-014: 5 分ごとに ±8pt の範囲で平行移動させる。
    private func startDrift() {
        driftTimer?.cancel()
        driftTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 2)) {
                        drift = CGSize(width: .random(in: -8...8), height: .random(in: -8...8))
                    }
                }
            }
        }
    }
}
