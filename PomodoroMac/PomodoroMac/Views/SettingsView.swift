import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PomodoroCore

// REQ-UIX-031: 中断・リセット・プリセット編集・設定変更はメインウィンドウ（と設定画面）でのみ可能。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    @State private var logFileError: String?
    @State private var diagnosticsError: String?

    var body: some View {
        @Bindable var bindable = model
        TabView {
            filesTab(model: $bindable).tabItem { Label("ファイル", systemImage: "folder") }
            behaviorTab(model: $bindable).tabItem { Label("動作", systemImage: "timer") }
            appearanceTab(model: $bindable).tabItem { Label("表示", systemImage: "paintpalette") }
            PresetEditorView().tabItem { Label("プリセット", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 460)
    }

    // MARK: - ファイル

    private func filesTab(model: Bindable<AppModel>) -> some View {
        Form {
            // REQ-TSK-005: 監視対象ファイルのパスは設定画面から選べ、Vault の場所に依存しない。
            Section("Task.md（読み取り専用）") {
                filePathRow(path: self.model.settings.taskFilePath, placeholder: "未設定") {
                    chooseTaskFile()
                }
                // REQ-TSK-024
                Text("重要なタスクには行末にブロック ID（`^abc123`）を付けると、文言を修正しても選択が維持されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("このファイルには書き込みません。読み取り専用として開きます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("実績ログの出力先") {
                // Decision 0015: フォルダを選ばせ、ファイル名は設定で持つ。
                // 原子的な書き込み (REQ-LOG-004) に、同じフォルダへの書き込み許可が要るため。
                filePathRow(path: self.model.settings.logFolderPath, placeholder: "フォルダ未設定") {
                    chooseLogFolder()
                }
                HStack {
                    Text("ファイル名")
                    Spacer()
                    TextField("", text: model.settings.logFileName)
                        .labelsHidden()
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }
                if let path = self.model.settings.logFilePath {
                    Text("出力先: \(path)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let logFileError {
                    Text(logFileError).font(.footnote).foregroundStyle(.red)
                }
                // REQ-LOG-020: 同時編集で競合しうることを設定画面に明記する。
                Text("追記中にエディタ側で同じファイルを編集すると競合します。ログファイルは開いたままにしないでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // REQ-LOG-013
                Toggle("ログのタスク名をリンク記法にする", isOn: model.settings.logTaskAsLink)
            }

            diagnosticsSection
        }
        .formStyle(.grouped)
    }

    // REQ-ERR-010 / Decision 0018: 記録しないと決めたことは、決めただけでは伝わらない。
    // **何を書かないかを、書き出す導線の隣に置く。**
    private var diagnosticsSection: some View {
        Section("診断ログ") {
            Text("不具合の報告に添えるための記録です。**タスク名・ノートの中身・ファイルのパス・端末名は記録しません。** そのまま公開の場に貼れます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("保存先: \(DiagnosticLog.directory.path)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("書き出す…") { exportDiagnostics() }
                Button("Finder で表示") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: DiagnosticLog.directory.path)
                }
                Spacer()
            }
            if let failure = model.diagnostics.lastFailure {
                Text("診断ログを書けていません: \(failure)")
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
            Button("選択…", action: choose)
        }
    }

    private func chooseTaskFile() {
        guard let url = openPanel(message: "監視する Task.md を選んでください") else { return }
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
            logFileError = "このフォルダは選べません。Task.md と同じファイルを指すか、書き込めない場所です。"
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
        panel.message = "実績ログを保存するフォルダを選んでください"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "このフォルダを使う"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - 動作

    private func behaviorTab(model: Bindable<AppModel>) -> some View {
        Form {
            Section("論理日と周回") {
                Stepper(value: model.settings.logicalDayStartHour, in: 0...12) {
                    Text("論理日の境界時刻：\(self.model.settings.logicalDayStartHour) 時")
                }
                Stepper(value: model.settings.idleResetHours, in: 1...48) {
                    Text("周回数を自動リセットする未使用時間：\(self.model.settings.idleResetHours) 時間")
                }
            }
            Section("タスク") {
                Toggle("完了済みタスクを一覧に表示する", isOn: model.settings.showCompletedTasks)
            }
            // REQ-UIX-033 / Decision 0016: 既定は未設定。任意のキーを割り当てられる。
            Section("ショートカット") {
                HStack {
                    Text("一時停止 / 再開")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.pauseResumeHotKey,
                        isActive: self.model.pauseResumeHotKeyIsActive
                    )
                }
                HStack {
                    Text("ウィンドウを前面に出す")
                    Spacer()
                    HotKeyRecorderView(
                        binding: model.settings.showWindowHotKey,
                        isActive: self.model.showWindowHotKeyIsActive
                    )
                }
                Text("他のアプリで使われている組み合わせは登録できません。修飾キーを含めて指定してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            PairingSection()

            Section("起動") {
                Toggle("ログイン時に起動する", isOn: model.settings.launchAtLogin)
            }

            Section("延長") {
                Text("延長できるのは終了5分前から終了1分後までです。区切りを意識しているときだけ延ばせるようにしています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 表示

    private func appearanceTab(model: Bindable<AppModel>) -> some View {
        Form {
            // REQ-COL-003
            Section("外観") {
                Picker("外観", selection: model.settings.appearance) {
                    Text("システムに合わせる").tag(AppearancePreference.system)
                    Text("ライト").tag(AppearancePreference.light)
                    Text("ダーク").tag(AppearancePreference.dark)
                }
                .pickerStyle(.inline)
            }
            // REQ-UIX-032
            Section("メニューバー") {
                Picker("表示密度", selection: model.settings.menuBarDisplayMode) {
                    Text("残り時間とセッション種別").tag(MenuBarDisplayMode.timeAndType)
                    Text("残り時間とタスク名").tag(MenuBarDisplayMode.timeAndTask)
                    Text("残り時間のみ").tag(MenuBarDisplayMode.timeOnly)
                    Text("アイコンのみ").tag(MenuBarDisplayMode.iconOnly)
                }
                .pickerStyle(.inline)
                Text("メニューバーでは色を使わず、形とテキストで状態を示します（背景の明るさが変わるためです）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
