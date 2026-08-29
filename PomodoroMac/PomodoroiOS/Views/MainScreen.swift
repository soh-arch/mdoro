import SwiftUI
import MdoroCore

// REQ-UIX-001: the iPhone's main screen offers every feature (settings, choosing a task, working the timer).
struct MainScreen: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(ClientModel.self) private var model
    @State private var isAppearancePresented = false

    // Decision 0027: the appearance follows **this device's setting**, not the Mac's.
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
            // REQ-ERR-016 / Decision 0035: a refusal goes **where it is noticed right after the action**.
            // With a banner set into the body, a refusal pressed after scrolling down to the task
            // list ends up off the screen.
            // Laid over the bottom edge, within reach, it is seen wherever the eye is.
            .overlay(alignment: .bottom) {
                if let refusal = model.lastRefusal {
                    RefusalNotice(code: refusal)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.lastRefusal)
            .navigationTitle("Mdoro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAppearancePresented = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                // iOS 26 gathers adjacent toolbar items into one frame. **The roles differ, so they are kept apart.**
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    // REQ-UIX-013: an explicit action from the main screen leads to the focus view.
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
        // REQ-COL-003: fixing to light or to dark has to reach the vessel as well.
        // Without that, the ground and the text come from our own palette while the navigation bar
        // follows the OS's appearance, and the two disagree.
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
            // REQ-COM-012: reaching 00:00 does not settle it as complete. It is shown as "waiting for sync".
            if model.isAwaitingSync {
                Text("Waiting for sync")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // REQ-COM-013: while disconnected, the controls are disabled.
    // REQ-UIX-044: the colour of a button is looked up by role name. **Left to the OS default, enabled
    // and disabled end up looking the same.**
    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Decision 0028: REQ-UIX-045 is for the Mac only. **Do not fill the iPhone's screen with explanations.**
            // The reason a button cannot be pressed is held by the Mac's settings screen and by the spoken label.
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
        // **Do not let the text on a button wrap.**
        .lineLimit(1)
        .disabled(!model.isConnected)
    }

    // REQ-TIM-044: a break cannot be extended. REQ-TIM-046: outside the window that accepts it, disabled.
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

    // REQ-UIX-007 / 008: the active preset's name is shown at all times, and with two or more it is
    // switched in two taps or fewer.
    @ViewBuilder
    private var presetRow: some View {
        let presets = model.snapshot?.presets.presets ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Preset").font(.footnote).foregroundStyle(theme.textTertiary)
                if presets.count >= 2 {
                    Menu("\(preset.name) (\(Format.presetShape(preset)))") {
                        ForEach(presets) { candidate in
                            Button("\(candidate.name) (\(Format.presetShape(candidate)))") {
                                model.send(.selectPreset, params: CommandParams(presetId: candidate.id))
                            }
                        }
                    }
                    .disabled(!model.isConnected)
                } else {
                    // REQ-PRS-013: with one, no switching UI is shown. Adding is done on the Mac.
                    Text("\(preset.name) (\(Format.presetShape(preset)))")
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()
            }
            .font(.callout)

        }
    }
}

// REQ-ERR-016 / Decision 0035: the iPhone says in its own words which action the Mac did not accept.
//
// **The wording is looked up from `code`.** The `message` that came with it is for diagnosis (10.2),
// and the sender does not decide the wording on the other screen.
struct RefusalNotice: View {
    @Environment(\.theme) private var theme
    @Environment(ClientModel.self) private var model
    let code: ProtocolErrorCode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(code.displayMessage)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { model.acknowledgeRefusal() }
                .buttonStyle(.plain)
                .foregroundStyle(theme.color(.accentPrimary, .text))
        }
        .font(.footnote)
        .foregroundStyle(theme.color(.warning, .text))
        .padding(12)
        // REQ-UIX-046: a banner (a -subtle ground inside a -line border) is for a state that needs
        // attention, not for warning alone. REQ-COL-011 keeps session states out of it.
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// REQ-UIX-002 / 003: the type is shown by both colour and wording, and the loop as n / interval.
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

// This device's settings. **Not the Mac's settings.**
// Only the appearance (Decision 0027) and unpairing go here.
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
                    // **Do not show the label row.** With it, there look to be four items to choose from.
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

                // decisions/0021: exactly one support link, here. The same order as the Mac's About (REQ-UIX-047).
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
                    // Show where the link goes before it opens. REQ-COL-002: paint the label ourselves and make it a plain button.
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
