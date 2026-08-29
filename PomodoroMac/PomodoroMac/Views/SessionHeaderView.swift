import SwiftUI
import MdoroCore

// REQ-UIX-002 / 003 / 013: the session type is shown in both colour and words, and the loop count as
// n / interval.
// REQ-COL-011: only -graphic and -text may be used. The banner treatment is reserved for warning, and
// ColorRole refuses it.
struct SessionHeaderView: View {
    @Environment(\.theme) private var theme
    let sessionType: SessionType
    let runState: RunState
    let loopDisplay: Int
    let longBreakInterval: Int

    private var role: ColorRole { sessionType.colorRole }

    var body: some View {
        HStack(spacing: 10) {
            // REQ-COL-010 / 013: nothing rides on colour alone. The stroke style tells them apart too.
            ProgressRingGlyph(style: sessionType.progressRingStyle)
                .foregroundStyle(theme.color(role, .graphic))
                .frame(width: 14, height: 14)

            Text(Format.sessionLabel(sessionType))
                .font(.headline)
                .foregroundStyle(theme.color(role, .text))

            if runState == .paused {
                Text("Paused")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            // REQ-UIX-003: that the next one is a long break must be knowable in advance.
            Text("\(loopDisplay) / \(longBreakInterval)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("Loop \(loopDisplay) of \(longBreakInterval)")
        }
    }
}

// REQ-COL-013: Focus is a solid line, a short break a thin solid line, a long break a double line.
struct ProgressRingGlyph: View {
    let style: ProgressRingStyle

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                switch style {
                case .solid:
                    Circle().strokeBorder(lineWidth: size * 0.22)
                case .thin:
                    Circle().strokeBorder(lineWidth: size * 0.11)
                case .double:
                    Circle().strokeBorder(lineWidth: size * 0.11)
                    Circle().strokeBorder(lineWidth: size * 0.11).padding(size * 0.22)
                }
            }
        }
    }
}
