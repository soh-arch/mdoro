import Foundation

// REQ-UIX-047 / REQ-PRT-001: 両端末の About 節が同じ文言・同じ並びを使うための唯一の出典。
public enum AppInfo {
    public static let name = "Mdoro"
    public static let tagline = "A focus timer for Markdown task files. Mac and iPhone, over your LAN only."
    public static let license = "MIT"

    // REQ-NFR-008 / Decision 0021: 支援リンクは About に1つだけ。表示用の文字列を URL とは別に持つ。
    public static let supportURL = URL(string: "https://buymeacoffee.com/soh.arch")!
    public static let supportLabel = "buymeacoffee.com/soh.arch"

    // Decision 0021: 配布はソースからのビルドのみ。
    public static let sourceURL = URL(string: "https://github.com/soh-arch/mdoro")!
    public static let sourceLabel = "github.com/soh-arch/mdoro"

    public static func version(_ bundle: Bundle = .main) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = bundle.infoDictionary?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}
