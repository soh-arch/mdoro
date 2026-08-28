import SwiftUI
import MdoroCore

// REQ-UIX-010〜014 / Decision 0005: 集中表示ビュー。
// **視界に入る情報を極限まで減らす**のが目的なので、副次情報を足さないこと。
struct FocusView: View {
    @Environment(ClientModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // REQ-UIX-014: 焼き付き防止のため 5 分ごとに ±8pt 平行移動させる。
    @State private var drift: CGSize = .zero
    // 戻り方の案内。**常時は出さない。**
    @State private var isExitHintVisible = false
    @State private var hintTimer: Task<Void, Never>?
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

                // **3つの塊を離して置く。** 固定の間隔だと向きによって詰まる。Spacer に配らせる。
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    secondary(height: secondaryHeight)
                    Spacer(minLength: 0)

                    // REQ-UIX-040: 数字は SF Rounded / medium / 等幅。
                    Text(Format.clock(model.remainingSeconds()))
                        .font(.system(size: timeHeight, weight: .medium, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityLabel(Format.spokenRemaining(model.remainingSeconds()))

                    // REQ-COL-031 / 013: セッション種別の色は**数字ではなく進行インジケータと種別ラベル**に当てる。
                    progressBar(width: min(geometry.size.width * 0.72, 520))
                    Spacer(minLength: 0)
                    controls(height: secondaryHeight)
                    Spacer(minLength: 0)
                    // REQ-UIX-011: 戻り方はダブルタップだけ。
                    exitHint(height: secondaryHeight)
                }
                .offset(drift)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            }
            .contentShape(Rectangle())
            // REQ-UIX-011: 通常画面へ戻るのは明示操作。**ダブルタップが先に判定される。**
            .onTapGesture(count: 2) { dismiss() }
            // 1回叩いた・払った、どちらも「戻ろうとした」合図とみなす。
            .onTapGesture { showExitHint() }
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { _ in showExitHint() })
        }
        .statusBarHidden()
        // REQ-COL-030: 常にダークのパレット。器も揃えないと標準コントロールだけ明るく残る。
        .preferredColorScheme(.dark)
        .onAppear {
            // REQ-UIX-012: 自動画面ロックを抑止する。
            UIApplication.shared.isIdleTimerDisabled = true
            startDrift()
        }
        .onDisappear {
            // **必ず解除する。** 付けっぱなしだと画面が永久に消えない。
            UIApplication.shared.isIdleTimerDisabled = false
            driftTimer?.cancel()
            driftTimer = nil
            hintTimer?.cancel()
            hintTimer = nil
        }
    }

    // REQ-COL-013: 色に加えて**線種**でも種別を分ける（Focus 実線 / Short 細実線 / Long 二重）。
    // リングではなくバーなのは、REQ-UIX-010 の数字を囲めるリングが横向きで短辺に収まらないため。
    @ViewBuilder
    private func progressBar(width: CGFloat) -> some View {
        let role = timer.sessionType.colorRole
        let style = timer.sessionType.progressRingStyle
        let thickness: CGFloat = style == .thin ? 3 : 6
        VStack(spacing: 3) {
            bar(width: width, height: thickness, role: role)
            // 二重線は長い休憩だけ。
            if style == .double { bar(width: width, height: 2, role: role) }
        }
        .opacity(timer.runState == .idle ? 0 : 1)
    }

    private func bar(width: CGFloat, height: CGFloat, role: ColorRole) -> some View {
        ZStack(alignment: .leading) {
            // **軌道は中立の色にする。** REQ-COL-011 により `-line` を渡すと precondition で落ちる。
            Capsule().fill(theme.borderSubtle)
            Capsule()
                .fill(theme.color(role, .graphic))
                .frame(width: width * progress)
        }
        .frame(width: width, height: height)
    }

    // 経過の割合。**残り時間から出す。** 進行の正本は Mac にある。
    private var progress: CGFloat {
        let total: Int
        switch timer.sessionType {
        case .work: total = preset.workSeconds
        case .shortBreak: total = preset.shortBreakSeconds
        case .longBreak: total = preset.longBreakSeconds
        }
        guard total > 0 else { return 0 }
        let elapsed = Double(total - model.remainingSeconds()) / Double(total)
        return CGFloat(min(max(elapsed, 0), 1))
    }

    @ViewBuilder
    private func exitHint(height: CGFloat) -> some View {
        // REQ-UIX-046: **色を帯びた地は使わない。** これは注意ではなく案内である。
        Text("Double-tap to go back")
            .font(.system(size: height * 0.7))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
            .opacity(isExitHintVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isExitHintVisible)
    }

    private func showExitHint() {
        isExitHintVisible = true
        hintTimer?.cancel()
        hintTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isExitHintVisible = false
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
                Image(systemName: model.connectionStatus.peerSymbolName)
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
                Text("Waiting for sync")
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
                Button("Pause") { model.send(.pause) }
            case .paused:
                Button("Resume") { model.send(.resume) }
            default:
                EmptyView()
            }
            // REQ-TIM-040: 休憩に延長はないので WORK 以外では非表示。
            if timer.sessionType == .work {
                Button("+\(preset.extendSeconds / 60) min") { model.send(.extend) }
                    .accessibilityLabel("Extend by \(preset.extendSeconds / 60) minutes")
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
