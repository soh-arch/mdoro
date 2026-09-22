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

// REQ-ERR-010 / REQ-COM-003 / REQ-PRT-004: **a scan whose anchor has been renamed finds nothing to
// object to, and passes.** That is the one failure the scans that read this repository's own sources
// exist to prevent, arriving through the scans themselves, so a missing anchor is an error rather
// than an absence — the same reason `swiftFiles(under:)` refuses a directory that moved.
struct MissingAnchor: Error, CustomStringConvertible {
    let path: String
    let anchor: String
    var description: String {
        "\(path) no longer contains `\(anchor)` — it was renamed or removed, and this scan was "
            + "watching nothing"
    }
}

// **`components(separatedBy:)` cannot say that the separator was not there.** It answers one piece —
// the whole text, handed back — for a text the anchor does not occur in, and every shape the callers
// here take that answer in reads like an answer about the code rather than about the anchor:
//
//   * `.last` is then the whole file. It is neither nil nor empty, so `try #require(…)` passes it
//     straight through as the window, and what the window contains is whatever the file contains. A
//     `contains` that has to hold is met by that spelling anywhere else in the file; a `contains`
//     that must not hold is broken by a spelling that was never in the declaration being watched.
//     **Both answers are an accident**, and on 2026-09-21 both were had at once from one renamed
//     anchor. Handed the whole of `MdoroServer.swift` where it had asked for one declaration, the
//     scan found the log line it insists on somewhere else in the file — so that half passed — and
//     found the field Decision 0018 forbids as well, so it failed, for the other clause, saying
//     nothing about the anchor. **A measurement of how much slack there is dates**: what that
//     window came to was measured twice over one fix to the file, and grew by 224 characters.
//   * `.dropFirst()` and `.dropLast()` are then empty, so a loop over every occurrence runs no
//     iterations: a rule with nothing left to break it, which is how a suite passes having read
//     nothing.
//
// The callers' own guard against the second shape was `!pieces.isEmpty`, which does catch the
// absence — but it says something about the code in saying so ("nothing here refuses a connection
// any more"), and that is not what went wrong. **Which anchor is gone is the whole of the news**, so
// it is told here, where it is known, rather than guessed at by each caller.
private func pieces(of text: String, splitAt anchor: String, in path: String) throws -> [String] {
    // An anchor that matches everywhere names nothing in particular. What `components(separatedBy:)`
    // answers for an empty separator is not something either end of this documents, so it is refused
    // rather than read off whatever comes back — the same reading `callArguments` makes of a marker
    // that opens no call.
    guard !anchor.isEmpty else { throw MissingAnchor(path: path, anchor: anchor) }
    let split = text.components(separatedBy: anchor)
    // One piece is the whole text back again, which is what "not found" looks like from here.
    guard split.count > 1 else { throw MissingAnchor(path: path, anchor: anchor) }
    return split
}

// The text after the last `anchor` — `components(separatedBy:).last`, with the absence it cannot
// report. **The last one, because one anchor can name more than one thing**: `func refuse(` names
// two declarations in `MdoroServer.swift`, and a caller that wants the second cannot ask for it by
// the first.
func afterTheLastAnchor(_ anchor: String, in text: String, of path: String) throws -> String {
    let split = try pieces(of: text, splitAt: anchor, in: path)
    // `pieces` answers two or more, so this is the text past an anchor that was really there.
    guard let last = split.last else { throw MissingAnchor(path: path, anchor: anchor) }
    return last
}

// The text after each `anchor`, in order — `components(separatedBy:).dropFirst()`, with the absence
// it cannot report. One piece per occurrence, so a caller counting them is counting occurrences.
func afterEachAnchor(_ anchor: String, in text: String, of path: String) throws -> [String] {
    let split = try pieces(of: text, splitAt: anchor, in: path)
    return Array(split.dropFirst())
}

// The text before each `anchor` — `components(separatedBy:).dropLast()`, with the absence it cannot
// report. Each piece begins where the previous occurrence ended rather than at the start of the
// file, and there is one per occurrence, the same as `afterEachAnchor`.
func beforeEachAnchor(_ anchor: String, in text: String, of path: String) throws -> [String] {
    let split = try pieces(of: text, splitAt: anchor, in: path)
    return Array(split.dropLast())
}

// REQ-ERR-010 / REQ-COM-003 / REQ-PRT-004: several scans here read a marker out of a file and then
// ask what the declaration underneath it does. **A window measured in characters is a window that
// slides.** `withoutComments` above drops a comment's text and keeps its newline and its
// indentation, so every line of prose written inside a declaration spends part of a fixed
// `prefix(n)` budget — and on 2026-09-20 two of these bodies grew by four lines and by two. Nothing
// went red, because nothing can: a window that has slid off the end of what it was watching reads
// exactly like a window whose contents are fine, and one that has slid onto the *next* declaration
// reads like a rule that declaration keeps. Either way the answer is an accident of how much prose
// happens to be above it.
//
// **So the window ends where the declaration does**, at the brace that closes it, and how many
// lines sit inside it stops mattering. Do not put a character count back.
//
// The text handed in begins just past a marker that named a declaration, and there are two cases of
// that. A marker that took the declaration's opening brace with it (`func stop() {`) leaves the text
// **already inside the body, one level deep**. A marker that stopped in the parameter list
// (`func refuse(`, which is where `components(separatedBy:)` leaves it) leaves the text **outside it,
// with that brace still ahead**.
//
// **Which case it is, only the marker can say.** The two look alike from inside the text: a body
// whose first statement is `if ready {` is one level down either way, so a scan that began at zero
// and waited for a brace to open would read that clause's own `}` as the end of the declaration.
// Counting from the depth the marker implies is what tells the clause's brace from the body's.
//
// **What this reads of a string literal is narrow**: a `"` opens one and the next unescaped `"`
// closes it. Inside, a brace is not a brace, and a `\"` does not end the literal — escapes are
// honoured the way `localizedCalls` below honours them. Swift's literals are more than that. What
// is known not to be read is a multiline (`"""`) literal, a raw (`#"`) one, and **a literal nested
// inside an interpolation**. That these three are the ones known is not a reason to believe they
// are all of them.
//
// The nested one is the ordinary shape of the three: `"\(a["k"])"` is a subscript inside a message.
// Its quotes are counted as the outer literal's, so past it the parity of `"` is inverted for
// everything that follows. **It falls two ways, and the quiet one is the worse.** With an escape
// inside it — `"\(a["it\"s"])"` — the count comes out odd, the brace that closes the declaration is
// read as though it sat inside a literal, it is never counted, and the answer is
// `UnbalancedDeclaration`: wrong, but loud. With a brace inside it — `"\(a["}"])"` — the count comes
// out even and that brace is put back in play, so the window is cut short at it and handed over as
// the declaration's body. **A window shorter than the thing it is passed off as is the failure this
// function was written to stop.** And one with neither, `"\(a["k"])"`, comes out right by
// arithmetic — so writing one, trying it and watching it work says nothing about the next one.
//
// Neither file the callers read holds an interpolation at all today. That is a fact about
// `MdoroServer.swift` and `AppModel.swift` as they stand, not a property of this function.
struct UnbalancedDeclaration: Error, CustomStringConvertible {
    let marker: String
    var description: String {
        "no brace closes the declaration after `\(marker)` — the marker names something else now, "
            + "or the file is truncated"
    }
}

// **The one reading of a string literal that both windows below share.** A bracket counted here is
// what decides where a window ends, so the two must not each hold an opinion about what a literal
// is: a second reading of them is a second place to forget to plug.
//
// What this reading does **not** cover is written out above — a multiline (`"""`) literal, a raw
// (`#"`) one, and a literal nested inside an interpolation — and because there is one reading, that
// paragraph is about both windows. Neither of them is claimed to read more than this.
private struct StringLiteralSkipping {
    private var insideStringLiteral = false
    private var escaped = false

    // True when the character is code, where a bracket is a bracket. False for every character
    // inside a string literal, the quotes that open and close it included.
    mutating func isCode(_ character: Character) -> Bool {
        if insideStringLiteral {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                insideStringLiteral = false
            }
            return false
        }
        if character == "\"" {
            insideStringLiteral = true
            return false
        }
        return true
    }
}

// The body of the declaration the text opens, comments already gone. `marker` is carried only so a
// failure can say which declaration went missing.
func declarationBody(openedBy text: some StringProtocol, _ marker: String) throws -> String {
    let opened = String(text)
    // Read off the marker, because the text cannot answer it.
    let markerTookTheOpeningBrace = marker.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{")
    var depth = markerTookTheOpeningBrace ? 1 : 0
    var scan = StringLiteralSkipping()
    for index in opened.indices {
        let character = opened[index]
        guard scan.isCode(character) else { continue }
        switch character {
        case "{":
            depth += 1
        case "}":
            depth -= 1
            if depth == 0 { return String(opened[opened.startIndex..<index]) }
            // Closing what was never opened: the marker did not name a declaration, or it named one
            // whose brace the marker was expected to have taken and did not.
            if depth < 0 { throw UnbalancedDeclaration(marker: marker) }
        default:
            break
        }
    }
    throw UnbalancedDeclaration(marker: marker)
}

// **The same window, ended by the other bracket.** The scans above anchor on a declaration; several
// others anchor on a **call** — `ProtocolErrorPayload(`, `AuthFailedPayload(`, `AppModel(`,
// `State(initialValue:`, `MenuBarExtra(` — and ask which arguments it was written with. Those cut a
// fixed `prefix(n)` out of the text until 2026-09-20, with the fault the paragraph above describes:
// a count of characters is spent by every line of prose written above what is being watched, and a
// window that has slid reads exactly like a window whose contents are fine.
//
// **`declarationBody` cannot cut these.** Anchored on a call, the text begins inside an argument
// list, so the next `}` it meets closes the scope the call sits in rather than anything the call
// opened — the window it answers is the rest of the enclosing declaration, handed over as a body.
// `aMarkerThatNamedNoDeclarationIsAnErrorRatherThanAWindow` holds that, and it is why there are two
// functions here rather than one. **The bracket that ends a call is the `)` matching the one the
// marker opened.**
//
// **Which bracket the marker opened, only the marker can say** — the same reading `declarationBody`
// makes of its brace, one bracket along. The marker's own brackets are counted: `AppModel(` leaves
// one call open; `State(initialValue:` leaves one open as well, though it does not end in a
// bracket, so asking whether the last character is `(` is not enough; `f(a)` leaves none.
//
// **A marker that leaves none is refused rather than guessed at.** Beginning at zero instead, the
// first `(` inside the arguments opens a level whose own `)` is then read as the end of the call,
// and the window is cut short of what it is handed over as — which is the failure both of these
// functions exist to stop, arriving through the function meant to stop it.
struct UnclosedCall: Error, CustomStringConvertible {
    let marker: String
    // Two ways to have no bracket to stop at, and they are not the same fault: one is the marker
    // being the wrong shape for this window, the other is the file no longer holding what it named.
    let markerOpensNoCall: Bool
    var description: String {
        markerOpensNoCall
            ? "`\(marker)` leaves no call open, so there is no bracket for a window to end at"
            : "no bracket closes the call after `\(marker)` — the marker names something else now, "
                + "or the file is truncated"
    }
}

// The arguments the call the text opens was written with, comments already gone. `marker` is carried
// only so a failure can say which call went missing.
func callArguments(openedBy text: some StringProtocol, _ marker: String) throws -> String {
    // Read off the marker, because the text cannot answer it.
    var depth = 0
    var markerScan = StringLiteralSkipping()
    for character in marker {
        guard markerScan.isCode(character) else { continue }
        switch character {
        case "(":
            depth += 1
        case ")":
            depth -= 1
        default:
            break
        }
    }
    guard depth > 0 else { throw UnclosedCall(marker: marker, markerOpensNoCall: true) }

    let opened = String(text)
    var scan = StringLiteralSkipping()
    for index in opened.indices {
        let character = opened[index]
        guard scan.isCode(character) else { continue }
        switch character {
        case "(":
            depth += 1
        case ")":
            depth -= 1
            if depth == 0 { return String(opened[opened.startIndex..<index]) }
        default:
            break
        }
    }
    throw UnclosedCall(marker: marker, markerOpensNoCall: false)
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
