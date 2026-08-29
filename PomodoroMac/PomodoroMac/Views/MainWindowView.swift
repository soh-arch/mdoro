import SwiftUI
import MdoroCore

// REQ-UIX-001: the main window offers every feature (settings, choosing a task, working the timer).
struct MainWindowView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(AppModel.self) private var model

    // The model moves the clock on. A Timer on the view side does not fire.
    private var now: Date { model.displayNow }

    private var theme: Theme { Theme(appearance: model.settings.appearance, systemScheme: systemScheme) }
    private var preset: Preset { model.presets.activePreset ?? Preset.standard() }

    var body: some View {
        // **When the content is taller than the window, SwiftUI quietly cuts off the top.**
        // The part that grows and shrinks goes in a scroll view, and the status display is pinned below.
        VStack(spacing: 0) {
            ScrollView { content }
            Divider().overlay(theme.borderSubtle)
            statusBar
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 460, minHeight: 560)
        .background(theme.background)
        .environment(\.theme, theme)
        // REQ-COL-003: the settings also allow fixing it to light or to dark.
        .preferredColorScheme(preferredScheme)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            // REQ-ERR-017 / Decision 0035: a failed restore is shown once at launch.
            // **Losing the session and the presets is not something to keep quiet about.**
            if let problem = model.stateRestoreProblem {
                StateRestoreBanner(message: problem, setAsidePath: model.stateSetAsidePath)
            }

            // REQ-SEC-004: confirming a connection request. It comes before the timer controls.
            if let requester = model.pendingConnectionRequest {
                ConnectionRequestBanner(deviceName: requester)
            }

            // REQ-UIX-036: the confirmation UI for PENDING_DECISION. It comes before the other controls.
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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // REQ-UIX-006: VoiceOver reads the remaining time out as "12 minutes 30 seconds left" and the like.
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
        VStack(alignment: .leading, spacing: 8) {
            // REQ-UIX-045: a disabled control says why. It goes on the screen, not in a tooltip.
            controlRow(state)
            if let reason = extendDisabledReason {
                Text(reason).font(.caption).foregroundStyle(theme.textTertiary)
            }
        }
        // REQ-UIX-044: the colour of a button is looked up by role name. It is not left to the OS default.
        .buttonStyle(.bordered)
        .tint(theme.color(.accentPrimary, .text))
    }

    // REQ-TIM-046: outside the window that accepts it (from 5 minutes left to 1 minute after the end)
    // it cannot be pressed.
    private var extendDisabledReason: String? {
        guard model.timer.sessionType == .work, model.timer.runState != .idle else { return nil }
        guard !TimerEngine.isWithinExtensionWindow(model.timer, now: now) else { return nil }
        return String(localized: "Extending opens in the last 5 minutes")
    }

    @ViewBuilder
    private func controlRow(_ state: RunState) -> some View {
        HStack(spacing: 8) {
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
        // **Do not let the text on a button wrap.**
        .lineLimit(1)
    }

    // REQ-TIM-044: a break cannot be extended.
    // REQ-TIM-046: outside the window that accepts it the button is disabled (pressing it would only
    // come back as extendWindowClosed).
    @ViewBuilder
    private var extendButton: some View {
        if model.timer.sessionType == .work {
            // The wording may be short (the reason appears below it), but what is read out keeps the meaning.
            Button("+\(preset.extendSeconds / 60) min") { model.send(.extend) }
                .accessibilityLabel("Extend by \(preset.extendSeconds / 60) minutes")
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

    // REQ-UIX-004: the connection state must be visible at all times.
    private var statusBar: some View {
        HStack(spacing: 8) {
            let status = model.connection
            // **This is a way through to the settings.**
            SettingsLink {
                Label(Format.connectionLabel(status), systemImage: status.peerSymbolName)
                    .foregroundStyle(theme.color(status.colorRole, .text))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { model.settingsTab = .connection })
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
                Label(model.lastLogError ?? String(localized: "The session log is not being written"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(theme.color(.warning, .text))
                    .textSelection(.enabled)
                    .help(model.lastLogError ?? "")
            }
            // REQ-ERR-017 / Decision 0035: a failed save is treated the same as a failed log write.
            // **It is shown until it goes away.**
            if let problem = model.stateSaveProblem {
                Divider().frame(height: 12)
                Label(problem, systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(theme.color(.warning, .text))
                    .textSelection(.enabled)
                    // Kept to one line. **A line that grows pushes the connection state out.** The whole
                    // text stays in the help.
                    .lineLimit(1)
                    .help(problem)
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(theme.textSecondary)
    }
}

// REQ-ERR-017 / Decision 0035: a failed restore is shown exactly once at launch.
//
// **It was made a banner because the status line is the place for what stays "until resolved".** A
// failed save goes there. A failed restore has already happened and cannot wait to go away — only the
// user can say it has been read, so it stays until it is closed. It is not a sheet, because it is not
// grave enough to take the timer controls away.
struct StateRestoreBanner: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let message: String
    // REQ-ERR-017 / Decision 0036: where it was set aside. The name carries a date and time, so it is
    // shown apart from the sentence.
    let setAsidePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The previous state could not be restored", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
            // **Saying that it was set aside is not enough.** Show where it can be fetched from.
            if let setAsidePath {
                Text("Moved aside as: \(setAsidePath)")
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
            Button("Dismiss") { model.acknowledgeStateRestoreProblem() }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // REQ-COL-011: the banner treatment (a -subtle ground inside a -line border) is reserved for warning.
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// REQ-UIX-036 / REQ-PER-003(d) / REQ-PER-005: confirming a session that ended while nobody was there.
struct PendingDecisionView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let pending: PendingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "questionmark.circle")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text(detail)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
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
        // REQ-COL-011: the banner treatment (a -subtle ground inside a -line border) is reserved for warning.
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // The same two titles as `PendingDecisionCard` on the iPhone side.
    private var title: LocalizedStringKey {
        pending.reason == .restoredAfterEnd ? "The session had already ended" : "A long pause was detected"
    }

    private var detail: LocalizedStringKey {
        let minutes = pending.elapsedSeconds / 60
        let time = pending.endedAt.formatted(date: .abbreviated, time: .shortened)
        return pending.reason == .restoredAfterEnd
            ? "It ended at \(time) (actual \(minutes) min). Record it as completed?"
            : "It has been paused since \(time) (actual \(minutes) min)."
    }
}
