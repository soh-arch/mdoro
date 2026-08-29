import Foundation
import MdoroCore

// REQ-PLT-003 / 005: security-scoped bookmarks, so that a file the user chose can be reached under
// the sandbox across a restart.
//
// The one for `Task.md` is created with `securityScopeAllowOnlyReadAccess`.
// If "we do not write" rests on the discipline of the code alone, one day someone breaks it, so
// **a state the OS itself refuses** is made instead (the first principle / Decision 0002).
enum VaultFileAccess {

    enum AccessError: Error, Equatable {
        case bookmarkCreationFailed
        case bookmarkResolutionFailed
        case accessDenied
    }

    // MARK: - Creating a bookmark

    static func readOnlyBookmark(for url: URL) throws -> Data {
        try bookmark(for: url, options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
    }

    static func readWriteBookmark(for url: URL) throws -> Data {
        try bookmark(for: url, options: [.withSecurityScope])
    }

    private static func bookmark(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        // A URL received from the file-choosing dialog already has its scope open at that point.
        do {
            return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw AccessError.bookmarkCreationFailed
        }
    }

    // MARK: - Resolving, and access

    struct Resolved {
        let url: URL
        let isStale: Bool
    }

    static func resolve(_ bookmark: Data) throws -> Resolved {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return Resolved(url: url, isStale: isStale)
        } catch {
            throw AccessError.bookmarkResolutionFailed
        }
    }

    // REQ-PLT-005: `startAccessingSecurityScopedResource()` and `stop...` are always called as a pair.
    //
    // Fail to pair them and the resource on the kernel side is never released, until in the end
    // nothing can be accessed. To keep a forgotten call out by construction, the URL is never carried
    // outside this function to be accessed.
    static func withAccess<T>(to bookmark: Data, perform work: (URL) throws -> T) throws -> T {
        let resolved = try resolve(bookmark)
        guard resolved.url.startAccessingSecurityScopedResource() else {
            throw AccessError.accessDenied
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }
        return try work(resolved.url)
    }

    // Where access has to be held open — watching, for one — the caller holds the start and the end.
    // Even then, `stop` must be paired with it, in deinit or somewhere like it.
    static func beginAccess(to bookmark: Data) throws -> URL {
        let resolved = try resolve(bookmark)
        guard resolved.url.startAccessingSecurityScopedResource() else {
            throw AccessError.accessDenied
        }
        return resolved.url
    }

    static func endAccess(to url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

// REQ-ERR-010 / Decision 0034: this failure never came from the OS, but the diagnostic log
// must not show that. Same shape, same domain rule, a code fixed per case.
extension VaultFileAccess.AccessError: ReportableError {

    var errorCode: ErrorCode {
        switch self {
        case .bookmarkCreationFailed: .bookmarkCreationFailed
        case .bookmarkResolutionFailed: .bookmarkResolutionFailed
        case .accessDenied: .accessDenied
        }
    }

    var diagnosticSummary: String { errorCode.summary(caseName) }

    private var caseName: String {
        switch self {
        case .bookmarkCreationFailed: "bookmarkCreationFailed"
        case .bookmarkResolutionFailed: "bookmarkResolutionFailed"
        case .accessDenied: "accessDenied"
        }
    }

    // A bookmark goes bad when the folder moves or is removed, so every sentence points
    // the user back at the chooser rather than at a retry.
    //
    // Decision 0034 keeps the sentence beside the case; Decision 0022 keeps it in the
    // catalogue. **Both hold here because this failure lives in the app target.** The same
    // sentences in MdoroCore stay literals — a package has no catalogue to put them in.
    var displayMessage: String {
        switch self {
        case .bookmarkCreationFailed:
            String(localized: "Mdoro was not given access to that folder. Choose it again in Settings.")
        case .bookmarkResolutionFailed:
            String(localized: "The folder Mdoro was given access to can no longer be found. Choose it again in Settings.")
        case .accessDenied:
            String(localized: "Mdoro is no longer allowed into that folder. Choose it again in Settings.")
        }
    }
}

// Where the bookmarks are kept. AppSettings holds the paths for display, but this is the only thing
// that can actually reach the files.
struct VaultBookmarks: Codable, Equatable, Sendable {
    var taskFile: Data?
    // Decision 0015: on the log side the bookmark is for a **folder**.
    // With permission for a single file, the temporary file an atomic write needs cannot be created in
    // the same place.
    var logFolder: Data?

    static let storageKey = "vaultBookmarks"

    static func load(from defaults: UserDefaults = .standard) -> VaultBookmarks {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(VaultBookmarks.self, from: data) else {
            return VaultBookmarks()
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
