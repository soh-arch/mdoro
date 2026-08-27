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
struct PomodoroWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            LockScreenView(context: context)
                // REQ-UIX-027: 8.5 のトークンをそのまま当てない。
                // 背景はユーザーの壁紙なので「対 --bg」のコントラスト保証が成立しない。
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(sessionLabel(context.state.sessionType), systemImage: symbol(context.state.sessionType))
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    TimerText(state: context.state)
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        if let task = context.state.taskName, !task.isEmpty {
                            Text(task).font(.caption2).lineLimit(1)
                        }
                        StaleNotice(isStale: context.isStale)
                        Controls(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(context.state.sessionType))
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.caption.monospacedDigit())
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

// REQ-UIX-021: 残り時間は `Text(timerInterval:pauseTime:countsDown:)` に任せる。
// **アプリからの毎秒更新を行ってはならない。** 更新予算を使い切るうえ、
// そもそも suspend 中は更新できない。
private struct TimerText: View {
    let state: PomodoroActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timerRange, pauseTime: state.pauseTime, countsDown: true)
            .monospacedDigit()
    }
}

// REQ-UIX-023: `isStale` が真のとき「情報が古い可能性があります」を明示する。
// **古い情報を正しい情報のように見せない。**
private struct StaleNotice: View {
    let isStale: Bool

    var body: some View {
        if isStale {
            Label("情報が古い可能性があります", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// REQ-UIX-024: 「一時停止 / 再開」を LiveActivityIntent として置く。
private struct Controls: View {
    let state: PomodoroActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if state.isPaused {
                Button(intent: ResumeSessionIntent()) { Label("再開", systemImage: "play.fill") }
            } else {
                Button(intent: PauseSessionIntent()) { Label("一時停止", systemImage: "pause.fill") }
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        // REQ-COM-013 と同じ理由: 繋がっていないなら操作できるように見せない。
        .disabled(!state.isConnected)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<PomodoroActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                TimerText(state: context.state)
                    .font(.system(size: 44, weight: .medium, design: .rounded).monospacedDigit())
                Spacer()
                Controls(state: context.state)
            }

            if let task = context.state.taskName, !task.isEmpty {
                Text(task).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            StaleNotice(isStale: context.isStale)
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
