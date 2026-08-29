import SwiftUI
import MdoroCore

// REQ-SEC-001: 初回接続時は Mac 画面に6桁のペアリングコードを表示し、iPhone に入力させる。
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
                    // REQ-SEC-003: 3分間のみ有効。残り時間を出さないと失効の理由が分からない。
                    Text("Enter this code in the iPhone app (\(model.pairingRemainingSeconds) s left)")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                    Button("Stop pairing") { model.endPairing() }
                }
            } else {
                HStack {
                    Text(Format.connectionLabel(model.connection))
                    Spacer()
                    Button("Start pairing") { model.beginPairing() }
                }
                Text("Pairing stays open for three minutes. Five wrong codes end it.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            if let error = model.serverStartError {
                // REQ-SEC-005 / REQ-ERR-014: 待ち受けられない事実を隠さない。
                // REQ-ERR-010 / Decision 0034: the model hands over a finished sentence.
                // The reason is no longer here — it is a code in the diagnostic log.
                // REQ-COL-001 / 002: the role, not the hue. `danger` is the hue this line
                // already had — nothing can be listened on, so the iPhone cannot connect at all.
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(theme.color(.danger, .text))
                Text("Check that this app is allowed in System Settings > Privacy & Security > Local Network.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    // 3桁ずつに割ると読み上げやすい。
    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }
}

// REQ-SEC-004: 接続中に新たな要求が来たら確認を出し、承認された場合のみ受け入れる。
// **確認は60秒でタイムアウトし、既定は拒否。**
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
