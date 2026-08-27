import SwiftUI
import MdoroCore

// REQ-UIX-007: 有効なプリセット名を常時表示し、2件以上なら2タップ以内で切り替えられること。
// 設定画面を経由させない。
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
                // 1タップでメニュー、もう1タップで選択。
                Menu {
                    ForEach(presets) { preset in
                        Button {
                            model.send(.selectPreset(id: preset.id))
                        } label: {
                            // REQ-UIX-008: 時間構成を併記する。
                            Text("\(preset.name)（\(Format.presetShape(preset))）")
                        }
                    }
                } label: {
                    Text("\(active.name)（\(Format.presetShape(active))）")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                // REQ-PRS-013: 1件のときは切替 UI を出さず「追加」への導線にする。
                Text("\(active.name)（\(Format.presetShape(active))）")
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
