import SwiftUI
import MdoroCore

// REQ-SEC-001: on the first connection the Mac screen shows a six-digit pairing code, and the iPhone
// is where it is typed in.
struct PairingSection: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("iPhone connection") {
            if let code = model.pairingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formatted(code))
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                        .textSelection(.enabled)
                    // REQ-SEC-003: valid for three minutes only. Without the remaining time on show,
                    // there is no telling why it expired.
                    Text("Enter this code in the iPhone app (\(model.pairingRemainingSeconds) s left)")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                    Button("Stop pairing") { model.endPairing() }
                }
            } else {
                HStack {
                    // REQ-UIX-004 (v2.25): with nothing paired there is no connection state to
                    // speak of, here included — "Not connected" is not the name of a Mac that
                    // has never had anything to connect to.
                    if model.showsConnectionState {
                        Text(Format.connectionLabel(model.connection))
                    }
                    Spacer()
                    Button("Start pairing") { model.beginPairing() }
                }
                Text("Pairing stays open for three minutes. Five wrong codes end it.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            if let error = model.serverStartError {
                // REQ-SEC-005 / REQ-ERR-014: the fact that it cannot listen is not hidden.
                // REQ-ERR-010 / Decision 0034: the model hands over a finished sentence.
                // The reason is no longer here — it is a code in the diagnostic log.
                // REQ-COL-001 / 002: the role, not the hue. `danger` is the hue this line
                // already had — nothing can be listened on, so the iPhone cannot connect at all.
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(theme.color(.danger, .text))
                // REQ-COM-003 (v2.26): what to do about it is the model's to say. The local
                // network permission is the answer to one of the two failures that reach this
                // line and not to the other, and only the model knows which one this is.
                if let hint = model.serverStartHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    // Split into threes, it is easier to read out.
    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }
}

// REQ-SEC-004: a new request arriving while connected raises a confirmation, and it is accepted only
// on approval.
// **The confirmation times out after 60 seconds, and the default is to refuse.**
struct ConnectionRequestBanner: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(deviceName) is trying to connect", systemImage: "iphone.gen3.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text("The connected device will be disconnected. Denied automatically after 60 seconds.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 10) {
                Button("Allow") { model.respondToConnectionRequest(approved: true) }
                    .buttonStyle(.borderedProminent)
                Button("Deny") { model.respondToConnectionRequest(approved: false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
