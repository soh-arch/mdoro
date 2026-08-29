import ActivityKit
import WidgetKit
import SwiftUI
import MdoroCore

// REQ-UIX-020〜029 / Decision 0009: ロック画面・ダイナミックアイランドでの残り時間表示。
// **これはセッション終了を知らせる手段ではない。** 終了の通知は第5章のローカル通知が担う。
// 独立させることで、更新できない状況でも通知は必ず届く。
struct MdoroWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MdoroActivityAttributes.self) { context in
            LockScreenView(context: context)
                // REQ-UIX-027: 8.5's tokens are guaranteed against `--bg`, not the lock screen's
                // container; on the container's own background the clause leaves the foreground
                // to the system. Facts: docs/PLATFORM.md.
                .activityBackgroundTint(nil)
                // Reaches the system's dismiss button, not the view above (docs/PLATFORM.md).
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                // 端の2領域は**狭く、島の外周まで届く。** アイコンを添えると種別名が押し出されて消え、
                // 詰めて置くと角の丸みで最初と最後の字が欠ける。文字だけにして内側へ寄せる。
                DynamicIslandExpandedRegion(.leading) {
                    Text(sessionLabel(context.state.sessionType))
                        .font(.system(size: WidgetFontSize.label, weight: .medium))
                        .lineLimit(1)
                        .padding(.leading, WidgetInset.islandEdge)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.loopDisplay)/\(context.state.longBreakInterval)")
                        .font(.system(size: WidgetFontSize.label).monospacedDigit())
                        .lineLimit(1)
                        .padding(.trailing, WidgetInset.islandEdge)
                }
                // **`.center` は使わない。** 中央領域が幅を全部取り、端の2領域を潰す。
                DynamicIslandExpandedRegion(.bottom) {
                    // **島にタスク名を出さない。** 高さが固定で、3つ積むと黙って消える。
                    // REQ-UIX-025: タスク名はロック画面が持つ。
                    HStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            TimerText(state: context.state)
                                .font(.system(size: WidgetFontSize.islandTimer, weight: .medium, design: .rounded).monospacedDigit())
                            StatusNotice(isStale: context.isStale, isConnected: context.state.isConnected)
                        }
                        Spacer(minLength: 0)
                    }
                    // 下の領域も外周まで届く。**角の丸みに食われるので四方を逃がす。**
                    .padding(.horizontal, WidgetInset.islandEdge)
                    .padding(.bottom, WidgetInset.islandBottom)
                }
            } compactLeading: {
                // REQ-UIX-023: コンパクト表示に文言は置けない。**記号で示す。**
                Image(systemName: compactSymbol(context))
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.compactTimer).monospacedDigit())
                    // 9.2: Focus は最大180分。`1:05:00` でも切れない幅にする。
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: compactSymbol(context))
            }
        }
    }

    private func sessionLabel(_ type: SessionType) -> String {
        switch type {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }

    // 確認できていないときは種別ではなく注意記号を出す。
    private func compactSymbol(_ context: ActivityViewContext<MdoroActivityAttributes>) -> String {
        if context.isStale || !context.state.isConnected { return "exclamationmark.triangle.fill" }
        return symbol(context.state.sessionType)
    }

    // REQ-COL-013 の趣旨で、**形の違いで種別を分ける。**
    private func symbol(_ type: SessionType) -> String {
        switch type {
        case .work: return "timer"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "moon.zzz"
        }
    }
}

// REQ-UIX-041: フォントサイズは pt で明示する。**高さが固定**で、字が伸びれば行が落ちる。
// REQ-UIX-042: 余白は 8.6.2 の値から選ぶ。
private enum WidgetInset {
    // 島の角の丸みを避けるための、端からの逃げ。
    static let islandEdge: CGFloat = 8
    static let islandBottom: CGFloat = 4
}

private enum WidgetFontSize {
    static let label: CGFloat = 12
    static let secondary: CGFloat = 11
    static let lockTimer: CGFloat = 44
    static let islandTimer: CGFloat = 34
    static let compactTimer: CGFloat = 12
}

// REQ-UIX-021: 残り時間は `Text(timerInterval:pauseTime:countsDown:)` に任せる。
// **アプリからの毎秒更新を行ってはならない。**
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
// **`isStale` を切り替えるのは OS で、期限が来た瞬間とは限らない**（実測で4分遅れ）。
// 切れたこと自体はこちらが知っている。**知っていることは、OS を待たずに自分で言う。**
private struct StatusNotice: View {
    let isStale: Bool
    let isConnected: Bool

    var body: some View {
        if isStale {
            notice("This may be out of date", "exclamationmark.triangle")
        } else if !isConnected {
            notice("Disconnected from your Mac", ConnectionStatus.disconnected.peerSymbolName)
        }
    }

    // **`LocalizedStringKey` で受ける。** `String` を渡すと `Label` の verbatim 初期化子に
    // 解決され、この拡張が出す2文だけがカタログに載らない（Decision 0022）。
    private func notice(_ text: LocalizedStringKey, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: WidgetFontSize.secondary))
            .foregroundStyle(.secondary)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<MdoroActivityAttributes>

    var body: some View {
        // **2列にして幅を使う。**
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: WidgetFontSize.label, weight: .medium))
                // 入らない行は黙って消える。**REQ-UIX-023（MUST）の注意書きがタスク名に勝つ。**
                if context.isStale || !context.state.isConnected {
                    StatusNotice(isStale: context.isStale, isConnected: context.state.isConnected)
                } else if let task = context.state.taskName, !task.isEmpty {
                    Text(task)
                        .font(.system(size: WidgetFontSize.secondary))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // **`Text(timerInterval:)` に `.fixedSize()` を付けないこと。** 寸法はシステムが決める。
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.lockTimer, weight: .medium, design: .rounded).monospacedDigit())
                Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                    .font(.system(size: WidgetFontSize.label).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // REQ-UIX-042: `.padding()` の 16 はシステム側の余白と二重になる。
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var label: String {
        switch context.state.sessionType {
        case .work: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }
}
