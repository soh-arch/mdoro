import Testing
import Foundation
@testable import MdoroCore

// REQ-TIM-030 (SPEC 4.6): `startWork` / `startBreak` are refused while RUNNING / PAUSED, and the
// refusal never reaches the Mac's screen — so a `Start Next` item in the live half of the menu is
// a button that does nothing when pressed. Measured on the user's machine (2026-09-02): while the
// menu bar showed a running timer, `Start Next` was pressed and nothing happened.
//
// The rule lives in a view `swift test` cannot link, so the scan reads its source — the same
// route `StartingTwiceTests` and `ColorLiteralTests` take.

private let menuBarViews = "PomodoroMac/PomodoroMac/Views/MenuBarViews.swift"

private struct MissingAnchor: Error, CustomStringConvertible {
    let path: String
    let anchor: String
    var description: String {
        "\(path) no longer contains `\(anchor)` — it was renamed, and this scan was watching nothing"
    }
}

// The live half of the top level: from the first `if isLive {` to the `Divider()` that closes it.
private func liveBlock() throws -> String {
    let body = withoutComments(try source(menuBarViews))
    guard let opening = body.range(of: "if isLive {") else {
        throw MissingAnchor(path: menuBarViews, anchor: "if isLive {")
    }
    let rest = body[opening.upperBound...]
    guard let divider = rest.range(of: "Divider()") else {
        throw MissingAnchor(path: menuBarViews, anchor: "Divider() after if isLive {")
    }
    return String(rest[rest.startIndex..<divider.lowerBound])
}

@Suite("The live menu holds no dead button")
struct MenuBarMenuTests {

    // REQ-TIM-030: while RUNNING / PAUSED the state machine refuses a start, so the menu must not
    // offer one. `skip` is the accepted way out of a live session (4.6).
    @Test func theLiveMenuDoesNotOfferAStart() throws {
        let block = try liveBlock()
        #expect(
            !block.contains("startNextSession"),
            "REQ-TIM-030: the live block of \(menuBarViews) offers Start Next, whose command the state machine refuses from RUNNING / PAUSED — a button that does nothing when pressed"
        )
        // The anchor is watching the right block: skip is what belongs here.
        #expect(
            block.contains(".skip"),
            "the live block of \(menuBarViews) no longer sends .skip — the scan's anchor may be watching the wrong block"
        )
    }
}
