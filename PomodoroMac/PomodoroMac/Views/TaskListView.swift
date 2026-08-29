import SwiftUI
import MdoroCore

// REQ-TSK-004: the task list that was loaded must be browsable, and choosable from.
// REQ-TSK-011 / 014: grouped by heading, with child tasks laid out indented.
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
                // REQ-ERR-001: show the reason and a way to choose again. The timer keeps running.
                notice("No task file selected",
                       detail: "Choose a file to watch in Settings.",
                       role: .warning)
            } else if model.tasks.loadFailed {
                // REQ-ERR-002: the error is shown while the list from just before is kept.
                notice("Could not read the task file",
                       detail: "Showing what was read last time.",
                       role: .danger)
            }

            if sections.isEmpty, model.settings.taskFilePath != nil, !model.tasks.loadFailed {
                // REQ-TSK-016: with nothing found, show an example of the notation that is expected.
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
                // REQ-TSK-037 / REQ-ERR-003: show whether the list was cut short, and how many were read.
                Text("Showing the first \(model.tasks.items.count)")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }
            Spacer()

            // REQ-TSK-032: say quietly that the selection followed.
            if model.didFollowTaskSelection {
                Button {
                    model.acknowledgeTaskFollow()
                } label: {
                    Label("Followed the selection", systemImage: "arrow.turn.down.right")
                        .font(.footnote)
                        .foregroundStyle(theme.color(.accentPrimary, .text))
                }
                // REQ-COL-002: `.link` does not accept a colour of our own. **The label is painted here
                // and the button made plain.**
                .buttonStyle(.plain)
            }

            if model.tasks.selectedTaskId != nil {
                // REQ-UIX-047: the size matches `Add`.
                Button { model.clearTaskSelection() } label: {
                    Text("Clear selection")
                        .foregroundStyle(theme.color(.accentPrimary, .text))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: TaskItem) -> some View {
        HStack(spacing: 6) {
            // REQ-TSK-014: child tasks are laid out indented under the parent.
            if item.depth > 0 {
                Spacer().frame(width: CGFloat(item.depth) * 16)
            }
            Image(systemName: item.isCompleted ? "checkmark.square" : "square")
                .foregroundStyle(theme.textTertiary)
            Text(item.displayText)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? theme.textTertiary : theme.textPrimary)
            // REQ-TSK-023: a task that carries a block ID must be tellable from the rest.
            if item.idKind == .blockId {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
                    .help("Has a block ID, so the selection survives edits to the text")
            }
            Spacer()
        }
        // REQ-COL-002 / REQ-UIX-044 / 8.6.3: a selection is shown with a `-subtle` ground.
        // **The fill `List(selection:)` uses does not change with `.tint`.** Drawing it here is the only
        // way to look the colour up by role name.
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

    // REQ-TSK-016: the empty-state note is where the app shows the notation it reads, and a
    // sample nobody can read does not show it. A resolved `String` reaches `Text` verbatim,
    // so the backticks around `- [ ] task` were printed as themselves; the key goes in
    // whole and SwiftUI sets the sample as code, which is what the same kind of line in
    // `SettingsView` already does. The catalogue is still where the words live — a literal
    // in this position is the key Xcode extracts (Decision 0022).
    private func notice(_ title: LocalizedStringKey, detail: LocalizedStringKey, role: ColorRole) -> some View {
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
