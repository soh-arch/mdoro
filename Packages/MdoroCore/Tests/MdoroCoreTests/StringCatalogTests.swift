import Testing
import Foundation

// The tools for reading the repository's own sources live in `RepositorySources.swift`.
//
// Decision 0022 keeps the String Catalog for a reason that outlives the one language:
// **to keep string literals from being scattered through the code.** Nothing in a build
// enforces that. `xcodebuild` writes .stringsdata and never writes back to the .xcstrings —
// but Xcode does, on every build, from outside the build's own task graph, and so does
// `xcstringstool sync` when someone runs it (`docs/PLATFORM.md`). **So what these catch is not
// a catalogue no tool can update; it is a change written without opening Xcode and pushed with
// the catalogue as it was.** CI runs `swift test` and opens no Xcode, so it never repairs one
// either.
//
// And a lookup that finds no catalogue returns the key — which, in an English-only app, looks
// exactly right on screen. So the two ways it goes wrong are both silent, and both are checked
// here.

private struct AppTarget {
    let folder: String
    var catalogue: String { folder + "/Localizable.xcstrings" }
}

private let appTargets = [
    AppTarget(folder: "PomodoroMac/PomodoroMac"),
    AppTarget(folder: "PomodoroMac/PomodoroiOS"),
    AppTarget(folder: "PomodoroMac/PomodoroWidget"),
]

private func catalogueKeys(_ path: String) throws -> Set<String> {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = root?["strings"] as? [String: Any]
    return Set(strings?.keys ?? [:].keys)
}

private func sourceLanguage(_ path: String) throws -> String? {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["sourceLanguage"] as? String
}

// Every `String(localized: "…")` in a file, as written. Interpolated ones are left out: the
// key Xcode extracts for those depends on the type of each interpolation (`%@` / `%lld` / …),
// which is not in the text. A literal with no interpolation is its own key exactly.
private func plainLocalizedLiterals(in text: String) -> [String] {
    var found: [String] = []
    var rest = Substring(text)
    while let call = rest.range(of: "String(localized: \"") {
        rest = rest[call.upperBound...]
        var literal = ""
        var index = rest.startIndex
        var escaped = false
        while index < rest.endIndex {
            let character = rest[index]
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
            index = rest.index(after: index)
        }
        if !literal.contains("\\(") { found.append(literal) }
        rest = rest[index...]
    }
    return found
}

@Suite("The words the app shows live in a String Catalog (Decision 0022)")
struct StringCatalogTests {

    // The MdoroWidget shape: six `String(localized:)` calls in a target that had no
    // catalogue at all, so every one of them returned its own key. English, so the lock
    // screen looked right and the strings were invisible to anyone adding a language.
    @Test func aTargetThatLocalisesAStringHasSomewhereToLocaliseItInto() throws {
        for target in appTargets {
            let localises = try swiftFiles(under: target.folder, recursive: true)
                .filter { $0.value.contains("String(localized:") || $0.value.contains("LocalizedStringKey") }
            guard !localises.isEmpty else { continue }
            let exists = FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent(target.catalogue).path
            )
            #expect(exists, "Decision 0022: \(target.folder) localises \(localises.keys.sorted()) into nothing")
            guard exists else { continue }
            #expect(try sourceLanguage(target.catalogue) == "en", "REQ-UIX-038 / Decision 0022")
        }
    }

    // The other direction, and the one that arrives without a sound. The catalogue is written
    // by Xcode — its editor, and its builds, outside the build's task graph — and by
    // `xcstringstool sync` run by hand (`docs/PLATFORM.md`). **None of those happens to a
    // `String(localized:)` added from another editor and pushed as it is:** it lands in the
    // .stringsdata and never in the .xcstrings. The lookup then returns the key and nothing
    // anywhere says the string was missed.
    @Test func everyPlainSentenceTheCodeAsksForIsAKeyInItsTargetsCatalogue() throws {
        for target in appTargets {
            let keys = try catalogueKeys(target.catalogue)
            for (name, text) in try swiftFiles(under: target.folder, recursive: true) {
                for literal in plainLocalizedLiterals(in: text) {
                    #expect(
                        keys.contains(literal),
                        "Decision 0022: \(name) asks for `\(literal)`, which \(target.catalogue) does not have"
                    )
                }
            }
        }
    }

    // The PresetEditorView shape: `Text(.init(markdown))` and `LocalizedStringKey(someString)`
    // build a key at run time, so the compiler never sees one and Xcode extracts nothing. It
    // reads like a localised string at the call site, which is what makes it worth a test.
    @Test func noViewBuildsItsKeyAfterTheCompilerHasGone() throws {
        for target in appTargets {
            for (name, text) in try swiftFiles(under: target.folder, recursive: true) {
                #expect(!text.contains("Text(.init("), "Decision 0022: \(name) builds a key at run time")
                // A literal written plainly never spells out `LocalizedStringKey`. Only the type
                // annotation and the argument's type are left.
                for built in ["LocalizedStringKey(", "LocalizedStringKey.init("] {
                    #expect(!text.contains(built), "Decision 0022: \(name) builds a key at run time")
                }
            }
        }
    }

    // Decision 0022's boundary for the package: MdoroCore has no catalogue to reach, so it
    // keeps the state and the two identifiers, and each platform's `Format` keeps the words.
    // Wording kept in the package would have to be written a second time on each screen anyway,
    // and the copy that is read is then the one no catalogue can translate.
    @Test func theConnectionStateIsNamedByTheCoreAndWordedByTheScreens() throws {
        let words = ["Connected", "Reconnecting", "Not connected"]
        let core = try source("Packages/MdoroCore/Sources/MdoroCore/ConnectionState.swift")
        for word in words {
            #expect(
                !core.contains("\"\(word)\""),
                "Decision 0022: `\(word)` is a display string in a package with no catalogue"
            )
        }
        for target in appTargets.prefix(2) {
            let theme = try source(target.folder + "/Views/Theme.swift")
            let keys = try catalogueKeys(target.catalogue)
            #expect(theme.contains("connectionLabel"), "\(target.folder) has no wording of its own")
            for word in words {
                #expect(theme.contains("\"\(word)\""), "\(target.folder) never says `\(word)`")
                #expect(keys.contains(word), "\(target.catalogue) is missing `\(word)`")
            }
        }
    }
}
