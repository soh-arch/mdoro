import SwiftUI
import MdoroCore

// REQ-UIX-004 / REQ-COM-013: the connection state must be visible at all times.
struct ConnectionBanner: View {
    @Environment(\.theme) private var theme
    @Environment(ClientModel.self) private var model
    @State private var pairingCode = ""

    // REQ-UIX-046: a banner is used **only for a state that needs attention**. When all is well, a dot
    // and a short label are enough.
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
                // REQ-PER-011: while a persisted state is on show, the time it was received is shown alongside it.
                if !model.isConnected, let at = model.snapshotReceivedAt {
                    Text("Last received \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(.footnote)
            .foregroundStyle(theme.color(model.connectionStatus.colorRole, .text))

            // REQ-NTF-011: until a sync has happened it says "syncing", and information that is not
            // settled is not shown as if it were.
            if model.isAwaitingFirstSync {
                Text("Syncing…")
                    .font(.footnote)
                    .foregroundStyle(theme.color(.warning, .text))
            }

            // Do not hide the reason a Live Activity cannot be shown.
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
        // REQ-ERR-014: local network permission being denied gets different wording from not being on Wi-Fi.
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
            // REQ-COM-004: **the reason, and a way out of it.** Once a refusal has arrived nothing
            // is dialling any more, so a refusal that shows no control is exactly the dead end the
            // clause names — the user left waiting without being asked anything. Six digits are the
            // one move this end can make by itself, and `submitPairingCode` re-dials as it sends
            // them, which is also the way back from a Mac that simply did not approve (REQ-SEC-004).
            // **So it is offered for every reason, not for the two whose wording names a code**: a
            // pairing window the user has just been told to open on the Mac, and a registration
            // this Mac no longer knows, both end up here needing precisely this field.
            pairingField
        } else if case let .refused(reason) = model.status {
            // REQ-PRT-004 / REQ-COM-004: **the update, and no field.** Entering a code again cannot
            // mend a version, so offering one would send the user round a loop with no end in it.
            // The sentence is the one 10.2's own code already carries (Decision 0035) — a refusal
            // the app has words for does not get a second wording written for it here.
            Text(reason.protocolErrorCode.displayMessage)
                .font(.callout)
        } else if model.status == .needsPairing {
            Text("Start pairing in Settings on your Mac, then enter the six-digit code it shows.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
            pairingField
        } else if model.servers.count > 1 {
            // REQ-ERR-005: when more than one is found, let the user choose from a list.
            Text("Choose a Mac").font(.footnote).foregroundStyle(theme.textSecondary)
            ForEach(model.servers) { server in
                Button(server.name) { model.connect(to: server) }
                    .font(.footnote)
            }
        } else if model.servers.isEmpty {
            // REQ-ERR-008: do not fall back on a generic connection error.
            Text("Not connected to your Mac")
                .font(.callout.weight(.medium))
            Text("Join the same Wi-Fi network as your Mac.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
    }

    // REQ-SEC-001: the six-digit pairing code is entered here.
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
        case .connectionRejectedByUser: return "Your Mac did not approve the connection"
        }
    }
}

// REQ-UIX-036 / REQ-PER-005: the confirmation on return. While disconnected, it says the confirmation
// has to happen on the Mac.
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
                // REQ-PER-005: while disconnected, the iPhone cannot answer.
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

// REQ-TSK-004: the task list must be viewable and selectable from the iPhone as well.
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
                            // REQ-TSK-014: child tasks are laid out indented.
                            if item.depth > 0 { Spacer().frame(width: CGFloat(item.depth) * 16) }
                            // REQ-COL-010: told apart by shape first, with colour added on top. It is
                            // a shape that carries meaning, so `-graphic`.
                            let isSelected = model.snapshot?.task.selectedTaskId == item.stableId
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected
                                                 ? theme.color(.accentPrimary, .graphic)
                                                 : theme.textTertiary)
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
