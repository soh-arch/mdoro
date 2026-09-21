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

// **The scans that read a declaration now trust one function to say where it ends.**
//
// `PairingTests`, `FailuresThatReachSomeoneTests` and `StartingTwiceTests` used to cut a fixed
// number of characters out of the comment-stripped source, which moved every time a line of prose
// was written above what they were watching. They cut to the closing brace instead. That puts the
// boundary in one place, and a fault in that one place would reach all of them at once in the shape
// those suites are least able to notice: a window that agrees with whatever it was pointed at.
//
// Nothing else reads `declarationBody`, and the files it is pointed at hold no brace inside a
// string literal and no declaration without a closing brace — so the cases it has to get right
// cannot be tried on them. They are written here.
@Suite("A window that ends where the declaration does")
struct DeclarationBodyTests {

    // The two shapes a marker leaves behind, because one scan covers both.
    // `components(separatedBy: "func refuse(")` stops inside the parameter list, with the body's
    // opening brace still ahead; `range(of: "func stop() {")` stops inside the body, with that
    // brace already behind. Exact text rather than `contains`, so a boundary off by one shows.
    @Test func theWindowRunsFromTheMarkerToTheBraceThatClosesTheDeclaration() throws {
        let stoppedInTheParameterList = #"""
        _ code: Int) {
            body()
        }
        next()
        """#
        let fromTheParameterList = try declarationBody(openedBy: stoppedInTheParameterList, "func refuse(")
        #expect(fromTheParameterList == "_ code: Int) {\n    body()\n")

        let stoppedInsideTheBody = "\n    body()\n}\nnext()"
        let fromInsideTheBody = try declarationBody(openedBy: stoppedInsideTheBody, "func stop() {")
        #expect(fromInsideTheBody == "\n    body()\n")
    }

    // A brace the declaration does not open cannot close it, and the inner one has to be counted
    // back out again. Cut at the first `}` and the window ends before `kept()`.
    @Test func anInnerBraceDoesNotCloseTheDeclaration() throws {
        let nested = #"""
        () {
            if ready {
                inner()
            }
            kept()
        }
        next()
        """#
        let body = try declarationBody(openedBy: nested, "func refuse(")
        #expect(body.contains("inner()"), "the window stopped before the nesting it should count through")
        #expect(body.contains("kept()"), "an inner brace was read as the end of the declaration")
        #expect(!body.contains("next()"), "the window ran past the declaration it was cutting")
    }

    // **A brace inside a string literal is not a brace.** Believed, it would cut the window short —
    // silently, and in the direction that reads like a rule being kept.
    @Test func aBraceInsideAStringLiteralIsNotABrace() throws {
        let withABraceInALiteral = #"""
        () {
            log("}")
            kept()
        }
        next()
        """#
        let plainLiteral = try declarationBody(openedBy: withABraceInALiteral, "func write(")
        #expect(plainLiteral.contains("kept()"), "a brace inside a string literal closed the window")
        #expect(!plainLiteral.contains("next()"), "the window ran past the declaration it was cutting")

        // And the escape, because a `\"` read as the end of the literal puts the brace after it
        // back in play — the same fault one character along.
        let withAnEscapedQuote = #"""
        () {
            log("\"}")
            kept()
        }
        next()
        """#
        let escapedLiteral = try declarationBody(openedBy: withAnEscapedQuote, "func write(")
        #expect(escapedLiteral.contains("kept()"), "an escaped quote was read as the end of the literal")
        #expect(!escapedLiteral.contains("next()"), "the window ran past the declaration it was cutting")
    }

    // **A window with no end is not a window.** Answering the rest of the file instead would hand
    // every caller the whole type to look in, which is how a scan starts agreeing with anything.
    @Test func aDeclarationWithNoClosingBraceIsAnErrorRatherThanAWindow() throws {
        let unclosed = "() {\n    body()\n"
        #expect(throws: UnbalancedDeclaration.self) {
            try declarationBody(openedBy: unclosed, "func refuse(")
        }
        // And it says which declaration. A scan that has lost its anchor is the thing these
        // helpers exist to make loud, not the thing they exist to survive.
        do {
            let answered = try declarationBody(openedBy: unclosed, "func refuse(")
            Issue.record("a declaration with no closing brace answered a window: \(answered)")
        } catch let error as UnbalancedDeclaration {
            #expect(error.marker == "func refuse(")
            #expect(error.description.contains("func refuse("), "the failure does not name the declaration")
        }
    }

    // **The property the change was for.** Prose written inside a body spends a character count and
    // does not move this. `withoutComments` leaves the comment's indentation and its newline behind,
    // which is what the count was being spent on — so the fixture is held to actually moving the
    // statement, or it demonstrates nothing.
    @Test func prosePutInsideTheBodyDoesNotMoveTheWindow() throws {
        let plain = #"""
        () {
            kept()
        }
        next()
        """#
        let withProse = #"""
        () {
            // a line somebody added while explaining this
            kept()
        }
        next()
        """#
        let strippedPlain = withoutComments(plain)
        let strippedProse = withoutComments(withProse)

        let fromPlain = try declarationBody(openedBy: strippedPlain, "func refuse(")
        let fromProse = try declarationBody(openedBy: strippedProse, "func refuse(")
        #expect(fromPlain.contains("kept()"))
        #expect(fromProse.contains("kept()"), "a line of prose pushed the statement out of the window")
        #expect(!fromProse.contains("next()"), "the window ran past the declaration it was cutting")

        let plainAt = try #require(strippedPlain.range(of: "kept()"))
        let proseAt = try #require(strippedProse.range(of: "kept()"))
        let statementMoved =
            strippedPlain.distance(from: strippedPlain.startIndex, to: plainAt.lowerBound)
                < strippedProse.distance(from: strippedProse.startIndex, to: proseAt.lowerBound)
        #expect(statementMoved, "the prose did not move the statement, so this fixture proves nothing")
    }

    // Proved on text written here, the scan can still be cutting the wrong thing out of the file it
    // is pointed at — the same gap `theScanReadsMoreOfTheAppTargetsThanTheOldSpellingDid` covers
    // above. `FailuresThatReachSomeoneTests` reads `write(refusal:)` for the refusal's log line, and
    // what it must get back is that declaration rather than the type around it.
    @Test func theWindowCutFromARealFileIsOneDeclarationAndNotTheFileAroundIt() throws {
        let server = withoutComments(try source("PomodoroMac/PomodoroMac/Server/MdoroServer.swift"))
        let tail = try #require(server.components(separatedBy: "func write(refusal").last)
        let body = try declarationBody(openedBy: tail, "func write(refusal")
        #expect(!body.isEmpty, "the window is empty, and anything read from an empty window agrees")
        #expect(body.count < tail.count, "the window is the whole rest of the file")
        #expect(body.contains("conn.refused"), "the declaration this cuts is no longer the one that writes")
        // The next declaration is outside it, whatever it has come to be called.
        #expect(!body.contains("func "), "the window ran into the declaration after it")
    }
}
