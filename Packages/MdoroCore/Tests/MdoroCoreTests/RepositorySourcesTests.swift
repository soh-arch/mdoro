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

    // **The depth the count starts from comes off the marker, and it has to.** A marker that took the
    // opening brace with it leaves the text already one level in; begin at zero instead and the first
    // `if` in the body opens a level whose own `}` closes what then looks like the declaration.
    //
    // This is the shape that was wrong, and nothing caught it: `stop()` and `stopServer()` — the two
    // declarations reached by a marker of that form — have no nested brace between them, so the files
    // could not exercise it, and the fixture that covered the form had no nesting either. The
    // statement after the nesting is the one the window has to still hold.
    @Test func aMarkerThatTookTheOpeningBraceStartsOneLevelDeep() throws {
        let oneNesting = #"""
            if ready {
                inner()
            }
            kept()
        }
        next()
        """#
        let body = try declarationBody(openedBy: oneNesting, "func stop() {")
        #expect(body.contains("inner()"), "the window stopped before the nesting it should count through")
        #expect(body.contains("kept()"), "a clause's own brace was read as the end of the declaration")
        #expect(!body.contains("next()"), "the window ran past the declaration it was cutting")
    }

    // Two levels, because counting one back out is not the same as counting back to where it started.
    @Test func aMarkerThatTookTheOpeningBraceCountsOutOfEveryNesting() throws {
        let twoNestings = #"""
            if ready {
                for item in items {
                    inner(item)
                }
            }
            kept()
        }
        next()
        """#
        let body = try declarationBody(openedBy: twoNestings, "func stop() {")
        #expect(body.contains("inner(item)"), "the window stopped before the nesting it should count through")
        #expect(body.contains("kept()"), "the window came back up one level short")
        #expect(!body.contains("next()"), "the window ran past the declaration it was cutting")
    }

    // And in the file, for the marker of that form the scans actually use. `stop()` holds no nested
    // brace, which is why the two fixtures above carry that case; what is left for a real file to
    // answer is that the window is this declaration and ends where it does.
    @Test func theWindowCutFromAMarkerThatTookTheBraceIsRightInTheFileToo() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        let opening = try #require(appModel.range(of: "func stop() {"), "AppModel no longer has stop()")
        let body = try declarationBody(openedBy: appModel[opening.upperBound...], "func stop() {")
        #expect(!body.isEmpty, "the window is empty, and anything read from an empty window agrees")
        #expect(
            body.contains("hasStarted = false"),
            "the declaration this cuts is no longer the one that clears the flag"
        )
        #expect(!body.contains("func "), "the window ran into the declaration after it")
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

    // **A marker that named no declaration is not a window either.** Anchored on a call, the text
    // begins inside the parameter list of something that is not a declaration, and the first `}` it
    // reaches closes a scope this window never opened. Left to run, the count comes back to zero on
    // some later pair of braces and a window is answered — the rest of an enclosing function,
    // presented as a declaration's body. This is also why the scans that anchor on a call cannot be
    // moved onto this one.
    @Test func aMarkerThatNamedNoDeclarationIsAnErrorRatherThanAWindow() {
        let afterACall = #"""
                code: reason.protocolErrorCode)
            }
            onRetry = {
                queue.async {
                    again()
                }
            }
        """#
        #expect(throws: UnbalancedDeclaration.self) {
            try declarationBody(openedBy: afterACall, "ProtocolErrorPayload(")
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

// **And the other bracket, for the scans that anchor on a call.**
//
// `ASettingWeCannotReadTests`, `FailuresThatReachSomeoneTests` and `TestHostTests` ask what
// arguments a call was written with — `ProtocolErrorPayload(`, `AuthFailedPayload(`, `AppModel(`,
// `State(initialValue:`, `MenuBarExtra(`. Nine of those windows were a fixed `prefix(n)`, and the
// slack measured 1 to 10 lines: thinner than the declaration windows above, in the same files where
// a line of prose is written most often. `declarationBody` cannot cut them, because past a call the
// next `}` closes the scope the call sits in.
//
// Same reason the suite above exists: one function answers all of them, so a fault in it arrives
// everywhere at once in the shape those suites cannot notice — a window that agrees with whatever it
// was pointed at. The files it is pointed at hold no bracket inside a literal, no marker two levels
// deep and no unclosed call, so the cases it has to get right are written here.
@Suite("A window that ends where the call does")
struct CallArgumentsTests {

    // Exact text rather than `contains`, so a boundary off by one shows. The closing bracket is not
    // part of the arguments, and nothing after it is either.
    @Test func theWindowRunsFromTheMarkerToTheBracketThatClosesTheCall() throws {
        let flat = try callArguments(openedBy: "code: 1, message: nil)\nnext()", "refuse(")
        #expect(flat == "code: 1, message: nil")

        let wrapped = try callArguments(
            openedBy: "\n    code: 1,\n    message: nil\n)\nnext()",
            "refuse("
        )
        #expect(wrapped == "\n    code: 1,\n    message: nil\n")
    }

    // A bracket the call did not open cannot close it, and the inner one has to be counted back out
    // again. Stop at the first `)` and the window ends inside the first argument.
    @Test func aNestedCallDoesNotCloseTheOuterOne() throws {
        let nested = try callArguments(openedBy: "code: Code(error), message: sum(a, b))\nnext()", "refuse(")
        #expect(nested == "code: Code(error), message: sum(a, b)")
        let stoppedEarly = nested.contains("message:")
        #expect(stoppedEarly, "a nested call's own bracket was read as the end of the outer one")
        let ranOn = nested.contains("next()")
        #expect(!ranOn, "the window ran past the call it was cutting")
    }

    // **The depth the count starts from comes off the marker, and the marker's last character is not
    // enough to read it.** `State(initialValue:` ends in a colon and leaves a call open all the
    // same; `TestHostTests` anchors on exactly that. A marker can leave two open, and one can carry
    // a bracket inside a literal of its own, which is not a bracket either.
    @Test func theDepthTheCountStartsFromComesOffTheMarker() throws {
        let notEndingInABracket = try callArguments(
            openedBy: " TestHost.isRunning ? AppModel(store: x) : AppModel())\n",
            "_model = State(initialValue:"
        )
        #expect(notEndingInABracket == " TestHost.isRunning ? AppModel(store: x) : AppModel()")

        // Two levels: counting one back out is not the same as counting back to where it started.
        let twoLevelsDeep = try callArguments(openedBy: "x))\nnext()", "outer(inner(")
        #expect(twoLevelsDeep == "x)")

        let bracketInsideTheMarkersLiteral = try callArguments(openedBy: "b)\nnext()", #"log("a(", "#)
        #expect(bracketInsideTheMarkersLiteral == "b")
    }

    // **A marker that leaves no call open is refused rather than guessed at.** Begin the count at
    // zero and the first `(` inside the arguments opens a level whose own `)` is read as the end of
    // the call: a window cut short of what it is handed over as, which is the failure this function
    // exists to stop.
    @Test func aMarkerThatLeavesNoCallOpenIsAnErrorRatherThanAWindow() {
        #expect(throws: UnclosedCall.self) {
            try callArguments(openedBy: "(a)\nnext()", "somethingElse")
        }
        // A marker matched against nothing, which is what an empty one is.
        #expect(throws: UnclosedCall.self) {
            try callArguments(openedBy: "(a)\nnext()", "")
        }
        // And one that closed again what it opened.
        #expect(throws: UnclosedCall.self) {
            try callArguments(openedBy: "b)\nnext()", "refuse(a)")
        }
    }

    // **A bracket inside a string literal is not a bracket.** Believed, it cuts the window short —
    // silently, and in the direction that reads like a rule being kept.
    @Test func aBracketInsideAStringLiteralIsNotABracket() throws {
        let inALiteral = try callArguments(openedBy: #"message: "done)", code: 1)"# + "\nnext()", "refuse(")
        #expect(inALiteral == #"message: "done)", code: 1"#)

        // And the escape, because a `\"` read as the end of the literal puts the bracket after it
        // back in play — the same fault one character along.
        let escapedQuote = try callArguments(openedBy: #"message: "it\")", code: 1)"# + "\nnext()", "refuse(")
        #expect(escapedQuote == #"message: "it\")", code: 1"#)
    }

    // **A window with no end is not a window.** Answering the rest of the file instead hands every
    // caller the whole type to look in, which is how a scan starts agreeing with anything.
    @Test func aCallWithNoClosingBracketIsAnErrorRatherThanAWindow() {
        #expect(throws: UnclosedCall.self) {
            try callArguments(openedBy: "code: 1, message: nil", "refuse(")
        }
        // And it says which call, and which of the two faults it was: a marker of the wrong shape is
        // not a file that has lost what the marker named.
        do {
            let answered = try callArguments(openedBy: "code: 1", "refuse(")
            Issue.record("a call with no closing bracket answered a window: \(answered)")
        } catch let error as UnclosedCall {
            #expect(error.marker == "refuse(")
            #expect(error.markerOpensNoCall == false)
            let namesTheCall = error.description.contains("refuse(")
            #expect(namesTheCall, "the failure does not name the call")
        } catch {
            Issue.record("a call with no closing bracket threw something else: \(error)")
        }
        do {
            let answered = try callArguments(openedBy: "(a)", "somethingElse")
            Issue.record("a marker that opens no call answered a window: \(answered)")
        } catch let error as UnclosedCall {
            #expect(error.markerOpensNoCall)
            let saysWhy = error.description.contains("leaves no call open")
            #expect(saysWhy, "the failure does not say the marker opened nothing")
        } catch {
            Issue.record("a marker that opens no call threw something else: \(error)")
        }
    }

    // A call written with nothing in it has an empty window, and that is an answer rather than a
    // fault. The callers are the ones that insist their own windows are not empty.
    @Test func aCallWithNoArgumentsIsAnEmptyWindowAndNotAnError() throws {
        let nothing = try callArguments(openedBy: ")\nnext()", "AppModel(")
        #expect(nothing.isEmpty)
    }

    // **Proved on text written here, the scan can still be cutting the wrong thing out of the file
    // it is pointed at.** Both callers' real anchors, for the two things a real file can say that a
    // fixture cannot: that the window is this call and not the declaration around it, and that the
    // bound is doing work — `message:` is in the file just past the bracket, which is the sentence
    // `theRefusalsTheServerSendsCarryACodeAndNoSentence` would be wrong to read.
    @Test func theWindowCutFromARealFileIsOneCallAndNotTheFileAroundIt() throws {
        let appModel = withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift"))
        let payload = try #require(appModel.components(separatedBy: "ProtocolErrorPayload(").last)
        let arguments = try callArguments(openedBy: payload, "ProtocolErrorPayload(")
        #expect(!arguments.isEmpty, "the window is empty, and anything read from an empty window agrees")
        #expect(arguments.count < payload.count, "the window is the whole rest of the file")
        let tied = arguments.contains("relatedRequestId:")
        #expect(tied, "the call this cuts is no longer the one that answers a request")
        // The next declaration is outside it, whatever it has come to be called.
        let ranOn = arguments.contains("func ")
        #expect(!ranOn, "the window ran into the declaration after the call")

        let server = withoutComments(try source("PomodoroMac/PomodoroMac/Server/MdoroServer.swift"))
        let refusal = try #require(server.components(separatedBy: "AuthFailedPayload(").last)
        let refusalArguments = try callArguments(openedBy: refusal, "AuthFailedPayload(")
        #expect(!refusalArguments.isEmpty, "the window is empty, and an empty window agrees with anything")
        let carriesNoSentence = !refusalArguments.contains("message:")
        #expect(carriesNoSentence, "the refusal now carries a sentence")
        // **And the bound is what says so.** The file does hold a `message:` past this bracket,
        // legitimately, for a payload of another kind — so a window that ran on would call the
        // refusal wrong. This is the negative claim the fixed count above was closest to breaking.
        let pastTheBracket = refusal.contains("message:")
        #expect(pastTheBracket, "nothing past the bracket says `message:` any more, so this proves nothing")
    }

    // **The property the change was for.** Prose written inside the arguments spends a character
    // count and does not move this. `withoutComments` leaves the comment's indentation and its
    // newline behind, which is what the count was being spent on — so the fixture is held to
    // actually moving the argument, or it demonstrates nothing at all.
    @Test func prosePutInsideTheArgumentsDoesNotMoveTheWindow() throws {
        let plain = #"""

            store: x,
            notifications: y
        )
        next()
        """#
        let withProse = #"""

            store: x,
            // why this one is the one
            notifications: y
        )
        next()
        """#
        let strippedPlain = withoutComments(plain)
        let strippedProse = withoutComments(withProse)

        let fromPlain = try callArguments(openedBy: strippedPlain, "AppModel(")
        let fromProse = try callArguments(openedBy: strippedProse, "AppModel(")
        let plainSays = fromPlain.contains("notifications:")
        #expect(plainSays)
        let proseSays = fromProse.contains("notifications:")
        #expect(proseSays, "a line of prose pushed the argument out of the window")
        let ranOn = fromProse.contains("next()")
        #expect(!ranOn, "the window ran past the call it was cutting")

        let plainAt = try #require(strippedPlain.range(of: "notifications:"))
        let proseAt = try #require(strippedProse.range(of: "notifications:"))
        let argumentMoved =
            strippedPlain.distance(from: strippedPlain.startIndex, to: plainAt.lowerBound)
                < strippedProse.distance(from: strippedProse.startIndex, to: proseAt.lowerBound)
        #expect(argumentMoved, "the prose did not move the argument, so this fixture proves nothing")
    }

    // The other half of the same property, and the one a negative claim rests on: what is written
    // past the bracket is not in the window, however close to it.
    @Test func whatIsWrittenPastTheBracketIsNotInTheWindow() throws {
        let planted = "code: 1)\nlog(message: \"after\")\nnext()"
        let arguments = try callArguments(openedBy: planted, "refuse(")
        #expect(arguments == "code: 1")
        let reachedPast = arguments.contains("message:")
        #expect(!reachedPast, "the window reached past the bracket it stops at")
    }
}
