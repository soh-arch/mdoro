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

// REQ-UIX-031 / Decision 0029: **危険度で階層を分ける。**
//
// 旧条文は操作を4つに絞っていたが、守っていたのは「誤操作」であって
// 「メニューにあること」ではない。**確認を1段はさめば、深さは作れる。**
//
// 直下         … 取り返しのつく操作
// 確認1段     … 中断・周回リセット（破壊的）
// サブメニュー … 設定の一部（選ぶだけ。破壊的操作を含まない）
// 置かない     … プリセット編集・パス変更・ペアリング（不可逆か、外の世界に触る）
struct MenuBarMenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var preset: Preset { model.presets.activePreset ?? Preset.standard() }
    private var isLive: Bool { model.timer.runState == .running || model.timer.runState == .paused }

    var body: some View {
        // --- 直下 ---
        switch model.timer.runState {
        case .running:
            Button("Pause") { model.send(.pause) }
        case .paused:
            Button("Resume") { model.send(.resume) }
        case .idle, .finished:
            Button(nextSessionTitle) { model.startNextSession() }
        case .pendingDecision:
            // 確認はメインウィンドウで行う（REQ-UIX-036 / REQ-PER-005）。
            Text("A decision is needed")
            Button("Open the main window") { openMain() }
        }

        if isLive {
            Button(nextSessionTitle) { model.startNextSession() }
            // REQ-TIM-018: スキップは周回数を減らさない。取り返しがつく。
            Button("Skip") { model.send(.skip) }
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
        }
        taskMenu
        displayMenu

        Divider()

        // --- 確認を1段はさむ ---
        // **滑って押しても走らない。** 破壊的な操作を浅い場所に置かないための段。
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

        SettingsLink { Text("Settings…") }
        Button("Open Main Window") { openMain() }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    // 設定画面の一部を持ち出す。**選ぶだけで、外の世界には触らない。**
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

    // REQ-TSK-004: タスクの選択はどちらの画面からでもできること。
    // **一覧が長いときは打ち切る。** 縦長のメニューに1000件は載せられない。
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
                // **選択の解除は最下段。** 上に置くと、タスクを選ぶつもりで押してしまう。
                if model.tasks.selectedTaskId != nil {
                    Divider()
                    Button("Clear selection") { model.clearTaskSelection() }
                }
            }
        }
    }

    private static let taskMenuLimit = 20

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
