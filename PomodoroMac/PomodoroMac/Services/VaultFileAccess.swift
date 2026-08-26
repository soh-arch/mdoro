import Foundation
import PomodoroCore

// REQ-PLT-003 / 005: サンドボックス下でユーザーが選んだファイルへ、再起動をまたいで到達するための
// セキュリティスコープ付きブックマーク。
//
// `Task.md` 側は `securityScopeAllowOnlyReadAccess` を付けて生成する。
// 「書き込まない」をコードの規律だけで担保するといつか誰かが破るため、**OS が拒否する状態を作る**
// （3原則の1つ目 / Decision 0002）。
enum VaultFileAccess {

    enum AccessError: Error, Equatable {
        case bookmarkCreationFailed
        case bookmarkResolutionFailed
        case accessDenied
    }

    // MARK: - ブックマークの生成

    static func readOnlyBookmark(for url: URL) throws -> Data {
        try bookmark(for: url, options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
    }

    static func readWriteBookmark(for url: URL) throws -> Data {
        try bookmark(for: url, options: [.withSecurityScope])
    }

    private static func bookmark(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        // ファイル選択ダイアログから受け取った URL は、その時点でスコープが開いている。
        do {
            return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw AccessError.bookmarkCreationFailed
        }
    }

    // MARK: - 解決とアクセス

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

    // REQ-PLT-005: `startAccessingSecurityScopedResource()` と `stop...` を必ず対で呼ぶ。
    //
    // 対にし損ねるとカーネル側のリソースが解放されず、いずれアクセスできなくなる。
    // 呼び忘れを構造的に防ぐため、この関数の外へ URL を持ち出してアクセスしない。
    static func withAccess<T>(to bookmark: Data, perform work: (URL) throws -> T) throws -> T {
        let resolved = try resolve(bookmark)
        guard resolved.url.startAccessingSecurityScopedResource() else {
            throw AccessError.accessDenied
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }
        return try work(resolved.url)
    }

    // 監視のようにアクセスを継続したい用途では、開始と終了を呼び出し側が持つ。
    // その場合も `stop` を deinit などで必ず対にすること。
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

// ブックマークの保管。パスは表示用に AppSettings が持つが、実際に到達できるのはこちらだけ。
struct VaultBookmarks: Codable, Equatable, Sendable {
    var taskFile: Data?
    // Decision 0015: ログ側は**フォルダ**のブックマーク。
    // ファイル単位の許可では、原子的書き込みに要る一時ファイルを同じ場所に作れない。
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
