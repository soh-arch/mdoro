import Testing
@testable import MdoroCore

#if canImport(AppKit)
import AppKit
private func symbolExists(_ name: String) -> Bool {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
}
#elseif canImport(UIKit)
import UIKit
private func symbolExists(_ name: String) -> Bool {
    UIImage(systemName: name) != nil
}
#endif

// **存在しない SF Symbol 名は、エラーにならず何も描かれない。**
// `timer.slash`（実在しない）をメニューバーに指定した結果、項目が丸ごと消え、
// REQ-UIX-030（メニューバーに常駐して残り時間を常時表示）が満たされていない状態に気づけなかった。
// 名前を増やしたらここに足すこと。
@Suite("SF Symbol 名の実在 (REQ-UIX-030 / 035)")
struct SymbolNameTests {

    // `peerSymbolName` は `#if os(macOS)` で分岐するため、テストを走らせた側の名前しか通らない。
    // **もう片方の名前は、名指しで確かめる。** SF Symbols のカタログは両プラットフォームで共通。
    @Test func peerSymbolsOfBothPlatformsExist() {
        for name in ["iphone.gen3", "iphone.gen3.slash",
                     "laptopcomputer", "laptopcomputer.slash",
                     "arrow.trianglehead.2.clockwise"] {
            #expect(symbolExists(name), "\(name) が実在しない")
        }
    }

    @Test func connectionStatusSymbolsExist() {
        for status in ConnectionStatus.allCases {
            #expect(symbolExists(status.menuBarSymbolName),
                    "\(status): メニューバー用の \(status.menuBarSymbolName) が実在しない")
            #expect(symbolExists(status.symbolName),
                    "\(status): 画面用の \(status.symbolName) が実在しない")
            #expect(symbolExists(status.peerSymbolName),
                    "\(status): 相手端末用の \(status.peerSymbolName) が実在しない")
        }
    }

    // REQ-UIX-035: 接続状態は形で区別する。同じ形を使い回すと区別にならない。
    @Test func connectionStatusSymbolsAreDistinct() {
        let menuBar = Set(ConnectionStatus.allCases.map(\.menuBarSymbolName))
        #expect(menuBar.count == ConnectionStatus.allCases.count)
        let onScreen = Set(ConnectionStatus.allCases.map(\.symbolName))
        #expect(onScreen.count == ConnectionStatus.allCases.count)
    }
}
