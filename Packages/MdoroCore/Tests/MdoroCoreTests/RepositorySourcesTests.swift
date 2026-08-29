import Testing
import Foundation
@testable import MdoroCore

// **走査は、走査先が消えたときにこそ落ちなければならない。**
//
// Several suites here hold rules that live in the app targets by reading their source
// (`ColorLiteralTests`, `StringCatalogTests`, `TestHostTests`, `NotationSampleTests`). Every
// one of them is a loop over files, and a loop over no files passes. The recursive branch of
// `swiftFiles` used to answer `[]` when the directory was not there, so renaming
// `PomodoroMacTests` was enough to silence the guard that keeps a test run from reaching the
// reader's notification centre — the scans failing open, in exactly the way they exist to
// prevent.
//
// This is not hypothetical maintenance. `project.pbxproj` belongs to Xcode and to the human
// working in it (Decision 0013), and the folders under `PomodoroMac/` still carry their
// pre-Mdoro names with a rename outstanding. **They are going to move.**
@Suite("A scan whose target has moved says so (POL-047)")
struct RepositorySourcesTests {

    @Test func aDirectoryThatIsNotThereThrowsRatherThanReadingNothing() {
        #expect(throws: MissingSourceDirectory.self) {
            try swiftFiles(under: "PomodoroMac/PomodoroMacTests-renamed", recursive: true)
        }
        // 非再帰の枝も同じ答えを返すこと。片方だけ直すと、次に緩むのはもう片方になる。
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

    // そして、実在する走査先は今までどおり読めること。
    @Test func aDirectoryThatIsThereStillReads() throws {
        let files = try swiftFiles(under: "PomodoroMac/PomodoroMacTests", recursive: true)
        #expect(!files.isEmpty)
        #expect(files["DiagnosticLogTests.swift"] != nil)
    }
}
