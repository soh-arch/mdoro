import Foundation
import Testing
@testable import MdoroCore

// **存在しないアセット名は、エラーにならず何も描かれない。**
// 名前を増やしたら `Tools/make_icon.swift` を回し、ここで実在を確かめること。
@Suite("Menu bar mark (REQ-UIX-030 / 035)")
struct MenuBarMarkTests {

    // Tests/MdoroCoreTests/ から5つ上がリポジトリのルート。
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
            // テンプレート画像でないと、地の明るさに追随せず黒いままになる（REQ-COL-022）。
            let contents = try String(contentsOf: imageSet.appendingPathComponent("Contents.json"), encoding: .utf8)
            #expect(contents.contains("\"template-rendering-intent\" : \"template\""),
                    "\(mark.assetName) is not registered as a template image")
        }
    }

    // 使っていない画像が残っていると、次に触る人がどれが生きているのか分からなくなる。
    @Test func noOtherMenuBarImageSetsAreLeftBehind() throws {
        let expected = Set(MenuBarMark.allCases.map { "\($0.assetName).imageset" })
        let found = try FileManager.default
            .contentsOfDirectory(atPath: Self.assetsDirectory.path)
            .filter { $0.hasPrefix("MenuBar") }
        #expect(Set(found) == expected, "unused imageset left behind: \(Set(found).subtracting(expected))")
    }

    // REQ-UIX-035 と同じ理由。同じ絵を使い回すと、状態の区別にならない。
    @Test func assetNamesAreDistinct() {
        #expect(Set(MenuBarMark.allCases.map(\.assetName)).count == MenuBarMark.allCases.count)
    }

    @Test func everyRunStateMapsToAMark() {
        let expected: [RunState: MenuBarMark] = [
            .idle: .idle,
            .running: .running,
            .paused: .paused,
            // 猶予中は待機と同じ印。猶予が切れて IDLE に落ちても印が変わらない。
            .finished: .idle,
            // 判断待ちは「時間が動いていない」点で一時停止と同じ。
            .pendingDecision: .paused,
        ]
        for (state, mark) in expected {
            #expect(MenuBarMark.mark(for: state) == mark, "\(state) maps to \(MenuBarMark.mark(for: state))")
        }
        // RunState が増えたらここも増やす。網羅していることを数で担保する。
        #expect(expected.count == 5)
    }
}
