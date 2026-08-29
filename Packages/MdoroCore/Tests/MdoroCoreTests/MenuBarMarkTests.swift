import Foundation
import Testing
@testable import MdoroCore

// **A missing asset name is not an error; nothing is drawn.**
// When a name is added, run `Tools/make_icon.swift` and confirm here that it exists.
@Suite("Menu bar mark (REQ-UIX-030 / 035)")
struct MenuBarMarkTests {

    // Five levels up from Tests/MdoroCoreTests/ is the repository root.
    private static var assetsDirectory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("PomodoroMac/PomodoroMac/Assets.xcassets")
    }

    @Test func everyMarkHasAnImageSetOnDisk() throws {
        for mark in MenuBarMark.allCases {
            let imageSet = Self.assetsDirectory.appendingPathComponent("\(mark.assetName).imageset")
            #expect(FileManager.default.fileExists(atPath: imageSet.path),
                    "\(mark.assetName).imageset is missing; run Tools/make_icon.swift")
            // Unless it is a template image it does not follow the brightness of the ground and
            // stays black (REQ-COL-022).
            let contents = try String(contentsOf: imageSet.appendingPathComponent("Contents.json"), encoding: .utf8)
            #expect(contents.contains("\"template-rendering-intent\" : \"template\""),
                    "\(mark.assetName) is not registered as a template image")
        }
    }

    // An unused image left behind leaves the next person unable to tell which one is live.
    @Test func noOtherMenuBarImageSetsAreLeftBehind() throws {
        let expected = Set(MenuBarMark.allCases.map { "\($0.assetName).imageset" })
        let found = try FileManager.default
            .contentsOfDirectory(atPath: Self.assetsDirectory.path)
            .filter { $0.hasPrefix("MenuBar") }
        #expect(Set(found) == expected, "unused imageset left behind: \(Set(found).subtracting(expected))")
    }

    // The same reason as REQ-UIX-035. Reusing one picture tells no state apart from another.
    @Test func assetNamesAreDistinct() {
        #expect(Set(MenuBarMark.allCases.map(\.assetName)).count == MenuBarMark.allCases.count)
    }

    @Test func everyRunStateMapsToAMark() {
        let expected: [RunState: MenuBarMark] = [
            .idle: .idle,
            .running: .running,
            .paused: .paused,
            // Within the grace, the same mark as idle. The mark does not change when the grace
            // runs out and it falls to IDLE.
            .finished: .idle,
            // Waiting for a decision is the same as paused, in that time is not moving.
            .pendingDecision: .paused,
        ]
        for (state, mark) in expected {
            #expect(MenuBarMark.mark(for: state) == mark, "\(state) maps to \(MenuBarMark.mark(for: state))")
        }
        // Add a RunState and add it here too. The count is what holds the coverage.
        #expect(expected.count == 5)
    }
}
