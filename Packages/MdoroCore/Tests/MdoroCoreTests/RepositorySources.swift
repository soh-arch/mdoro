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
// **What this reads of a string literal**: a `"` opens one and the next unescaped `"` closes it, and
// inside it a brace is not a brace and a `\"` does not end the literal. **And `\(` is where the code
// comes back** — so a literal written inside an interpolation is read as a literal of its own, and a
// bracket is counted at the depth it is actually written at. `"\(a["}"])"` holds no brace at all.
//
// That last part was not read until 2026-09-21, and how it failed is the reason the paragraphs above
// are here. The nested literal's quotes were counted as the outer one's, so past it the parity of `"`
// was inverted for everything after. **It fell two ways, and the quiet one was the worse.** With a
// brace inside it — `"\(a["}"])"` — the count came out even, that brace was put back in play, the
// window was cut short at it and handed over as the declaration's body: **a window shorter than the
// thing it is passed off as is the failure this function was written to stop.** With an escape inside
// it — `"\(a["it\"s"])"` — the count came out odd, the brace that closes the declaration was read as
// though it sat inside a literal, and the answer was `UnbalancedDeclaration`: wrong, but loud. And
// one with neither, `"\(a["k"])"`, came out right **by arithmetic** — so writing one, trying it and
// watching it work said nothing whatever about the next one.
//
// **Two forms are still not read, and those are refused rather than answered**: a multiline (`"""`)
// literal and a raw (`#"`, `##"`, …) one both meet `UnreadableLiteral`. Cutting a short window for
// them would be the failure above arriving through the function meant to stop it. **That these two
// are the ones named is not a reason to believe they are all of them.**
struct UnbalancedDeclaration: Error, CustomStringConvertible {
    let marker: String
    var description: String {
        "no brace closes the declaration after `\(marker)` — the marker names something else now, "
            + "or the file is truncated"
    }
}

// A literal this reading cannot follow. **Refused, rather than answered short.** The alternative is
// a window that stops inside the literal and is handed to a caller as the whole of what its marker
// named, or a sentence handed to a catalogue with its end cut off — which is the one failure every
// scan in this file exists to prevent, arriving through the scans themselves.
struct UnreadableLiteral: Error, CustomStringConvertible {
    // Named rather than counted, so a failure says which form was met and not merely that one was.
    enum Form: Equatable {
        case multiline
        case raw
    }
    let form: Form
    var description: String {
        // Spelled with escapes rather than as raw literals, so that nothing in this file is a shape
        // the reading above refuses — a scan pointed at it one day would have to stop on its own text.
        let spelling = switch form {
        case .multiline: "multiline (\"\"\")"
        case .raw: "raw (#\")"
        }
        return "a \(spelling) string literal is not read here, so nothing is cut or collected past one"
    }
}

// **The one reading of a string literal in this file.** A bracket counted here is what decides where
// a window ends, and the same reading says what a localised sentence was written to say — so the
// three scans below must not each hold an opinion about what a literal is: **a second reading of
// them is a second place to forget to plug.**
//
// `localizedCalls` held a second one until 2026-09-21, and it had the fault above in a worse form.
// It stopped at the first `"` after the opening one, which a subscript inside an interpolation puts
// in the middle of the sentence — so `"a \(d["k"]) b"` came back as `a \(d[`, **with or without an
// escape in it**. The windows had one shape that came out right by arithmetic; this had none.
//
// What this reading does **not** cover is written out above — a multiline (`"""`) literal and a raw
// (`#"`) one, both refused — and because there is one reading, that paragraph is about all three
// scans. None of them is claimed to read more than this.
private struct StringLiteralSkipping {
    // Where the reading is, innermost last. Empty is plain code. `.literal` is inside a `"…"`;
    // `.interpolation` is code again, inside a `\(…)`, and counts its own brackets so that it knows
    // which `)` hands the reading back to the literal it was written in.
    private enum Nesting {
        case literal
        case interpolation(depth: Int)
    }
    private var nesting: [Nesting] = []
    private var escaped = false
    // A `"""` cannot be told from an empty literal until its third quote arrives, and a `#"` cannot
    // be told from an ordinary `#` until its quote does. One character of memory each, rather than a
    // lookahead this reading has no way to take.
    private var literalIsEmptySoFar = false
    private var closedAnEmptyLiteral = false
    private var sawHashes = false

    private var insideALiteral: Bool {
        guard let innermost = nesting.last else { return false }
        if case .literal = innermost { return true }
        return false
    }

    // True while the reading is anywhere inside a literal, its interpolations included — because the
    // text of a literal is everything written between its quotes, which is what `localizedCalls`
    // collects.
    var isReadingALiteral: Bool { !nesting.isEmpty }

    // True when the character is code, where a bracket is a bracket. False for every character inside
    // a string literal, the quotes that open and close it included — **except that the code inside an
    // interpolation is code**, and so are the brackets of the `\(…)` itself, which pair up and so
    // leave every count where it was.
    mutating func isCode(_ character: Character) throws -> Bool {
        if insideALiteral {
            closedAnEmptyLiteral = false
            sawHashes = false
            let wasEmpty = literalIsEmptySoFar
            literalIsEmptySoFar = false
            if escaped {
                escaped = false
                // `\(` is the one escape that hands the reading back to code.
                if character == "(" {
                    nesting.append(.interpolation(depth: 1))
                    return true
                }
                return false
            }
            if character == "\\" {
                escaped = true
                return false
            }
            if character == "\"" {
                nesting.removeLast()
                // Only at the top level: an empty literal closing inside an interpolation cannot be
                // the head of a multiline one.
                if wasEmpty, !insideALiteral { closedAnEmptyLiteral = true }
                return false
            }
            return false
        }
        // Code: the top level, or inside an interpolation.
        if character == "\"" {
            if closedAnEmptyLiteral { throw UnreadableLiteral(form: .multiline) }
            if sawHashes { throw UnreadableLiteral(form: .raw) }
            nesting.append(.literal)
            literalIsEmptySoFar = true
            return false
        }
        if character == "#" {
            // Held rather than acted on: `#if`, `#expect` and a `"#"` of its own are not raw
            // literals, and each of them clears this on the character that follows.
            sawHashes = true
            closedAnEmptyLiteral = false
            return true
        }
        closedAnEmptyLiteral = false
        sawHashes = false
        if let innermost = nesting.last, case .interpolation(let depth) = innermost {
            switch character {
            case "(":
                nesting[nesting.count - 1] = .interpolation(depth: depth + 1)
            case ")":
                if depth == 1 {
                    nesting.removeLast()
                } else {
                    nesting[nesting.count - 1] = .interpolation(depth: depth - 1)
                }
            default:
                break
            }
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
        guard try scan.isCode(character) else { continue }
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
        guard try markerScan.isCode(character) else { continue }
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
        guard try scan.isCode(character) else { continue }
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
// label is matched across whitespace instead of as a fixed spelling; the literal itself goes through
// `StringLiteralSkipping` above and is kept exactly as it was written.
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
//
// **What a literal is, `StringLiteralSkipping` says and nothing here does.** What is left below is
// the driving of it — where to begin, what to keep, where to stop — and the driving is all this ever
// was on top of a reading of its own. Two places held one reading each, so a form neither could
// follow had to be remembered in both; the form that arrived was a literal nested in an
// interpolation, and this was the copy nobody had looked at.
func localizedCalls(in text: String) throws -> [String?] {
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

        // The argument's opening is handed to the reading a character at a time rather than compared
        // to `"`: a raw literal begins with a `#`, and the reading refuses one on the quote behind
        // it, which it can only do if it is shown both.
        var scan = StringLiteralSkipping()
        var opened = false
        while index < text.endIndex, !opened {
            let character = text[index]
            _ = try scan.isCode(character)
            if scan.isReadingALiteral {
                opened = true
            } else if character != "#" {
                break
            }
            index = text.index(after: index)
        }
        guard opened else {
            found.append(nil)
            continue
        }

        var literal = ""
        while index < text.endIndex {
            let character = text[index]
            _ = try scan.isCode(character)
            guard scan.isReadingALiteral else {
                // That character closed the literal — and a `"""` is only recognisable from its third
                // quote, so the next character is shown to the reading before this answer is kept.
                // Otherwise the empty literal at the head of a multiline one is answered as the whole
                // of it: a sentence of no characters, with nothing anywhere saying so.
                let next = text.index(after: index)
                if next < text.endIndex { _ = try scan.isCode(text[next]) }
                break
            }
            literal.append(character)
            index = text.index(after: index)
        }
        found.append(literal)
        // Past the literal, so a `String(localized: "` spelled inside one is not read as a call.
        searchFrom = index
    }
    return found
}

// Every `String(localized: "…")` literal in a file, as written.
func localizedStringLiterals(in text: String) throws -> [String] {
    try localizedCalls(in: text).compactMap { $0 }
}
