import Foundation
import Observation
import MdoroCore

// REQ-ERR-010 / Decision 0018: 診断ログの入り口。
//
// **利用者由来の文字列をここへ渡さないこと。** タスクは `stableId` の下4桁、
// ファイルはパスのダイジェストで同定する。伏字処理を持たないことが要点で、
// 持たなければ、そこにバグが入る余地もない。
//
// 置き場所は `~/Library/Logs/Pomodoro/`（サンドボックスではコンテナ内の同じ位置）。
// `tail -f` できる、1行1イベントのプレーンテキスト。
@MainActor
@Observable
final class DiagnosticLog {

    // ログ自体が書けないことも黙らせない（CONTEXT「失敗を黙らせない」）。
    private(set) var lastFailure: String?

    @ObservationIgnored private var file: DiagnosticLogFile?

    static let directory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Mdoro", isDirectory: true)
    }()

    func open(preset: Preset, settings: AppSettings) {
        file = DiagnosticLogFile(
            directory: Self.directory,
            header: DiagnosticHeader(
                appVersion: Self.bundleValue("CFBundleShortVersionString"),
                build: Self.bundleValue("CFBundleVersion"),
                osVersion: Self.osVersion,
                architecture: Self.architecture,
                settings: DiagnosticHeader.settingsFields(preset: preset, settings: settings)
            )
        )
    }

    // 記録するのは状態の変わり目だけで、毎秒の刻みは載せない。
    // その量なら同期で書いて差し支えなく、失敗をその場で拾えるぶん素直になる。
    func write(_ code: String, level: DiagnosticLevel = .info, _ fields: [DiagnosticField] = []) {
        guard let file else { return }
        file.write(DiagnosticEvent(level: level, code: code, fields: fields))
        lastFailure = file.lastFailure
    }

    func exportedText() -> String { file?.exportedText() ?? "" }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
