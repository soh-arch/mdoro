import SwiftUI
import MdoroCore

// REQ-UIX-010–014 / Decision 0005: the focus view.
// The aim is **to cut what enters the field of view to the barest minimum**, so do not add secondary information.
struct FocusView: View {
    @Environment(ClientModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // REQ-UIX-014: shifted by ±8pt every 5 minutes to guard against burn-in.
    @State private var drift: CGSize = .zero
    // The hint on how to go back. **It is not shown all the time.**
    @State private var isExitHintVisible = false
    @State private var hintTimer: Task<Void, Never>?
    @State private var driftTimer: Task<Void, Never>?

    private let theme = Theme(focusView: true)

    private var timer: TimerContext { model.snapshot?.timer ?? .idle(now: Date()) }
    private var preset: Preset { model.snapshot?.presets.activePreset ?? Preset.standard() }

    var body: some View {
        GeometryReader { geometry in
            // REQ-UIX-010: the remaining time has a character height of at least 40% of the screen's short edge.
            let shortEdge = min(geometry.size.width, geometry.size.height)
            let timeHeight = shortEdge * 0.40
            // The secondary information is at most 1/4 of the remaining time (= the remaining time is
            // at least four times the secondary information).
            let secondaryHeight = timeHeight / 4

            ZStack {
                theme.background.ignoresSafeArea()

                // **Set the four blocks apart.** A fixed gap crowds them in one orientation or the
                // other. Let Spacer share it out.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    secondary(height: secondaryHeight)
                    Spacer(minLength: 0)

                    // REQ-UIX-040: the digits are SF Rounded / medium / monospaced.
                    Text(Format.clock(model.remainingSeconds()))
                        .font(.system(size: timeHeight, weight: .medium, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityLabel(Format.spokenRemaining(model.remainingSeconds()))

                    // REQ-COL-031 / 013: the session type's colour goes on **the progress indicator and the type label, not the digits**.
                    progressBar(width: min(geometry.size.width * 0.72, 520))
                    Spacer(minLength: 0)
                    controls(height: secondaryHeight)
                    Spacer(minLength: 0)
                    // REQ-UIX-011: the only way back is a double tap.
                    exitHint(height: secondaryHeight)
                }
                .offset(drift)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            }
            .contentShape(Rectangle())
            // REQ-UIX-011: going back to the main screen is an explicit action. **The double tap is matched first.**
            .onTapGesture(count: 2) { dismiss() }
            // A single tap and a swipe are both taken as a sign of trying to go back.
            .onTapGesture { showExitHint() }
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { _ in showExitHint() })
        }
        .statusBarHidden()
        // REQ-COL-030: always the dark palette. Without matching the vessel too, only the standard controls stay light.
        .preferredColorScheme(.dark)
        .onAppear {
            // REQ-UIX-012: the automatic screen lock is held off.
            UIApplication.shared.isIdleTimerDisabled = true
            startDrift()
        }
        .onDisappear {
            // **Always release it.** Left on, the screen never goes dark again.
            UIApplication.shared.isIdleTimerDisabled = false
            driftTimer?.cancel()
            driftTimer = nil
            hintTimer?.cancel()
            hintTimer = nil
        }
    }

    // REQ-COL-013: the type is told apart by **stroke style** as well as colour (Focus solid / Short thin solid / Long double).
    // It is a bar rather than a ring because a ring wide enough to circle REQ-UIX-010's digits does not
    // fit the short edge in landscape.
    @ViewBuilder
    private func progressBar(width: CGFloat) -> some View {
        let role = timer.sessionType.colorRole
        let style = timer.sessionType.progressRingStyle
        let thickness: CGFloat = style == .thin ? 3 : 6
        VStack(spacing: 3) {
            bar(width: width, height: thickness, role: role)
            // The double line is for the long break only.
            if style == .double { bar(width: width, height: 2, role: role) }
        }
        .opacity(timer.runState == .idle ? 0 : 1)
    }

    private func bar(width: CGFloat, height: CGFloat, role: ColorRole) -> some View {
        ZStack(alignment: .leading) {
            // **The track takes a neutral colour.** Under REQ-COL-011, passing `-line` trips a precondition and crashes.
            Capsule().fill(theme.borderSubtle)
            Capsule()
                .fill(theme.color(role, .graphic))
                .frame(width: width * progress)
        }
        .frame(width: width, height: height)
    }

    // The share elapsed. **Worked out from the remaining time.** The Mac is the source of truth for progress.
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
        // REQ-UIX-046: **do not use a coloured ground.** This is a hint, not a warning.
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

    // REQ-UIX-010: the secondary information is the session type, the task name, the loop count and the connection state, and nothing else.
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
                // REQ-COM-012: even at 00:00 it is not treated as complete.
                Text("Waiting for sync")
                    .font(.system(size: height * 0.7))
                    .foregroundStyle(theme.color(.warning, .text))
            }
        }
    }

    // REQ-UIX-011: the controls are narrowed to "pause / resume" and "extend".
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
            // REQ-TIM-040: a break cannot be extended, so it is hidden outside WORK.
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

    // REQ-UIX-014: shifted within a ±8pt range every 5 minutes.
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
