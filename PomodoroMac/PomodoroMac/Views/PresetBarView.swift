import SwiftUI
import MdoroCore

// REQ-UIX-007: the name of the active preset is shown at all times, and with two or more it must be
// switchable within two taps.
struct PresetBarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    private var presets: [Preset] { model.presets.presets }
    private var active: Preset { model.presets.activePreset ?? Preset.standard() }

    var body: some View {
        HStack(spacing: 8) {
            Text("Preset")
                .font(.footnote)
                .foregroundStyle(theme.textTertiary)

            if presets.count >= 2 {
                Menu {
                    ForEach(presets) { preset in
                        Button {
                            model.send(.selectPreset(id: preset.id))
                        } label: {
                            // REQ-UIX-008: the shape of the times is written alongside.
                            Text("\(preset.name) (\(Format.presetShape(preset)))")
                        }
                    }
                } label: {
                    Text("\(active.name) (\(Format.presetShape(active)))")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                // REQ-PRS-013: with only one, no switcher is shown; it becomes the way through to "Add".
                Text("\(active.name) (\(Format.presetShape(active)))")
                    .foregroundStyle(theme.textPrimary)
                SettingsLink {
                    Text("Add").foregroundStyle(theme.color(.accentPrimary, .text))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .font(.callout)
    }
}
