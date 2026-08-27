import SwiftUI
import MdoroCore

// REQ-TSK-004: 読み込まれたタスク一覧を閲覧・選択できること。
// REQ-TSK-011 / 014: 見出しごとにグループ化し、子タスクは字下げして並べる。
struct TaskListView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    private var sections: [TaskSection] {
        model.tasks.grouped(showCompleted: model.settings.showCompletedTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if model.settings.taskFilePath == nil {
                // REQ-ERR-001: タスク欄に理由と再選択導線を表示する。タイマー機能は継続する。
                notice("No task file selected", detail: "Choose a file to watch in Settings.", role: .warning)
            } else if model.tasks.loadFailed {
                // REQ-ERR-002: 直前に成功した一覧を保持したままエラーを示す。
                notice("Could not read the task file", detail: "Showing what was read last time.", role: .danger)
            }

            if sections.isEmpty, model.settings.taskFilePath != nil, !model.tasks.loadFailed {
                // REQ-TSK-016: 0件のときは想定している記法の例を示す。
                notice("No tasks found",
                       detail: "Reads lines written as `- [ ] task`. Headings (##) group them.",
                       role: .warning)
            }

            List {
                ForEach(sections) { section in
                    Section(section.name) {
                        ForEach(section.items) { item in
                            row(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 160)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tasks").font(.headline).foregroundStyle(theme.textPrimary)

            if model.tasks.wasTruncated {
                // REQ-TSK-037 / REQ-ERR-003: 打ち切りの有無と読み込んだ件数を示す。
                Text("Showing the first \(model.tasks.items.count)")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
            Spacer()

            // REQ-TSK-032: 追従が発生したことを控えめに知らせる。
            if model.didFollowTaskSelection {
                Button {
                    model.acknowledgeTaskFollow()
                } label: {
                    Label("Followed the selection", systemImage: "arrow.turn.down.right")
                        .font(.footnote)
                        .foregroundStyle(theme.color(.accentPrimary, .text))
                }
                // REQ-COL-002: `.link` スタイルは自前の色を受け付けない（`.tint` も効かない）。
                // **ラベルを自分で塗り、素のボタンにする。**
                .buttonStyle(.plain)
            }

            if model.tasks.selectedTaskId != nil {
                Button { model.clearTaskSelection() } label: {
                    Text("Clear selection")
                        .font(.footnote)
                        .foregroundStyle(theme.color(.accentPrimary, .text))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: TaskItem) -> some View {
        HStack(spacing: 6) {
            // REQ-TSK-014: 子タスクは親の下に字下げして並べる。
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 16)
            }
            Image(systemName: item.isCompleted ? "checkmark.square" : "square")
                .foregroundStyle(theme.textTertiary)
            Text(item.displayText)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? theme.textTertiary : theme.textPrimary)
            // REQ-TSK-023: ブロック ID を持つタスクを識別できるようにする。
            if item.idKind == .blockId {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
                    .help("Has a block ID, so the selection survives edits to the text")
            }
            Spacer()
        }
        // REQ-COL-002 / REQ-UIX-044 / 8.6.3: 選択は `-subtle` の地で示す。
        //
        // **`List(selection:)` の塗りは `.tint` では変わらない。** macOS のリストは
        // システムのハイライト色を使う。役割名から引くには、自分で描くしかない
        // （2026-08-28、実機で確認。前回 `.tint` を当てて直らなかった）。
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.stableId == model.tasks.selectedTaskId
                      ? theme.color(.accentPrimary, .subtle)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectTask(id: item.stableId) }
        .listRowSeparator(.hidden)
    }

    private func notice(_ title: String, detail: String, role: ColorRole) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.footnote)
        }
        .foregroundStyle(theme.color(role, .text))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(role, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.color(role, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
