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
                notice("Task.md が選ばれていません", detail: "設定で監視するファイルを選んでください。", role: .warning)
            } else if model.tasks.loadFailed {
                // REQ-ERR-002: 直前に成功した一覧を保持したままエラーを示す。
                notice("Task.md を読み込めませんでした", detail: "前回読み込んだ内容を表示しています。", role: .danger)
            }

            if sections.isEmpty, model.settings.taskFilePath != nil, !model.tasks.loadFailed {
                // REQ-TSK-016: 0件のときは想定している記法の例を示す。
                notice("タスクが見つかりません",
                       detail: "`- [ ] タスク名` の形式の行を読み取ります。見出し（##）ごとにまとまります。",
                       role: .warning)
            }

            List(selection: selectionBinding) {
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
            Text("タスク").font(.headline).foregroundStyle(theme.textPrimary)

            if model.tasks.wasTruncated {
                // REQ-TSK-037 / REQ-ERR-003: 打ち切りの有無と読み込んだ件数を示す。
                Text("先頭 \(model.tasks.items.count) 件のみ表示")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
            Spacer()

            // REQ-TSK-032: 追従が発生したことを控えめに知らせる。
            if model.didFollowTaskSelection {
                Button {
                    model.acknowledgeTaskFollow()
                } label: {
                    Label("選択を追従しました", systemImage: "arrow.turn.down.right")
                        .font(.footnote)
                }
                .buttonStyle(.link)
            }

            if model.tasks.selectedTaskId != nil {
                Button("選択を解除") { model.clearTaskSelection() }
                    .buttonStyle(.link)
                    .font(.footnote)
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.tasks.selectedTaskId },
            set: { if let id = $0 { model.selectTask(id: id) } }
        )
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
                    .help("ブロック ID があるため、文言を直しても選択が維持されます")
            }
            Spacer()
        }
        .tag(item.stableId)
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
