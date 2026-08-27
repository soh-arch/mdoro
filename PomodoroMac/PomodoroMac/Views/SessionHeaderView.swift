import SwiftUI
import MdoroCore

// REQ-UIX-002 / 003 / 013: セッション種別を色と文言の両方で示し、周回数を n / interval で表示する。
// REQ-COL-011: セッション状態に使えるのは -graphic と -text のみ。バナー表現（-subtle + -line）は
// warning に予約されているため、ここでは使わない。ColorRole が型で拒否する。
struct SessionHeaderView: View {
    @Environment(\.theme) private var theme
    let sessionType: SessionType
    let runState: RunState
    let loopDisplay: Int
    let longBreakInterval: Int

    private var role: ColorRole { sessionType.colorRole }

    var body: some View {
        HStack(spacing: 10) {
            // REQ-COL-013: 色に加えて線種でも区別する。色だけに頼らせない（REQ-COL-010）。
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

            // REQ-UIX-003: 次が長い休憩であることが事前にわかるようにする。
            Text("\(loopDisplay) / \(longBreakInterval)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("Loop \(loopDisplay) of \(longBreakInterval)")
        }
    }
}

// REQ-COL-013: Focus は実線、短い休憩は細い実線、長い休憩は二重線。
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
