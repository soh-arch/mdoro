import SwiftUI
import MdoroCore

// REQ-UIX-030 / 032 / 035 / REQ-COL-022: the label in the menu bar.
// **No accent colour** (REQ-COL-022) — not because colour is unusable. The clause rests on
// two things: a template image holds on a ground that varies, and the state must not ride on
// colour alone. Facts: docs/PLATFORM.md.
// The state is shown by shape (a template image) and by text.
struct MenuBarLabelView: View {
    let model: AppModel

    // The model moves the clock on.
    private var now: Date { model.displayNow }

    var body: some View {
        HStack(spacing: 4) {
            // REQ-UIX-035 / Decision 0031: what the mark shows is the **run state**, not the connection state.
            Image(MenuBarMark.mark(for: model.timer.runState).assetName)
            if let text {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var text: String? {
        guard model.settings.menuBarDisplayMode != .iconOnly else { return nil }
        let clock = model.timer.runState == .idle ? "--:--" : Format.clock(model.remainingSeconds(at: now))

        switch model.settings.menuBarDisplayMode {
        case .iconOnly:
            return nil
        case .timeOnly:
            return clock
        case .timeAndType:
            return "\(clock) \(Format.sessionLabel(model.timer.sessionType))"
        case .timeAndTask:
            guard let task = model.tasks.selectedTaskSnapshot, !task.isEmpty else { return clock }
            return "\(clock) \(task.prefix(20))"
        }
    }

    // REQ-UIX-038: English only. What is read out says as much about the run state as the mark's shape does.
    private var accessibilityLabel: String {
        let remaining = Format.spokenRemaining(model.remainingSeconds(at: now))
        var parts = [Format.sessionLabel(model.timer.sessionType),
                     Format.runStateLabel(model.timer.runState),
                     remaining]
        // REQ-UIX-004 (v2.25): spoken as well as shown — nothing paired, no connection state.
        if model.showsConnectionState {
            parts.append(Format.connectionLabel(model.connection))
        }
        return parts.joined(separator: ", ")
    }
}

// REQ-UIX-031 / Decision 0029: **the levels are split by how dangerous the action is.**
//
// Top level        … actions that can be taken back
// One confirmation … abort and reset the loop count (destructive)
// Submenu          … part of the settings (only choosing)
// Not here         … editing a preset, changing a path, pairing (irreversible, or touching the
//                    outside world)
struct MenuBarMenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var preset: Preset { model.presets.activePreset ?? Preset.standard() }
    private var isLive: Bool { model.timer.runState == .running || model.timer.runState == .paused }

    var body: some View {
        // --- top level ---
        switch model.timer.runState {
        case .running:
            Button("Pause") { model.send(.pause) }
        case .paused:
            Button("Resume") { model.send(.resume) }
        case .idle, .finished:
            Button(nextSessionTitle) { model.startNextSession() }
        case .pendingDecision:
            // REQ-UIX-036 / REQ-PER-005: the confirming is done in the main window.
            Text("A decision is needed")
            Button("Open the main window") { openMain() }
        }

        if isLive {
            // REQ-TIM-030 (4.6): `startWork` / `startBreak` are refused while RUNNING / PAUSED,
            // so `Start Next` does not appear here — a button whose command is always refused is
            // a dead button. Moving on from a live session is `skip`'s job, and it costs nothing
            // that cannot be started again (REQ-TIM-020: no loop count is added).
            Button("Skip") { model.send(.skip) }
        }

        Divider()

        // REQ-UIX-007: with two presets or more, another one must be reachable within two taps,
        // so the switcher is here. **The clause that governs the other side is REQ-PRS-013**:
        // with only one preset, no switch list is shown, and the switching UI becomes the way
        // through to adding one. That way through lives in `PresetBarView` in the main window,
        // which is why nothing takes its place here.
        if model.presets.presets.count >= 2 {
            Menu("Preset") {
                ForEach(model.presets.presets) { candidate in
                    Button {
                        model.send(.selectPreset(id: candidate.id))
                    } label: {
                        Text(presetMenuTitle(candidate))
                    }
                }
            }
        }
        taskMenu
        displayMenu

        Divider()

        // --- one confirmation in between ---
        // **A slip of the finger does not set it running.**
        if isLive || model.timer.runState == .finished {
            Menu("Stop…") {
                Button("Confirm stop") { model.send(.abort) }
            }
        }
        if model.timer.loopCount > 0 {
            Menu("Reset loop count…") {
                Button("Confirm reset") { model.send(.resetLoopCount) }
            }
        }

        Divider()

        stateNotices

        // REQ-UIX-004 / Decision 0031: on the Mac the connection state is here and in the status line,
        // nowhere else. **One line, to read only** — and only while a pairing exists (v2.25).
        if model.showsConnectionState {
            Text("iPhone: \(Format.connectionLabel(model.connection))")
        }
        SettingsLink { Text("Settings…") }
        Button("Open Main Window") { openMain() }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    // REQ-ERR-017 / REQ-UIX-031 / Decision 0037: **the menu is the last place a message can reach.**
    // Mdoro sits in the menu bar and runs with the main window shut, so the bands in that window
    // never arrive for someone who does not open it.
    //
    // **Only what cannot be taken back goes here.** A state that could not be restored is already
    // lost, and a save that has stopped is losing more with every session. No report of success, no
    // progress, no statistics (Decision 0037), and it sits below the actions so that nobody looking
    // for a control has to read past it (Decision 0029).
    //
    // **The sentence, the set-aside path and the way to dismiss stay in the window.** The path is
    // reading matter, and it is the only pointer back to the file (Decision 0036) — a dismissal
    // offered here would let it be cleared by someone who was never shown it. So the notice states
    // what happened and opens the place that holds the rest.
    @ViewBuilder
    private var stateNotices: some View {
        // REQ-ERR-017: a failed restore is shown once per launch. This line stands until the band in
        // the window is dismissed, which clears both.
        if model.stateRestoreProblem != nil {
            Button("The previous state could not be restored…") { openMain() }
        }
        // REQ-ERR-017: a failed save is shown **until it resolves**, so this line stands as long as
        // the condition does. It is the graver of the two: work done from here on is not being kept.
        if model.stateSaveProblem != nil {
            Button("Mdoro is not saving its state…") { openMain() }
        }
        // REQ-CFG-018 / 9.3: a setting the saved file held outside its range has been put back to
        // its default. **It belongs here by the same test as the two above: it cannot be taken
        // back.** The value the reader chose is gone from the file — `AppModel.init` saves the
        // repaired record over it — so a reader who never opens the main window would have nothing
        // anywhere to learn it from. Which settings, and the way to dismiss, stay in the window.
        if !model.settingsResetAtLaunch.isEmpty {
            Button("Some saved settings were put back to their defaults…") { openMain() }
        }
    }

    // **Only choosing; nothing here touches the outside world.**
    private var displayMenu: some View {
        Menu("Display") {
            Picker("Appearance", selection: Binding(
                get: { model.settings.appearance },
                set: { model.settings.appearance = $0 }
            )) {
                Text("System").tag(AppearancePreference.system)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
            Picker("Menu bar", selection: Binding(
                get: { model.settings.menuBarDisplayMode },
                set: { model.settings.menuBarDisplayMode = $0 }
            )) {
                Text("Time and type").tag(MenuBarDisplayMode.timeAndType)
                Text("Time and task").tag(MenuBarDisplayMode.timeAndTask)
                Text("Time only").tag(MenuBarDisplayMode.timeOnly)
                Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
            }
        }
    }

    // REQ-TSK-004: a task must be choosable from either screen. **A long list is cut short.**
    @ViewBuilder
    private var taskMenu: some View {
        let sections = model.tasks.grouped(showCompleted: model.settings.showCompletedTasks)
        if !sections.isEmpty {
            Menu("Task") {
                ForEach(sections) { section in
                    Menu(section.name) {
                        ForEach(section.items.prefix(Self.taskMenuLimit)) { item in
                            Button {
                                model.selectTask(id: item.stableId)
                            } label: {
                                Text(item.displayText
                                     + (item.stableId == model.tasks.selectedTaskId ? " ✓" : ""))
                            }
                        }
                        if section.items.count > Self.taskMenuLimit {
                            Divider()
                            Text("More in the main window")
                        }
                    }
                }
                // **Clearing the selection goes at the very bottom.** Higher up, it gets pressed by
                // someone meaning to choose a task.
                if model.tasks.selectedTaskId != nil {
                    Divider()
                    Button("Clear selection") { model.clearTaskSelection() }
                }
            }
        }
    }

    private static let taskMenuLimit = 20

    // REQ-UIX-008: the shape of the times is written alongside.
    // **The wording is looked up before anything is joined on.** Pass a String to `Text` and it
    // resolves to the verbatim initialiser and is not extracted (Decision 0022). The ✓ mark is not a
    // word, so it may be appended as it is.
    private func presetMenuTitle(_ candidate: Preset) -> String {
        let shaped = String(localized: "\(candidate.name) (\(Format.presetShape(candidate)))")
        return candidate.id == preset.id ? shaped + " ✓" : shaped
    }

    private var nextSessionTitle: String {
        String(localized: "Start Next (\(Format.sessionLabel(model.timer.nextSessionType)))")
    }

    private func openMain() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: MdoroMacApp.mainWindowId)
    }
}
