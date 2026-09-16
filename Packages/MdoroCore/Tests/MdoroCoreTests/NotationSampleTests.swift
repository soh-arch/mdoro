import Testing
import Foundation

// REQ-TSK-016: when nothing was found in the task file, the app answers by showing the notation
// it reads. A sample the reader cannot pick out of the sentence does not show anything, and that
// is what a verbatim `Text` produces — `String(localized:)` resolves the key first, so `Text`
// gets a plain String and prints the backticks as themselves. Handing `Text` the key instead
// lets SwiftUI set the sample as code.
//
// The two forms read almost identically at the call site, so neither one holds the other in
// place. The rule is checked on the text instead: nothing that draws resolves a string with a
// backtick in it.

private let drawingSources = [
    "PomodoroMac/PomodoroMac/Views",
    "PomodoroMac/PomodoroiOS/Views",
    "PomodoroMac/PomodoroWidget",
]

// Every `String(localized: "…")` literal in a file, as written.
private func resolvedLiterals(in text: String) -> [String] {
    var found: [String] = []
    var rest = Substring(text)
    while let call = rest.range(of: "String(localized: \"") {
        rest = rest[call.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { break }
        found.append(String(rest[rest.startIndex..<end]))
        rest = rest[end...]
    }
    return found
}

@Suite("A notation sample reaches the screen as Markdown (POL-052 / REQ-TSK-016)")
struct NotationSampleTests {

    @Test func nothingThatDrawsResolvesAStringWithNotationInIt() throws {
        for directory in drawingSources {
            for (name, text) in try swiftFiles(under: directory, recursive: true) {
                for literal in resolvedLiterals(in: text) where literal.contains("`") {
                    Issue.record(
                        """
                        POL-052: \(name) resolves `\(literal)` before drawing it, so the \
                        backticks print as themselves. Pass the key to Text instead.
                        """
                    )
                }
            }
        }
    }

    // The scan has to find the calls it is looking for, or it passes by being blind.
    @Test func theScanReadsTheFormItIsLookingFor() {
        #expect(resolvedLiterals(in: #"Text(String(localized: "a `b` c"))"#) == ["a `b` c"])
        #expect(resolvedLiterals(in: #"Text("a `b` c")"#).isEmpty)
    }

    // The one the audit found. It has to still be on screen, or the check above is about a
    // sentence nobody shows.
    @Test func theEmptyStateStillShowsTheNotation() throws {
        let view = withoutComments(try source("PomodoroMac/PomodoroMac/Views/TaskListView.swift"))
        #expect(
            view.contains("`- [ ] task`"),
            "REQ-TSK-016: the empty state no longer shows an example of the notation it reads"
        )
    }
}
