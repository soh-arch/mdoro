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
}
