import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MdoroCore

// REQ-UIX-031: 中断・リセット・プリセット編集・設定変更はメインウィンドウ（と設定画面）でのみ可能。
// 設定タブの識別子。メインウィンドウから開く先を指定するため、モデルが持つ。
enum SettingsTab: String, Hashable, CaseIterable {
    case presets, files, connection, behavior, display, about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { Theme(appearance: model.settings.appearance, systemScheme: systemScheme) }
    @State private var logFileError: String?
    @State private var diagnosticsError: String?

    var body: some View {
        @Bindable var bindable = model
        // 並びは「タイマーの形 → 読み書きするファイル → 相手の端末 → 規則 → 見た目」。
        // 触る頻度が高いものほど手前に置く。
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
        // 設定ウィンドウは別の Scene なので、テーマを自分で配る（REQ-COL-002）。
        .environment(\.theme, theme)
        // REQ-COL-003: ライト固定・ダーク固定はこちらの窓にも効かせる。
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: SwiftUI.ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - 接続

    // 「iPhone との接続」は動作の設定ではない。独立したタブに置き、
    // メインウィンドウの接続表示から直接ここへ来られるようにする（REQ-UIX-004）。
    private var connectionTab: some View {
        Form { PairingSection() }.formStyle(.grouped)
    }

    // MARK: - ファイル

    private func filesTab(model: Bindable<AppModel>) -> some View {
        Form {
            // REQ-TSK-005: 監視対象ファイルのパスは設定画面から選べ、Vault の場所に依存しない。
            Section("Task file (read-only)") {
                filePathRow(path: self.model.settings.taskFilePath, placeholder: "Not set") {
                    chooseTaskFile()
                }
                // REQ-TSK-024
                Text("Add a block ID (`^abc123`) at the end of a line, and the selection survives edits to the wording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("This file is never written to. It is opened read-only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Where the session log is written") {
                // Decision 0015: フォルダを選ばせ、ファイル名は設定で持つ。
                // 原子的な書き込み (REQ-LOG-004) に、同じフォルダへの書き込み許可が要るため。
                filePathRow(path: self.model.settings.logFolderPath, placeholder: "No folder set") {
                    chooseLogFolder()
                }
                HStack {
                    Text("File name")
                    Spacer()
                    TextField("", text: model.settings.logFileName)
                        .labelsHidden()
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }
                if let path = self.model.settings.logFilePath {
                    Text("Written to: \(path)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let logFileError {
                    Text(logFileError).font(.footnote).foregroundStyle(.red)
                }
                // REQ-LOG-020: 同時編集で競合しうることを設定画面に明記する。
                Text("Editing the same file while it is being appended to will conflict. Do not leave the log open in an editor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // REQ-LOG-013
                Toggle("Write task names as links", isOn: model.settings.logTaskAsLink)
            }

            diagnosticsSection
        }
        .formStyle(.grouped)
    }

    // REQ-ERR-010 / Decision 0018: 記録しないと決めたことは、決めただけでは伝わらない。
    // **何を書かないかを、書き出す導線の隣に置く。**
    private var diagnosticsSection: some View {
        Section("Diagnostic log") {
            Text("A record to attach to a bug report. **Task names, note contents, file paths and device names are never written.** You can paste it in public as it is.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Kept in: \(DiagnosticLog.directory.path)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Export…") { exportDiagnostics() }
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: DiagnosticLog.directory.path)
                }
                Spacer()
            }
            if let failure = model.diagnostics.lastFailure {
                Text("The diagnostic log cannot be written: \(failure)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let diagnosticsError {
                Text(diagnosticsError).font(.footnote).foregroundStyle(.red)
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
            diagnosticsError = String(describing: error)
        }
    }

    private func filePathRow(path: String?, placeholder: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(path ?? placeholder)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(path == nil ? .secondary : .primary)
            Spacer()
            Button("Choose…", action: choose)
        }
    }

    private func chooseTaskFile() {
        guard let url = openPanel(message: "Choose the task file to watch") else { return }
        model.setTaskFile(url)
        logFileError = nil
    }

    private func chooseLogFolder() {
        guard let url = folderPanel() else { return }
        do {
            try model.setLogFolder(url)
            logFileError = nil
        } catch {
            // REQ-LOG-021: Task.md と同一のファイルは指定できない。
            logFileError = "This folder cannot be used: it points at the task file, or it cannot be written to."
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

    // Decision 0015: フォルダを選ばせる。
    // 選んだフォルダへの書き込み許可がないと、原子的書き込みの一時ファイルを作れない。
    private func folderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the session log"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - 動作

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
            // REQ-UIX-033 / Decision 0016: 既定は未設定。任意のキーを割り当てられる。
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
                // Decision 0029: ウィンドウを開かずに進められるように。
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
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: model.settings.launchAtLogin)
            }

            Section("Extending") {
                Text("You can extend from 5 minutes before the end until 1 minute after. Extending is meant for the moment you are actually aware of the boundary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 表示

    // MARK: - About

    // decisions/0021: 支援リンクはここに1つだけ。集中を切る場所には出さない。
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
                    .foregroundStyle(.secondary)
            }
            Section {
                // 開く前にリンク先を見せる（decisions/0021 の「透明」）。
                // REQ-COL-002: `.link` スタイルは自前の色を受け付けないため、ラベルを塗って素のボタンにする。
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
