import Foundation

// Some rules this package owns are kept by the app targets, which `swift test` cannot link
// (REQ-COL-001 / 002 is one: the palette lives here, the views that must not bypass it do
// not). Reading their source is how those rules stay checked in CI, and it is the same route
// `MenuBarMarkTests` already takes to the asset catalogue.

// Tests/MdoroCoreTests/ から5つ上がリポジトリのルート。
var repositoryRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url
}

func source(_ path: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
}

// A comment is exactly where a token can sit without doing anything, and these tests are
// about what the code does, so comments come out before any of them looks.
func withoutComments(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> Substring in
            guard let marker = line.range(of: "//") else { return line }
            return line[line.startIndex..<marker.lowerBound]
        }
        .joined(separator: "\n")
}

// Every .swift under a directory, keyed by file name, comments already stripped.
func swiftFiles(under directory: String, recursive: Bool = false) throws -> [String: String] {
    let base = repositoryRoot.appendingPathComponent(directory)
    let names: [String]
    if recursive {
        names = FileManager.default.enumerator(atPath: base.path)?
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
    } else {
        names = try FileManager.default.contentsOfDirectory(atPath: base.path).filter { $0.hasSuffix(".swift") }
    }
    return try names.reduce(into: [:]) { result, name in
        result[URL(fileURLWithPath: name).lastPathComponent] =
            withoutComments(try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8))
    }
}
