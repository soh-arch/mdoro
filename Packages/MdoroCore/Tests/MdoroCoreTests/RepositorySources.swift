import Foundation

// Some rules this package owns are kept by the app targets, which `swift test` cannot link
// (REQ-COL-001 / 002 is one: the palette lives here, the views that must not bypass it do
// not). Reading their source is how those rules stay checked in CI, and it is the same route
// `MenuBarMarkTests` already takes to the asset catalogue.

// Five levels up from Tests/MdoroCoreTests/ is the repository root.
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

// **A directory that moved is not a directory with nothing in it.** A recursive branch answering
// `[]` when `enumerator` hands back nil lets a scan whose target has been renamed pass by finding
// nothing to object to — which is the one failure these scans exist to prevent, arriving through
// the scans themselves. Renaming `PomodoroMacTests` is enough to silence a guard on notifications
// reaching the reader.
//
// The folders here are the ones Xcode owns and the ones still carrying their pre-Mdoro names
// (left over from stage 9). **They will move.** Every caller has to hear about it, so the check
// is on the way in rather than in each of them.
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

// REQ-UIX-038 / Decision 0022: the scans that keep the words in a String Catalog have to find the
// calls that ask for them, and a scan that looks for the spelling `String(localized: "` finds only
// the ones written on one line. **The call this family exists to catch is a long sentence added
// from an editor that is not Xcode** (`StringCatalogTests`) — and a sentence long enough to be
// worth localising is a sentence that gets wrapped, so the argument sits on the line below. The
// label is matched across whitespace instead of as a fixed spelling; the literal itself is read
// character by character, untouched.
private let localizedCallOpening = "String("
private let localizedCallLabel = "localized:"

private func skipWhitespace(in text: String, from index: inout String.Index) {
    while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
    }
}

// Every `String(localized:)` call in a file, in order, each paired with the literal it was written
// with — `nil` when the argument is not a string literal, so that a caller asking only whether a
// file localises anything sees those too. Escapes are kept as written (`\"` stays two characters):
// the point of comparison is the source, not the resolved string.
func localizedCalls(in text: String) -> [String?] {
    var found: [String?] = []
    var searchFrom = text.startIndex
    while let opening = text.range(of: localizedCallOpening, range: searchFrom..<text.endIndex) {
        // Resume just past this `String(` whether or not it turns out to be the call we want, so a
        // nested one is still reached.
        searchFrom = opening.upperBound
        var index = opening.upperBound
        skipWhitespace(in: text, from: &index)
        guard text[index...].hasPrefix(localizedCallLabel) else { continue }
        index = text.index(index, offsetBy: localizedCallLabel.count)
        skipWhitespace(in: text, from: &index)
        guard index < text.endIndex, text[index] == "\"" else {
            found.append(nil)
            continue
        }
        index = text.index(after: index)
        var literal = ""
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                literal.append(character)
                escaped = false
            } else if character == "\\" {
                literal.append(character)
                escaped = true
            } else if character == "\"" {
                break
            } else {
                literal.append(character)
            }
            index = text.index(after: index)
        }
        found.append(literal)
        // Past the literal, so a `String(localized: "` spelled inside one is not read as a call.
        searchFrom = index
    }
    return found
}

// Every `String(localized: "…")` literal in a file, as written.
func localizedStringLiterals(in text: String) -> [String] {
    localizedCalls(in: text).compactMap { $0 }
}
