import Foundation

// アプリの自己紹介。両端末の About 節が同じ文言・同じ並びを使うための唯一の出典
// （REQ-UIX-047、REQ-PRT-001）。
public enum AppInfo {
    public static let name = "Mdoro"
    public static let tagline = "A focus timer for Markdown task files. Mac and iPhone, over your LAN only."
    public static let license = "MIT"

    // REQ-NFR-008 / decisions/0021: 支援リンクは About に1つだけ置く。
    // 開く前にリンク先を画面へ出すため、表示用の文字列を URL とは別に持つ。
    public static let supportURL = URL(string: "https://buymeacoffee.com/soh.arch")!
    public static let supportLabel = "buymeacoffee.com/soh.arch"

    // 配布はソースからのビルドのみ（decisions/0021）。About から取りに行ける場所を示す。
    public static let sourceURL = URL(string: "https://github.com/soh-arch/mdoro")!
    public static let sourceLabel = "github.com/soh-arch/mdoro"

    public static func version(_ bundle: Bundle = .main) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = bundle.infoDictionary?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}
