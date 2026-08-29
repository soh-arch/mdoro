import ActivityKit
import WidgetKit
import SwiftUI
import MdoroCore

// REQ-UIX-020–029 / Decision 0009: showing the remaining time on the lock screen and in the Dynamic Island.
// **This is not the means of announcing the end of a session.** Chapter 5's local notifications carry that.
// Keeping the two apart means the notification always arrives, even where nothing can be updated.
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
                // The two regions at the edges are **narrow, and they reach the island's outer edge.**
                // Adding an icon pushes the type's name out and it disappears; set flush, the rounded
                // corners clip the first and the last character. Text only, moved inwards.
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
                // **Do not use `.center`.** The centre region takes the whole width and crushes the two at the edges.
                DynamicIslandExpandedRegion(.bottom) {
                    // **Do not put the task name on the island.** The height is fixed, and stacking
                    // three of them makes them quietly disappear.
                    // REQ-UIX-025: the lock screen holds the task name.
                    HStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            TimerText(state: context.state)
                                .font(.system(size: WidgetFontSize.islandTimer, weight: .medium, design: .rounded).monospacedDigit())
                            StatusNotice(isStale: context.isStale, isConnected: context.state.isConnected)
                        }
                        Spacer(minLength: 0)
                    }
                    // The bottom region reaches the outer edge as well. **The rounded corners eat into
                    // it, so it is moved in on the sides and the bottom.**
                    .padding(.horizontal, WidgetInset.islandEdge)
                    .padding(.bottom, WidgetInset.islandBottom)
                }
            } compactLeading: {
                // REQ-UIX-023: no wording will fit in the compact presentation. **A symbol says it.**
                Image(systemName: compactSymbol(context))
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.compactTimer).monospacedDigit())
                    // 9.2: Focus runs to 180 minutes at most. The width is set so that even `1:05:00` is not cut off.
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

    // When nothing has been confirmed, a warning symbol goes out instead of the type.
    private func compactSymbol(_ context: ActivityViewContext<MdoroActivityAttributes>) -> String {
        if context.isStale || !context.state.isConnected { return "exclamationmark.triangle.fill" }
        return symbol(context.state.sessionType)
    }

    // In the spirit of REQ-COL-013, **the type is told apart by a difference in shape.**
    private func symbol(_ type: SessionType) -> String {
        switch type {
        case .work: return "timer"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "moon.zzz"
        }
    }
}

// REQ-UIX-041: font sizes are given explicitly in pt. **The height is fixed**, and if the text grows a line drops out.
// REQ-UIX-042: the spacing is chosen from 8.6.2's values.
private enum WidgetInset {
    // The inset from the edge that keeps clear of the island's rounded corners.
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

// REQ-UIX-021: the remaining time is left to `Text(timerInterval:pauseTime:countsDown:)`.
// **The app must not update it every second.**
private struct TimerText: View {
    let state: MdoroActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timerRange, pauseTime: state.pauseTime, countsDown: true)
            .monospacedDigit()
    }
}

// REQ-UIX-023: when `isStale` is true, say plainly that the information may be out of date.
// REQ-UIX-004: the connection state must be visible at all times.
//
// **It is the OS that flips `isStale`, and not necessarily the moment the deadline arrives** (measured
// at four minutes late). That the connection dropped is something we know ourselves.
// **What we know, we say ourselves, without waiting for the OS.**
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

    // **Take it as a `LocalizedStringKey`.** Passing a `String` resolves to `Label`'s verbatim
    // initialiser, and these two sentences alone, out of everything this extension shows, never reach
    // the catalogue (Decision 0022).
    private func notice(_ text: LocalizedStringKey, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: WidgetFontSize.secondary))
            .foregroundStyle(.secondary)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<MdoroActivityAttributes>

    var body: some View {
        // **Two columns, to use the width.**
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: WidgetFontSize.label, weight: .medium))
                // A line that does not fit quietly disappears. **REQ-UIX-023's notice (a MUST) beats the task name.**
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
                // **Do not put `.fixedSize()` on `Text(timerInterval:)`.** The system decides its dimensions.
                TimerText(state: context.state)
                    .font(.system(size: WidgetFontSize.lockTimer, weight: .medium, design: .rounded).monospacedDigit())
                Text("\(context.state.loopDisplay) / \(context.state.longBreakInterval)")
                    .font(.system(size: WidgetFontSize.label).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // REQ-UIX-042: `.padding()`'s 16 doubles up with the system's own spacing.
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
