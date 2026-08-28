import Foundation
import Observation
import MdoroCore

// REQ-ERR-010 / Decision 0018: 診断ログの入り口。
//
// **利用者由来の文字列をここへ渡さないこと。** タスクは `stableId` の下4桁、
// ファイルはパスのダイジェストで同定する。
// 置き場所は `<Library>/Logs/Mdoro/`。1行1イベントのプレーンテキスト。
@MainActor
@Observable
final class DiagnosticLog {

    // ログ自体が書けないことも黙らせない。
    // REQ-ERR-010 / Decision 0035: this code's only reader is the settings screen.
    private(set) var lastFailure: ErrorCode?

    @ObservationIgnored private var file: DiagnosticLogFile?

    static let defaultDirectory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Mdoro", isDirectory: true)
    }()

    // Where this log writes, and what the settings screen points the user at. A parameter so
    // a test can read back what was written without touching the log the user collects.
    let directory: URL

    init(directory: URL = DiagnosticLog.defaultDirectory) {
        self.directory = directory
    }

    func open(preset: Preset, settings: AppSettings) {
        file = DiagnosticLogFile(
            directory: directory,
            header: DiagnosticHeader(
                appVersion: Self.bundleValue("CFBundleShortVersionString"),
                build: Self.bundleValue("CFBundleVersion"),
                osVersion: Self.osVersion,
                architecture: Self.architecture,
                settings: DiagnosticHeader.settingsFields(preset: preset, settings: settings)
            )
        )
    }

    // 記録するのは状態の変わり目だけ。その量なら同期で書いてよく、失敗をその場で拾える。
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
