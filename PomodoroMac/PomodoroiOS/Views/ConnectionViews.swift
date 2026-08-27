import SwiftUI
import MdoroCore

// REQ-UIX-004 / REQ-COM-013: 接続状態を常時視認できること。
// 切断中は「Mac に接続していません」と明示する。
struct ConnectionBanner: View {
    @Environment(\.theme) private var theme
    @Environment(ClientModel.self) private var model
    @State private var pairingCode = ""

    // REQ-UIX-046: 帯は**注意を要する状態にだけ**使う。
    // 正常につながっているあいだ「問題ありません」と全幅で言う要素を置かない。
    // REQ-UIX-004 は、点と短いラベルで満たす。
    private var needsAttention: Bool {
        !model.isConnected || model.isAwaitingFirstSync || model.liveActivityProblem != nil
    }

    var body: some View {
        if needsAttention {
            banner
        } else {
            statusMark
        }
    }

    private var statusMark: some View {
        HStack(spacing: 8) {
            Image(systemName: model.connectionStatus.peerSymbolName)
            Text(Format.connectionLabel(model.connectionStatus))
        }
        .font(.footnote)
        .foregroundStyle(theme.color(model.connectionStatus.colorRole, .text))
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: model.connectionStatus.peerSymbolName)
                Text(Format.connectionLabel(model.connectionStatus))
                Spacer()
                // REQ-PER-011: 永続化された状態を出しているあいだは取得時刻を併記する。
                if !model.isConnected, let at = model.snapshotReceivedAt {
                    Text("Last received \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(.footnote)
            .foregroundStyle(theme.color(model.connectionStatus.colorRole, .text))

            // REQ-NTF-011: 同期が取れるまで「同期中」と示し、確定していない情報を断定的に見せない。
            if model.isAwaitingFirstSync {
                Text("Syncing…")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }

            // Live Activity が出せない理由は隠さない。正常なら何も出さない。
            if let problem = model.liveActivityProblem {
                Text("Live Activity: \(problem)")
                    .font(.caption)
                    .foregroundStyle(theme.color(.warning, .text))
                    .textSelection(.enabled)
            }

            if !model.isConnected {
                notice
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(model.connectionStatus.colorRole, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(model.connectionStatus.colorRole, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var notice: some View {
        // REQ-ERR-014: ローカルネットワーク許可の拒否は、Wi-Fi 未接続とは別の文言にする。
        if model.localNetworkDenied {
            Text("Local network access is not allowed")
                .font(.callout.weight(.medium))
            Text("Allow this app in Settings > Privacy & Security > Local Network.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
            Button("Open Settings") { openSettings() }
                .font(.footnote)
        } else if case let .failed(code) = model.status {
            Text(Self.message(for: code))
                .font(.callout)
            if code == .invalidPairingCode || code == .pairingAttemptsExceeded {
                pairingField
            }
        } else if model.status == .needsPairing {
            Text("Start pairing in Settings on your Mac, then enter the six-digit code it shows.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
            pairingField
        } else if model.servers.count > 1 {
            // REQ-ERR-005: 複数見つかったら一覧から選ばせる。
            Text("Choose a Mac").font(.footnote).foregroundStyle(theme.textSecondary)
            ForEach(model.servers) { server in
                Button(server.name) { model.connect(to: server) }
                    .font(.footnote)
            }
        } else if model.servers.isEmpty {
            // REQ-ERR-008: 汎用的な接続エラーにしない。
            Text("Not connected to your Mac")
                .font(.callout.weight(.medium))
            Text("Join the same Wi-Fi network as your Mac.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
    }

    // REQ-SEC-001: 6桁のペアリングコードを入力させる。
    private var pairingField: some View {
        HStack {
            TextField("Six-digit code", text: $pairingCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            Button("Connect") {
                model.submitPairingCode(pairingCode)
                pairingCode = ""
            }
            .disabled(pairingCode.count != 6)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func message(for code: AuthFailureCode) -> LocalizedStringKey {
        switch code {
        case .invalidPairingCode: return "That code is not correct"
        case .pairingModeNotActive: return "Start pairing on your Mac"
        case .pairingAttemptsExceeded: return "Five wrong codes. Start pairing again on your Mac"
        case .unknownDeviceToken: return "This device is no longer registered. Pair again"
        case .anotherClientConnected: return "Another device is connected"
        case .connectionRejectedByUser: return "Your Mac did not approve the connection"
        }
    }
}

// REQ-UIX-036 / REQ-PER-005: 復帰時の確認。切断中は Mac 側で確認が必要である旨を出す。
struct PendingDecisionCard: View {
    @Environment(\.theme) private var theme
    @Environment(ClientModel.self) private var model
    let pending: PendingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "questionmark.circle")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text(detail).font(.callout).foregroundStyle(theme.textSecondary)

            if model.isConnected {
                HStack(spacing: 8) {
                    if pending.reason == .pausedTooLong {
                        Button("Resume it") {
                            model.send(.confirmRestoredSession, params: CommandParams(decision: .resume))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Record as completed") {
                        model.send(.confirmRestoredSession, params: CommandParams(decision: .complete))
                    }
                    Button("Record as stopped") {
                        model.send(.confirmRestoredSession, params: CommandParams(decision: .discard))
                    }
                }
                .buttonStyle(.bordered)
            } else {
                // REQ-PER-005: 切断中は iPhone から応答できない。
                Text("Your Mac needs a decision")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: LocalizedStringKey {
        pending.reason == .restoredAfterEnd ? "The session had already ended" : "A long pause was detected"
    }

    private var detail: LocalizedStringKey {
        let minutes = pending.elapsedSeconds / 60
        return "actual \(minutes) min"
    }
}

// REQ-TSK-004: タスク一覧を iPhone からも閲覧・選択できること。
struct TaskListSectionView: View {
    @Environment(\.theme) private var theme
    @Environment(ClientModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks").font(.headline).foregroundStyle(theme.textPrimary)
                if model.taskList?.isTruncated == true {
                    // REQ-TSK-037
                    Text("First \(model.taskList?.itemCount ?? 0) only")
                        .font(.footnote)
                        .foregroundStyle(theme.color(.warning, .text))
                }
                Spacer()
            }

            if let error = model.taskList?.parseError {
                Text(error).font(.footnote).foregroundStyle(theme.color(.danger, .text))
            }

            let sections = model.taskList?.sections ?? []
            if sections.isEmpty {
                // REQ-TSK-016
                Text("No tasks found")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            ForEach(sections, id: \.name) { section in
                Text(section.name).font(.subheadline).foregroundStyle(theme.textTertiary)
                ForEach(section.items) { item in
                    Button {
                        model.send(.selectTask, params: CommandParams(stableId: item.stableId))
                    } label: {
                        HStack(spacing: 8) {
                            // REQ-TSK-014: 子タスクは字下げして並べる。
                            if item.depth > 0 { Spacer().frame(width: CGFloat(item.depth) * 16) }
                            Image(systemName: model.snapshot?.task.selectedTaskId == item.stableId
                                  ? "largecircle.fill.circle" : "circle")
                            Text(item.displayText)
                                .foregroundStyle(theme.textPrimary)
                            // REQ-TSK-023
                            if item.idKind == .blockId {
                                Image(systemName: "link").font(.caption2).foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isConnected)
                }
            }
        }
    }
}
