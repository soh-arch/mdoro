import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import PomodoroCore

// REQ-UIX-020〜029: ロック画面・ダイナミックアイランドでの残り時間表示。
//
// **これはセッション終了を知らせる手段ではない**（8.3 末尾）。終了の通知は第5章の
// ローカル通知が担い、こちらはアプリが動いている間の可視化に徹する。
// 両者を独立させることで、更新できない状況でも通知は必ず届く（Decision 0009）。
struct MdoroWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MdoroActivityAttributes.self) { context in
            LockScreenView(context: context)
                // REQ-UIX-027: 8.5 のトークンをそのまま当てない。
                // 背景はユーザーの壁紙なので「対 --bg」のコントラスト保証が成立しない。
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(sessionLabel(context.state.sessionType), systemImage: symbol(context.state.sessionType))
                        .font(.system(size: WidgetFontSize.label))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                        .font(.system(size: WidgetFontSize.label).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    TimerText(state: context.state)
                        .font(.system(size: WidgetFontSize.islandTimer, weight: .medium, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        if let task = context.state.taskName, !task.isEmpty {
                            Text(task).font(.system(size: WidgetFontSize.secondary)).lineLimit(1)
                        }
                        StatusNotice(isStale: context.isStale, isConnected: context.state.isConnected)
                        Controls(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(context.state.sessionType))
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.compactTimer).monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: symbol(context.state.sessionType))
            }
        }
    }

    private func sessionLabel(_ type: SessionType) -> String {
        switch type {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "短い休憩")
        case .longBreak: return String(localized: "長い休憩")
        }
    }

    private func symbol(_ type: SessionType) -> String {
        switch type {
        case .work: return "circle.fill"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "cup.and.saucer.fill"
        }
    }
}

// フォントサイズは pt で明示する。
// ロック画面とダイナミックアイランドは**高さが固定**で、字が伸びれば行が落ちる。
// 数値は従来の `.caption` / `.caption2` と同じ 12 / 11 pt で、見た目は変わらない。
private enum WidgetFontSize {
    static let label: CGFloat = 12
    static let secondary: CGFloat = 11
    static let lockTimer: CGFloat = 44
    static let islandTimer: CGFloat = 34
    static let compactTimer: CGFloat = 12
}

// REQ-UIX-021: 残り時間は `Text(timerInterval:pauseTime:countsDown:)` に任せる。
// **アプリからの毎秒更新を行ってはならない。** 更新予算を使い切るうえ、
// そもそも suspend 中は更新できない。
private struct TimerText: View {
    let state: MdoroActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timerRange, pauseTime: state.pauseTime, countsDown: true)
            .monospacedDigit()
    }
}

// REQ-UIX-023: `isStale` が真のとき「情報が古い可能性があります」を明示する。
// REQ-UIX-004: 接続状態は常時視認できること。
//
// **`isStale` の判定を下すのは OS で、期限が来た瞬間に切り替わるとは限らない。**
// 90 秒の期限に対して、実機では4分後に切り替わった（2026-08-27、19:08 切断 → 19:12 表示）。
// 切れたこと自体はこちら側が知っている。**知っていることは、OS を待たずに自分で言う。**
private struct StatusNotice: View {
    let isStale: Bool
    let isConnected: Bool

    var body: some View {
        if isStale {
            notice("情報が古い可能性があります", "exclamationmark.triangle")
        } else if !isConnected {
            notice("Mac との接続が切れています", ConnectionStatus.disconnected.symbolName)
        }
    }

    private func notice(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: WidgetFontSize.secondary))
            .foregroundStyle(.secondary)
    }
}

// REQ-UIX-024: 「一時停止 / 再開」を LiveActivityIntent として置く。
private struct Controls: View {
    let state: MdoroActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if state.isPaused {
                Button(intent: ResumeSessionIntent()) { Label("再開", systemImage: "play.fill") }
            } else {
                Button(intent: PauseSessionIntent()) { Label("一時停止", systemImage: "pause.fill") }
            }
        }
        .font(.system(size: WidgetFontSize.label))
        .buttonStyle(.bordered)
        // REQ-COM-013 と同じ理由: 繋がっていないなら操作できるように見せない。
        .disabled(!state.isConnected)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<MdoroActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: WidgetFontSize.label, weight: .medium))
                Spacer()
                Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                    .font(.system(size: WidgetFontSize.label).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                // **`Text(timerInterval:)` に `.fixedSize()` を付けないこと。**
                // 打ち切り対策のつもりで付けたところ、ロック画面のレイアウトが破綻し、
                // 時間も操作も消えて真っ白になった（2026-08-27、実機で確認）。
                // この Text の寸法はシステムが決める。こちらから理想幅を要求してはならない。
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.lockTimer, weight: .medium, design: .rounded).monospacedDigit())
                Spacer()
                Controls(state: context.state)
            }

            // ロック画面は**高さが固定**で、入らない行は黙って消える。
            // 3行目を取り合うなら、**REQ-UIX-023（MUST）の注意書きがタスク名に勝つ。**
            // 古い情報を正しい情報のように見せないことのほうが、何をしていたかより重い。
            if context.isStale || !context.state.isConnected {
                StatusNotice(isStale: context.isStale, isConnected: context.state.isConnected)
            } else if let task = context.state.taskName, !task.isEmpty {
                Text(task).font(.system(size: WidgetFontSize.secondary)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding()
    }

    private var label: String {
        switch context.state.sessionType {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "短い休憩")
        case .longBreak: return String(localized: "長い休憩")
        }
    }
}
