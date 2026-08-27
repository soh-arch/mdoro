import SwiftUI
import MdoroCore

// REQ-UIX-030 / 032 / 035 / REQ-COL-022: メニューバーのラベル。
//
// **メニューバーではアクセント色を使わない。** 地の明るさがユーザーの壁紙や外観設定で変わり、
// コントラストを保証できないため（REQ-COL-022）。状態は**形（テンプレート画像）とテキスト**で示す。
struct MenuBarLabelView: View {
    let model: AppModel

    // メニューバーの時計もモデルが進める（MainWindowView と同じ理由）。
    private var now: Date { model.displayNow }

    var body: some View {
        HStack(spacing: 4) {
            // REQ-UIX-035: 未接続・再接続中は形状の違うアイコンにする。
            Image(systemName: model.connection.menuBarSymbolName)
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

    private var accessibilityLabel: String {
        let remaining = Format.spokenRemaining(model.remainingSeconds(at: now))
        return "\(Format.sessionLabel(model.timer.sessionType))、\(remaining)、\(model.connection.label)"
    }
}

// REQ-UIX-031: ドロップダウンからは「一時停止 / 再開」「次のセッションを開始」「プリセット切替」
// 「メインウィンドウを開く」のみ。中断・リセット・プリセット編集・設定変更は誤操作防止のため出さない。
struct MenuBarMenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var preset: Preset { model.presets.activePreset ?? Preset.standard() }

    var body: some View {
        switch model.timer.runState {
        case .running:
            Button("Pause") { model.send(.pause) }
        case .paused:
            Button("Resume") { model.send(.resume) }
        case .idle, .finished:
            Button(nextSessionTitle) { startNext() }
        case .pendingDecision:
            // 確認はメインウィンドウで行う（REQ-UIX-036 / REQ-PER-005）。
            Text("A decision is needed")
            Button("Open the main window") { openMain() }
        }

        if model.timer.runState == .running || model.timer.runState == .paused {
            Button(nextSessionTitle) { startNext() }
        }

        Divider()

        // REQ-UIX-007: プリセットが2件以上のときだけ切替を出す。
        if model.presets.presets.count >= 2 {
            Menu("Preset") {
                ForEach(model.presets.presets) { candidate in
                    Button {
                        model.send(.selectPreset(id: candidate.id))
                    } label: {
                        // REQ-UIX-008: 時間構成を併記する。
                        Text("\(candidate.name)（\(Format.presetShape(candidate))）"
                             + (candidate.id == preset.id ? " ✓" : ""))
                    }
                }
            }
            Divider()
        }

        Button("Open Main Window") { openMain() }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private var nextSessionTitle: String {
        "Start Next (\(Format.sessionLabel(model.timer.nextSessionType)))"
    }

    private func startNext() {
        let next = model.timer.nextSessionType
        if next == .work {
            model.send(.startWork(presetId: preset.id, taskSnapshot: model.tasks.selectedTaskSnapshot))
        } else {
            model.send(.startBreak(type: next, presetId: preset.id))
        }
    }

    private func openMain() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: MdoroMacApp.mainWindowId)
    }
}
