import Testing
import Foundation
@testable import MdoroCore

// **A scan must fail precisely when its target has disappeared.**
//
// Several suites here hold rules that live in the app targets by reading their source
// (`ColorLiteralTests`, `StringCatalogTests`, `TestHostTests`, `NotationSampleTests`). Every
// one of them is a loop over files, and a loop over no files passes. Let the recursive branch of
// `swiftFiles` answer `[]` for a directory that is not there and renaming `PomodoroMacTests` is
// enough to silence the guard that keeps a test run from reaching the reader's notification
// centre — the scans failing open, in exactly the way they exist to prevent.
//
// This is not hypothetical maintenance. `project.pbxproj` belongs to Xcode and to the human
// working in it (Decision 0013), and the folders under `PomodoroMac/` still carry their
// pre-Mdoro names with a rename outstanding. **They are going to move.**
@Suite("A scan whose target has moved says so")
struct RepositorySourcesTests {

    @Test func aDirectoryThatIsNotThereThrowsRatherThanReadingNothing() {
        #expect(throws: MissingSourceDirectory.self) {
            try swiftFiles(under: "PomodoroMac/PomodoroMacTests-renamed", recursive: true)
        }
        // The non-recursive branch has to answer the same way. Fix only one and the next to go
        // slack is the other.
        #expect(throws: MissingSourceDirectory.self) {
            try swiftFiles(under: "PomodoroMac/NoSuchFolder")
        }
    }

    // A file is not a directory, and `enumerator` is happy to be handed one.
    @Test func aFileInPlaceOfADirectoryIsNotADirectory() {
        #expect(throws: MissingSourceDirectory.self) {
            try swiftFiles(under: "Packages/MdoroCore/Package.swift", recursive: true)
        }
    }

    // And a target that is really there still reads as it always did.
    @Test func aDirectoryThatIsThereStillReads() throws {
        let files = try swiftFiles(under: "PomodoroMac/PomodoroMacTests", recursive: true)
        #expect(!files.isEmpty)
        #expect(files["DiagnosticLogTests.swift"] != nil)
    }

    // **The same failure, one level down.** `StringCatalogTests` and `NotationSampleTests` both
    // loop over the `String(localized:)` calls in a file, and both used to find them by the
    // spelling `String(localized: "`. The call each of them exists to catch is one added from an
    // editor that is not Xcode — and a sentence long enough to be worth localising is a sentence
    // that gets wrapped, so its argument sits on the next line and the spelling is not there. The
    // scan then reports nothing and the suites pass, which is the shape of failure they were
    // written against.
    @Test func aCallWrappedOverTwoLinesIsStillACall() {
        #expect(localizedStringLiterals(in: #"String(localized: "flat")"#) == ["flat"])
        #expect(
            localizedStringLiterals(
                in: #"""
                String(
                    localized: "wrapped"
                )
                """#
            ) == ["wrapped"]
        )
        // The break can fall on the other side of the label, and the spacing is not the point
        // either way.
        #expect(localizedStringLiterals(in: "String(localized:\n    \"after the colon\")") == ["after the colon"])
        #expect(localizedStringLiterals(in: #"String( localized:  "spaced" )"#) == ["spaced"])
    }

    // What the scan answered before has to survive being made to see more.
    @Test func theScanStillReadsWhatItAlwaysRead() {
        // A `String(` that is not this call, and the rejected one does not swallow the call nested
        // inside it.
        let describing = localizedCalls(in: #"String(describing: error)"#).isEmpty
        #expect(describing)
        let formatted = localizedCalls(in: #"String(format: "%@", count)"#).isEmpty
        #expect(formatted)
        #expect(localizedStringLiterals(in: #"Text(String(localized: "inner"))"#) == ["inner"])
        // Escapes are kept as written: what these suites compare is the source.
        #expect(localizedStringLiterals(in: #"String(localized: "a \"b\" c")"#) == [#"a \"b\" c"#])
        // Interpolation is read here and dropped by `StringCatalogTests`, the one caller that
        // cannot check it against a catalogue. The scan is not the place that decides that.
        #expect(localizedStringLiterals(in: #"String(localized: "n = \(count)")"#) == [#"n = \(count)"#])
        // A literal that spells the call out does not add one.
        #expect(
            localizedStringLiterals(in: #"String(localized: "say String(localized: \"x\" here")"#)
                == [#"say String(localized: \"x\" here"#]
        )
        // An argument that is not a literal is still a call. `StringCatalogTests` asks whether a
        // file localises anything at all before it insists on a catalogue, and the answer there
        // does not depend on the argument being readable.
        let oneCallWithNothingToRead: [String?] = [nil]
        #expect(localizedCalls(in: #"String(localized: key)"#) == oneCallWithNothingToRead)
        let noLiteral = localizedStringLiterals(in: #"String(localized: key)"#).isEmpty
        #expect(noLiteral)
    }

    // Proved on made-up text, a scan can still be reading nothing real. The old spelling is kept
    // here as the baseline: across the app targets the scan has to read strictly more calls than
    // `String(localized: "` occurs, which is only true while a wrapped call is actually there for
    // it to read.
    @Test func theScanReadsMoreOfTheAppTargetsThanTheOldSpellingDid() throws {
        var read = 0
        var spelledOnOneLine = 0
        for folder in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroiOS", "PomodoroMac/PomodoroWidget"] {
            for (_, text) in try swiftFiles(under: folder, recursive: true) {
                read += localizedCalls(in: text).count
                spelledOnOneLine += text.components(separatedBy: "String(localized: \"").count - 1
            }
        }
        #expect(spelledOnOneLine > 0, "no `String(localized:)` call is left in the app targets at all")
        // Not a complaint about the code: every call being on one line is fine. It means this
        // test has stopped covering the wrapped form, and something else has to.
        #expect(read > spelledOnOneLine, "no call is wrapped any more, so nothing here exercises that")
    }
}
