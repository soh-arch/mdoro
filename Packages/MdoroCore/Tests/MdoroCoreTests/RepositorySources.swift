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

// **A directory that moved is not a directory with nothing in it.** The recursive branch used
// to answer `[]` when `enumerator` handed back nil, so a scan whose target had been renamed
// passed by finding nothing to object to — which is the one failure these scans exist to
// prevent, arriving through the scans themselves. Renaming `PomodoroMacTests` was enough to
// silence a guard on notifications reaching the reader.
//
// The folders here are the ones Xcode owns and the ones still carrying their pre-Mdoro names
// (工程9 の積み残し). **They will move.** Every caller has to hear about it, so the check is
// on the way in rather than in each of them.
struct MissingSourceDirectory: Error, CustomStringConvertible {
    let path: String
    var description: String { "\(path) is not a directory — it moved, or it was renamed" }
}

// Every .swift under a directory, keyed by file name, comments already stripped.
func swiftFiles(under directory: String, recursive: Bool = false) throws -> [String: String] {
    let base = repositoryRoot.appendingPathComponent(directory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw MissingSourceDirectory(path: directory)
    }
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
