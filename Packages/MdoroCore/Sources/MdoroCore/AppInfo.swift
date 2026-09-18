import Foundation

// REQ-UIX-047 / REQ-PRT-001: the one source both platforms' About sections read, so they show
// the same words in the same order.
public enum AppInfo {
    public static let name = "Mdoro"
    public static let tagline = "A focus timer for Markdown task files. Mac and iPhone, over your LAN only."
    public static let license = "MIT"

    // REQ-NFR-008 / Decision 0044: one support link, in the Mac's About, and nowhere else in the
    // app. The label to show is held separately from the URL.
    public static let supportURL = URL(string: "https://buymeacoffee.com/soh.arch")!
    public static let supportLabel = "buymeacoffee.com/soh.arch"

    // Decision 0021: distribution is building from source, nothing else.
    public static let sourceURL = URL(string: "https://github.com/soh-arch/mdoro")!
    public static let sourceLabel = "github.com/soh-arch/mdoro"

    public static func version(_ bundle: Bundle = .main) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = bundle.infoDictionary?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}
