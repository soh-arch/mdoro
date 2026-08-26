import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PomodoroCore

// REQ-UIX-031: 中断・リセット・プリセット編集・設定変更はメインウィンドウ（と設定画面）でのみ可能。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    @State private var logFileError: String?

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
                Text("重要なタスクには Obsidian 側でブロック ID（`^abc123`）を付けると、文言を修正しても選択が維持されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("このファイルには書き込みません。読み取り専用として開きます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("実績ログの出力先") {
                filePathRow(path: self.model.settings.logFilePath, placeholder: "未設定") {
                    chooseLogFile()
                }
                if let logFileError {
                    Text(logFileError).font(.footnote).foregroundStyle(.red)
                }
                // REQ-LOG-020: 同時編集で競合しうることを設定画面に明記する。
                Text("追記中に Obsidian 側で同じファイルを編集すると競合します。ログファイルは Obsidian で開いたままにしないでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // REQ-LOG-013
                Toggle("ログのタスク名をリンク記法にする", isOn: model.settings.logTaskAsLink)
                // REQ-LOG-014
                Toggle("前日の日次サマリ行を出力する", isOn: model.settings.logDailySummary)
                    .disabled(true)
                    .help("未実装です")
            }
        }
        .formStyle(.grouped)
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

    private func chooseLogFile() {
        // REQ-LOG-002: ファイルが存在しない場合は新規作成する。
        // NSOpenPanel では**まだ存在しないファイルを選べない**ため、出力先の指定には保存パネルを使う。
        guard let url = savePanel() else { return }
        do {
            try model.setLogFile(url)
            logFileError = nil
        } catch {
            // REQ-LOG-021: Task.md と同一のファイルは指定できない。
            logFileError = "このファイルは選べません。Task.md と同じファイル、または存在しないフォルダです。"
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

    private func savePanel() -> URL? {
        let panel = NSSavePanel()
        panel.message = "実績ログの出力先を選んでください"
        panel.allowedContentTypes = [UTType(filenameExtension: "md")].compactMap { $0 }
        panel.nameFieldStringValue = "PomodoroLog.md"
        panel.canCreateDirectories = true
        // 既存ファイルを選んだ場合も追記するだけなので、上書き警告は出さない。
        panel.isExtensionHidden = false
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
