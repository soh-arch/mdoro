import Foundation
import Observation
import MdoroCore

// REQ-ERR-010 / Decision 0018: the way in to the diagnostic log.
//
// **No string that came from the user is passed in here.** A task is identified by the last four
// digits of its `stableId`, a file by a digest of its path.
// It lives in `<Library>/Logs/Mdoro/`. Plain text, one event per line.
@MainActor
@Observable
final class DiagnosticLog {

    // That the log itself cannot be written is not kept quiet either.
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

    // Only the turning points of the state are recorded. At that volume it may be written
    // synchronously, and a failure can be picked up on the spot.
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
