import Testing
import Foundation

// The tools for reading the repository's own sources live in `RepositorySources.swift`.
//
// REQ-NTF-005: the end-of-session notification is sent as Time Sensitive so that it arrives
// during a Focus mode, and `Notify during Focus modes` is the switch that asks for it. **Asking
// is not arriving.** `.timeSensitive` needs the Time Sensitive Notifications capability, this
// project carries no entitlements file at all, and Mdoro is distributed as source to build
// (SPEC chapter 14) — so the switch is one a user can set, save and read back out of the
// diagnostic log with nothing on the other end of it
// (`docs/platform/0016-what-a-focus-breaking-notification-needs.md`).
//
// So the screen says so, in fixed text, beside the toggle it qualifies. The rule lives in a view
// `swift test` cannot link, so this scan reads its source — the same route `MenuBarMenuTests`
// and `ColorLiteralTests` take.
//
// **Both ways the note can stop working are quiet ones.** A note that drifts away from its
// toggle, or behind a condition, still reads correctly in the source; and a `Text("…")` whose
// key is not in the catalogue renders as its key, which in an English-only app looks exactly
// right on screen (`StringCatalogTests` keeps the rest of that).

private let presetEditor = "PomodoroMac/PomodoroMac/Views/PresetEditorView.swift"
private let macCatalogue = "PomodoroMac/PomodoroMac/Localizable.xcstrings"

private let toggleCall = "Toggle(\"Notify during Focus modes\""
// The wording, exactly as the view asks for it, which is also the key Xcode extracts.
private let theNote = "This build does not carry the Time Sensitive Notifications capability, so end-of-session notifications are not expected to arrive until Focus ends. The session itself ends on time."

// A scan whose anchor has been renamed finds nothing to object to, and nothing to object to
// reads exactly like nothing wrong. Every lookup here fails loudly instead.
private struct MissingAnchor: Error, CustomStringConvertible {
    let path: String
    let anchor: String
    var description: String {
        "\(path) no longer contains `\(anchor)` — it was renamed or removed, and this scan was watching nothing"
    }
}

// Comments are where a sentence can sit without being on screen, so they come out first.
private func codeLines(of path: String) throws -> [String] {
    let lines = withoutComments(try source(path)).split(separator: "\n", omittingEmptySubsequences: false)
    guard !lines.isEmpty else { throw MissingAnchor(path: path, anchor: "any line at all") }
    return lines.map(String.init)
}

private func line(containing needle: String, in lines: [String], of path: String) throws -> Int {
    guard let index = lines.firstIndex(where: { $0.contains(needle) }) else {
        throw MissingAnchor(path: path, anchor: needle)
    }
    return index
}

private func indentation(of line: String) -> Int {
    line.prefix { $0 == " " }.count
}

private func catalogueKeys(_ path: String) throws -> Set<String> {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let strings = root?["strings"] as? [String: Any], !strings.isEmpty else {
        throw MissingAnchor(path: path, anchor: "a non-empty `strings` object")
    }
    return Set(strings.keys)
}

@Suite("The Focus toggle says what it cannot do (REQ-NTF-005)")
struct TheToggleSaysWhatItCannotDoTests {

    // A note about a toggle, placed anywhere else in a Form, is a note about whatever it lands
    // next to. Nothing but blank lines and comments may come between the two.
    @Test func theNoteStandsBesideTheToggleItQualifies() throws {
        let lines = try codeLines(of: presetEditor)
        let toggle = try line(containing: toggleCall, in: lines, of: presetEditor)
        let note = try line(containing: theNote, in: lines, of: presetEditor)
        let between = lines[(min(toggle, note) + 1)..<max(toggle, note)]
        #expect(
            between.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty },
            "REQ-NTF-005: \(presetEditor) has code between `Notify during Focus modes` and the note that qualifies it — the note now reads as a note about that code instead"
        )
    }

    // The capability is settled when the app is built, so the note is not a judgement made at
    // run time: same indentation as the toggle means the same builder block, not the inside of
    // an `if`. **And `UNNotificationSettings.timeSensitiveSetting` stays out of it** — what it
    // returns with no entitlement is undocumented, so a branch on it fails in a way nobody sees.
    @Test func theNoteIsNotConditional() throws {
        let lines = try codeLines(of: presetEditor)
        let toggle = try line(containing: toggleCall, in: lines, of: presetEditor)
        let note = try line(containing: theNote, in: lines, of: presetEditor)
        #expect(
            indentation(of: lines[note]) == indentation(of: lines[toggle]),
            "REQ-NTF-005: the note in \(presetEditor) is indented \(indentation(of: lines[note])) where the toggle is indented \(indentation(of: lines[toggle])) — it has been nested inside something, and a note that can be skipped is one the reader may never get"
        )
        #expect(
            !lines.joined(separator: "\n").contains("timeSensitiveSetting"),
            "REQ-NTF-005: \(presetEditor) reads `UNNotificationSettings.timeSensitiveSetting`, whose value with no entitlement Apple does not document (docs/platform/0016)"
        )
    }

    // Decision 0022: a lookup that misses returns the key, and the key is this whole sentence in
    // English — so on screen a missing entry looks like a note that is working.
    @Test func theNoteIsAKeyInTheMacCatalogue() throws {
        let keys = try catalogueKeys(macCatalogue)
        #expect(
            keys.contains(theNote),
            "Decision 0022: \(presetEditor) asks for the Focus-mode note, which \(macCatalogue) does not have"
        )
    }
}
