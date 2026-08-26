import SwiftUI
import PomodoroCore

// REQ-SEC-001: 初回接続時は Mac 画面に6桁のペアリングコードを表示し、iPhone に入力させる。
struct PairingSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("iPhone との接続") {
            if let code = model.pairingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formatted(code))
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                        .textSelection(.enabled)
                    // REQ-SEC-003: 3分間のみ有効。残り時間を出さないと、
                    // 入力している最中に失効しても理由が分からない。
                    Text("iPhone のアプリでこのコードを入力してください（残り \(model.pairingRemainingSeconds) 秒）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("ペアリングをやめる") { model.endPairing() }
                }
            } else {
                HStack {
                    Text(model.connection.label)
                    Spacer()
                    Button("ペアリングを開始") { model.beginPairing() }
                }
                Text("ペアリングは開始してから3分間だけ有効です。コードを5回間違えると終了します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = model.serverStartError {
                // REQ-SEC-005 / REQ-ERR-014: 待ち受けられない事実と理由を隠さない。
                Text("接続を待ち受けられません: \(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Text("「システム設定 > プライバシーとセキュリティ > ローカルネットワーク」で、このアプリが許可されているか確認してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 6桁は3桁ずつに割ると読み上げやすく、入力の取り違えが減る。
    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }
}

// REQ-SEC-004: 既に別のクライアントが接続中の状態で新たな接続要求があった場合、
// Mac 側に確認を表示し、ユーザーが承認した場合のみ受け入れる。
// **確認は60秒でタイムアウトし、既定は拒否。**
struct ConnectionRequestBanner: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(deviceName) が接続しようとしています", systemImage: "iphone.gen3.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(theme.color(.warning, .text))
            Text("接続中の端末は切断されます。60秒で自動的に拒否します。")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 10) {
                Button("許可") { model.respondToConnectionRequest(approved: true) }
                    .buttonStyle(.borderedProminent)
                Button("拒否") { model.respondToConnectionRequest(approved: false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.warning, .subtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.color(.warning, .line)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
