import Testing
import Foundation
@testable import MdoroCore

// REQ-PER-011 / REQ-PER-010: **a state read back off the disk has not been synced, and the screen
// has to say so — whatever route the launch took.**
//
// The received-at time was shown (REQ-PER-011's first half), but the "not synced yet" half rested on
// `isAwaitingFirstSync`, and the one place that raised it was `MdoroiOSApp`'s notification handler.
// A user who simply opened the app was shown a restored state with nothing saying it was old; how
// old it was could be read off the time beside it and nowhere else. REQ-NTF-011 (SHOULD) describes
// the notification route; REQ-PER-011 (MUST) describes this one, and it was the one going unserved.
//
// These read the iPhone target's source because `swift test` cannot link it — the same route
// `StartingTwiceTests`, `ColorLiteralTests` and `TestHostTests` take to rules kept outside this
// package, and the only route that runs anywhere but the reader's own Mac: **no runner builds the
// iPhone side at all.** `PomodoroiOSTests` carries the half that actually restores a snapshot and
// reads the flag back; it needs a simulator, and this does not.

private let clientModel = "PomodoroMac/PomodoroiOS/ClientModel.swift"
private let iOSApp = "PomodoroMac/PomodoroiOS/MdoroiOSApp.swift"
private let connectionViews = "PomodoroMac/PomodoroiOS/Views/ConnectionViews.swift"

// **A scan whose anchor has been renamed finds nothing to object to, and passes.** That is the one
// failure these scans exist to prevent, arriving through the scans themselves, so a missing anchor
// is an error rather than an absence.
private struct MissingAnchor: Error, CustomStringConvertible {
    let path: String
    let anchor: String
    var description: String {
        "\(path) no longer contains `\(anchor)` — it was renamed, and this scan was watching nothing"
    }
}

// What a block does, from the brace that opens it to the one that closes it, comments already gone.
// **Brace counting, so a nested closure does not end the block early** — and it takes the braces at
// face value, which is fair for the blocks read here and would not be for a body carrying one in a
// string literal.
//
// Counting starts at the last `{` **inside the signature**, not at the character it ends on: one of
// these anchors is a closure argument (`receivedSnapshot: { [weak self] snapshot in`) whose brace
// sits in the middle of it, and starting after that brace opens at depth zero and closes at minus one.
private func block(_ path: String, after signature: String) throws -> String {
    let text = withoutComments(try source(path))
    guard let opening = text.range(of: signature) else {
        throw MissingAnchor(path: path, anchor: signature)
    }
    guard let brace = text[opening].lastIndex(of: "{") else {
        throw MissingAnchor(path: path, anchor: "an opening brace in \(signature)")
    }
    var depth = 0
    var index = brace
    let start = index
    while index < text.endIndex {
        if text[index] == "{" { depth += 1 }
        if text[index] == "}" {
            depth -= 1
            if depth == 0 { return String(text[start...index]) }
        }
        index = text.index(after: index)
    }
    throw MissingAnchor(path: path, anchor: "the brace closing \(signature)")
}

private func text(of path: String) throws -> String {
    withoutComments(try source(path))
}

@Suite("A restored state says it is not synced (REQ-PER-011)")
struct ARestoredStateSaysItIsNotSyncedTests {

    // **The one that was broken.** Restoring the snapshot put it on the screen and said nothing
    // about it not being settled.
    @Test func restoringTheLastSnapshotSaysItIsNotSyncedYet() throws {
        let body = try block(clientModel, after: "func restoreLastSnapshot() {")
        let raised = body.contains("isAwaitingFirstSync = true")
        #expect(raised, "REQ-PER-011: a restored state goes on the screen without being called unsynced")
    }

    // **And only when there is something to show.** A phone that has never been connected has no
    // state on its screen to call old, and a banner asking the user to wait for a sync of nothing
    // is a banner about nothing (REQ-UIX-046). The order of the two statements is the whole of it:
    // the flag goes up after the `guard` that gives up when nothing was stored.
    @Test func aLaunchWithNothingStoredRaisesNothing() throws {
        let body = try block(clientModel, after: "func restoreLastSnapshot() {")
        guard let guardStatement = body.range(of: "guard let data") else {
            throw MissingAnchor(path: clientModel, anchor: "guard let data in restoreLastSnapshot()")
        }
        guard let raised = body.range(of: "isAwaitingFirstSync = true") else {
            throw MissingAnchor(path: clientModel, anchor: "isAwaitingFirstSync = true in restoreLastSnapshot()")
        }
        let afterTheGuard = guardStatement.lowerBound < raised.lowerBound
        #expect(afterTheGuard,
                "REQ-PER-011 / REQ-UIX-046: the flag is raised before it is known that anything was restored")
    }

    // **The way back down.** One arriving `stateSnapshot` is what ends it; nothing else may.
    @Test func anArrivingSnapshotPutsItBackDown() throws {
        let body = try block(clientModel, after: "receivedSnapshot: { [weak self] snapshot in")
        let lowered = body.contains("isAwaitingFirstSync = false")
        #expect(lowered, "REQ-PER-011: a state received over a live connection is still called unsynced")

        // And nothing else puts it down, so the flag cannot be lowered by anything that is not a
        // snapshot off the wire. **The declaration is not one of them** — `= false` there is where the
        // flag starts, not somewhere it is lowered, and counting the spelling alone reads it as a
        // second place (it did, the first time this ran).
        let whole = try text(of: clientModel)
        let lowerings = whole.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("isAwaitingFirstSync = false") && !$0.contains("var isAwaitingFirstSync") }
        #expect(lowerings.count == 1,
                "the flag is put down in \(lowerings.count) places; only an arriving snapshot may: \(lowerings)")
    }

    // REQ-NTF-011: **the notification route is untouched.** It reaches the same flag, and it is the
    // one that covers a tap with nothing stored to restore.
    @Test func theNotificationRouteStillRaisesTheSameFlag() throws {
        let model = try text(of: clientModel)
        let raises = model.contains("func markAwaitingSync() { isAwaitingFirstSync = true }")
        #expect(raises, "REQ-NTF-011: `markAwaitingSync()` no longer raises the flag")

        let app = try text(of: iOSApp)
        let wired = app.contains("markAwaitingSync()")
        #expect(wired, "REQ-NTF-011: a notification tap no longer reaches `markAwaitingSync()`")
    }

    // **And the flag reaches the screen.** Raising it changes nothing unless the banner is shown for
    // it and the words are gated on it.
    @Test func theScreenIsStillGatedOnTheFlag() throws {
        let views = try text(of: connectionViews)
        let gated = views.contains("if model.isAwaitingFirstSync {")
        #expect(gated, "REQ-PER-011: the words are no longer shown for the flag")

        let says = views.contains("Syncing")
        #expect(says, "REQ-PER-011: nothing on the banner says a sync is outstanding")

        let attention = try block(connectionViews, after: "private var needsAttention: Bool {")
        let shown = attention.contains("model.isAwaitingFirstSync")
        #expect(shown, "REQ-UIX-046: the banner is not shown for a state that has not been synced")
    }
}
