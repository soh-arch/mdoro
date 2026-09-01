import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MdoroCore

// REQ-UIX-031: aborting, resetting, editing a preset and changing a setting are possible only in the
// main window (and the settings screen).
// The identifier of a settings tab. The model holds it so the main window can name where to open.
enum SettingsTab: String, Hashable, CaseIterable {
    case presets, files, connection, behavior, display, about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { Theme(appearance: model.settings.appearance, systemScheme: systemScheme) }
    @State private var logFileError: String?
    @State private var diagnosticsError: String?
    // 9.3 / Decision 0040: **the name is committed once, not once per keystroke.** Every change to
    // it takes the Bonjour registration down and puts a new one up, and a name typed straight into
    // the setting would do that eleven times for "Kitchen Mac". Bound straight through, it would
    // also refuse the moment the field went empty (`isValidDisplayName`) and put the old name back
    // under the cursor.
    @State private var displayNameDraft = ""
    @FocusState private var displayNameFocused: Bool
    // REQ-CFG-013 (v2.27): a refused commit is said, not silent. Cleared by the next valid one.
    @State private var displayNameError: String?
    @State private var logFileNameDraft = ""
    @FocusState private var logFileNameFocused: Bool
    @State private var logFileNameError: String?

    var body: some View {
        @Bindable var bindable = model
        // The more often something is touched, the nearer the front it goes.
        TabView(selection: $bindable.settingsTab) {
            PresetEditorView()
                .tabItem { Label("Presets", systemImage: "timer") }.tag(SettingsTab.presets)
            filesTab(model: $bindable)
                .tabItem { Label("Files", systemImage: "folder") }.tag(SettingsTab.files)
            connectionTab
                .tabItem { Label("Connection", systemImage: "iphone.gen3") }.tag(SettingsTab.connection)
            behaviorTab(model: $bindable)
                .tabItem { Label("Behavior", systemImage: "gearshape") }.tag(SettingsTab.behavior)
            appearanceTab(model: $bindable)
                .tabItem { Label("Display", systemImage: "paintpalette") }.tag(SettingsTab.display)
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 560, height: 460)
        // The settings window is a Scene of its own, so it hands the theme out itself (REQ-COL-002).
        .environment(\.theme, theme)
        // REQ-COL-003: fixing it to light or to dark takes effect in this window too.
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Connection

    // REQ-UIX-004: the connection is not a behaviour setting, so it gets a tab of its own.
    private var connectionTab: some View {
        Form {
            // 9.3 / Decision 0040: the one name this Mac shows anyone. It is not what identifies
            // it — that is an identifier the iPhone files its pairing under and nobody sees.
            Section("This Mac") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("", text: $displayNameDraft)
                        .labelsHidden()
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                        .focused($displayNameFocused)
                        .onSubmit { commitDisplayName() }
                        .onChange(of: displayNameFocused) { _, focused in
                            if !focused { commitDisplayName() }
                        }
                        // Follows the setting while the field is not being typed in — the iPhone
                        // can change it too (REQ-CFG-002).
                        .onChange(of: model.settings.displayName, initial: true) { _, name in
                            if !displayNameFocused { displayNameDraft = name }
                        }
                }
                Text("The name your iPhone sees. It is also the name this Mac shows on your network.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                Text("Your Mac's own name is never sent. Pairing survives a rename.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                // REQ-CFG-013 (v2.27) / REQ-COL-001: the refusal, in the role every other
                // cannot-do-that line on this screen wears.
                if let displayNameError {
                    Text(displayNameError)
                        .font(.footnote)
                        .foregroundStyle(theme.color(.danger, .text))
                }
            }
            PairingSection()
        }
        .formStyle(.grouped)
    }

    // 9.3 / REQ-CFG-013 (v2.27): one character or more. An empty name has no range to round
    // into, so the commit is refused, the old name is put back — and the refusal is shown,
    // because a value must not change or come back silently. A valid commit clears the line.
    private func commitDisplayName() {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.isValidDisplayName(trimmed) else {
            displayNameDraft = model.settings.displayName
            displayNameError = String(
                localized: "A name needs at least one character. The previous name was kept."
            )
            return
        }
        displayNameDraft = trimmed
        displayNameError = nil
        guard trimmed != model.settings.displayName else { return }
        model.settings.displayName = trimmed
    }

    // REQ-CFG-013 (v2.27): same shape for the log file name. Committed once rather than per
    // keystroke — bound straight through, `onSettingsChanged` rejected every invalid
    // intermediate value silently, which put the old name back under the cursor mid-edit.
    private func commitLogFileName() {
        let trimmed = logFileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.isValidLogFileName(trimmed) else {
            logFileNameDraft = model.settings.logFileName
            logFileNameError = String(
                localized: "A file name cannot be empty, start with a dot, or contain a slash. The previous name was kept."
            )
            return
        }
        logFileNameDraft = trimmed
        logFileNameError = nil
        guard trimmed != model.settings.logFileName else { return }
        model.settings.logFileName = trimmed
    }

    // MARK: - Files

    private func filesTab(model: Bindable<AppModel>) -> some View {
        Form {
            // REQ-TSK-005: the path of the watched file is chosen from the settings screen, and does not
            // depend on where the Vault is.
            Section("Task file (read-only)") {
                filePathRow(path: self.model.settings.taskFilePath,
                            placeholder: String(localized: "Not set")) {
                    chooseTaskFile()
                }
                // REQ-TSK-024
                Text("Add a block ID (`^abc123`) at the end of a line, and the selection survives edits to the wording.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                Text("This file is never written to. It is opened read-only.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            Section("Where the session log is written") {
                // Decision 0015: an atomic write (REQ-LOG-004) needs permission for the same folder.
                filePathRow(path: self.model.settings.logFolderPath,
                            placeholder: String(localized: "No folder set")) {
                    chooseLogFolder()
                }
                HStack {
                    Text("File name")
                    Spacer()
                    TextField("", text: $logFileNameDraft)
                        .labelsHidden()
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                        .focused($logFileNameFocused)
                        .onSubmit { commitLogFileName() }
                        .onChange(of: logFileNameFocused) { _, focused in
                            if !focused { commitLogFileName() }
                        }
                        // Follows the setting while the field is not being typed in — the iPhone
                        // can change it too (REQ-CFG-002).
                        .onChange(of: self.model.settings.logFileName, initial: true) { _, name in
                            if !logFileNameFocused { logFileNameDraft = name }
                        }
                }
                // REQ-CFG-013 (v2.27) / REQ-COL-001: a refused name is said, in the same role
                // `logFileError` below already wears.
                if let logFileNameError {
                    Text(logFileNameError)
                        .font(.footnote)
                        .foregroundStyle(theme.color(.danger, .text))
                }
                // REQ-LOG-002 / Decision 0033: **what is not being recorded is said where the
                // setting is.** Not a failure, so it is worded as a state and not as an error.
                if self.model.logFolderNotSet {
                    Text("Until a folder is chosen, sessions are not recorded. The timer runs and loops count as usual; nothing is written down, and nothing is held back to write later.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                if let path = self.model.settings.logFilePath {
                    Text("Written to: \(path)")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }
                // REQ-COL-001 / 002: the role, not the hue. The same `danger` the two lines
                // in the diagnostics section below already use — nothing can be written.
                if let logFileError {
                    Text(logFileError).font(.footnote).foregroundStyle(theme.color(.danger, .text))
                }
                // REQ-LOG-020: the settings screen says plainly that editing it at the same time can conflict.
                Text("Editing the same file while it is being appended to will conflict. Do not leave the log open in an editor.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                // REQ-LOG-013
                Toggle("Write task names as links", isOn: model.settings.logTaskAsLink)
            }

            diagnosticsSection
        }
        .formStyle(.grouped)
    }

    // REQ-ERR-010 / Decision 0018: **what is never written is said beside the way to write it out.**
    private var diagnosticsSection: some View {
        Section("Diagnostic log") {
            Text("A record to attach to a bug report. **Task names, note contents, file paths and device names are never written.** You can paste it in public as it is.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
            Text("Kept in: \(model.diagnostics.directory.path)")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
            HStack {
                Button("Export…") { exportDiagnostics() }
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.diagnostics.directory.path)
                }
                Spacer()
            }
            // REQ-ERR-010 / Decision 0035: **the one place where a code is put on the screen.**
            // The code for this failure cannot go into the log (the log is the thing that is broken).
            // It is either thrown away or shown here.
            if let failure = model.diagnostics.lastFailure {
                Text("The diagnostic log cannot be written (\(failure.description)). Nothing else is affected — quote this code in a bug report.")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.danger, .text))
                    .textSelection(.enabled)
            }
            if let diagnosticsError {
                Text(diagnosticsError).font(.footnote).foregroundStyle(theme.color(.danger, .text))
            }
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mdoro-diagnostics.log"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.diagnostics.exportedText().write(to: url, atomically: true, encoding: .utf8)
            diagnosticsError = nil
        } catch {
            // REQ-ERR-010 / Decision 0034: the screen gets a sentence, the log gets the code.
            // Unlike the row above, this failure can be logged — the log itself still works —
            // so Decision 0035's one exception does not reach here.
            diagnosticsError = String(
                localized: "Mdoro could not write the export to that location. Choose another folder and try again."
            )
            model.diagnostics.write("diagnostics.export", level: .warn, [
                DiagnosticField("why", ErrorCode(error).summary("exportFailed")),
            ])
        }
    }

    // `path` is the user's own file path, so the `Text` stays verbatim.
    // The placeholder is looked up from the catalogue by the caller.
    private func filePathRow(path: String?, placeholder: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(path ?? placeholder)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(path == nil ? theme.textSecondary : theme.textPrimary)
            Spacer()
            Button("Choose…", action: choose)
        }
    }

    private func chooseTaskFile() {
        guard let url = openPanel(message: String(localized: "Choose the task file to watch")) else { return }
        model.setTaskFile(url)
        logFileError = nil
    }

    private func chooseLogFolder() {
        guard let url = folderPanel() else { return }
        do {
            try model.setLogFolder(url)
            logFileError = nil
        } catch {
            // REQ-LOG-021: the same file as Task.md cannot be named.
            logFileError = String(
                localized: "This folder cannot be used: it points at the task file, or it cannot be written to."
            )
        }
    }

    private func openPanel(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.allowedContentTypes = [UTType(filenameExtension: "md")].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    // Decision 0015: a folder is what gets chosen.
    // Without permission to write to the chosen folder, the temporary file an atomic write needs
    // cannot be created.
    private func folderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose a folder for the session log")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use this folder")
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Behaviour

    private func behaviorTab(model: Bindable<AppModel>) -> some View {
        Form {
            Section("Day and loops") {
                Stepper(value: model.settings.logicalDayStartHour, in: 0...12) {
                    Text("A day starts at \(self.model.settings.logicalDayStartHour):00")
                }
                Stepper(value: model.settings.idleResetHours, in: 1...48) {
                    Text("Reset the loop count after \(self.model.settings.idleResetHours) hours idle")
                }
            }
            Section("Tasks") {
                Toggle("Show completed tasks", isOn: model.settings.showCompletedTasks)
            }
            // REQ-UIX-033 / Decision 0016: unset by default. Any key may be bound.
            Section("Shortcuts") {
                HStack {
                    Text("Pause / Resume")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.pauseResumeHotKey,
                        isActive: self.model.pauseResumeHotKeyIsActive
                    )
                }
                HStack {
                    Text("Bring the window to the front")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.showWindowHotKey,
                        isActive: self.model.showWindowHotKeyIsActive
                    )
                }
                // Decision 0029: so that things can be moved on without opening the window.
                HStack {
                    Text("Start the next session")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.startNextHotKey,
                        isActive: self.model.startNextHotKeyIsActive
                    )
                }
                HStack {
                    Text("Skip")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.skipHotKey,
                        isActive: self.model.skipHotKeyIsActive
                    )
                }
                Text("A combination another app already uses cannot be registered. Include a modifier key.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: model.settings.launchAtLogin)
            }

            Section("Extending") {
                Text("You can extend from 5 minutes before the end until 1 minute after. Extending is meant for the moment you are actually aware of the boundary.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Display

    // MARK: - About

    // decisions/0021: one support link, here and nowhere else. It never appears where it would break
    // concentration.
    private var aboutTab: some View {
        Form {
            Section(AppInfo.name) {
                LabeledContent("Version", value: AppInfo.version())
                LabeledContent("License", value: AppInfo.license)
                Button { NSWorkspace.shared.open(AppInfo.sourceURL) } label: {
                    LabeledContent("Source") {
                        Text(AppInfo.sourceLabel)
                            .foregroundStyle(theme.color(.accentPrimary, .text))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(AppInfo.sourceLabel) in your browser")
                Text(AppInfo.tagline)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
            Section {
                // Show where the link goes before it is opened ("transparent", in decisions/0021).
                // REQ-COL-002: the `.link` style does not accept a colour of our own, so the label is
                // painted and the button made plain.
                Button { NSWorkspace.shared.open(AppInfo.supportURL) } label: {
                    Text(AppInfo.supportLabel)
                        .foregroundStyle(theme.color(.accentPrimary, .text))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(AppInfo.supportLabel) in your browser")
            } header: {
                Text("Support")
            } footer: {
                // REQ-NFR-008
                Text("Mdoro has no ads, no in-app purchases, and no analytics. If it is useful to you, this opens the page in your browser.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private func appearanceTab(model: Bindable<AppModel>) -> some View {
        Form {
            // REQ-COL-003
            Section("Appearance") {
                Picker("Appearance", selection: model.settings.appearance) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
                .pickerStyle(.inline)
            }
            // REQ-UIX-032
            Section("Menu bar") {
                Picker("Menu bar display", selection: model.settings.menuBarDisplayMode) {
                    Text("Time and type").tag(MenuBarDisplayMode.timeAndType)
                    Text("Time and task").tag(MenuBarDisplayMode.timeAndTask)
                    Text("Time only").tag(MenuBarDisplayMode.timeOnly)
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                }
                .pickerStyle(.inline)
                Text("The menu bar uses shape and text instead of color, because its background brightness changes.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}
