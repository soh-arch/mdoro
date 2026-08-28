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
// 実在しない名前を指定するとメニューバー項目が丸ごと消える。名前を増やしたらここに足すこと。
@Suite("SF Symbol names exist (REQ-UIX-030 / 035)")
struct SymbolNameTests {

    // `peerSymbolName` は `#if os(macOS)` で分岐するため、テストを走らせた側の名前しか通らない。
    // **もう片方の名前は、名指しで確かめる。** SF Symbols のカタログは両プラットフォームで共通。
    @Test func peerSymbolsOfBothPlatformsExist() {
        for name in ["iphone.gen3", "iphone.gen3.slash",
                     "laptopcomputer", "laptopcomputer.slash",
                     "arrow.trianglehead.2.clockwise",
                     // 設定タブとタスク一覧で使う名前も、ここで実在を確かめる。
                     "timer", "gearshape", "folder", "paintpalette",
                     "largecircle.fill.circle", "circle",
                     // Live Activity のセッション記号。
                     "cup.and.saucer", "moon.zzz"] {
            #expect(symbolExists(name), "\(name) does not exist")
        }
    }

    @Test func connectionStatusSymbolsExist() {
        for status in ConnectionStatus.allCases {
            #expect(symbolExists(status.symbolName),
                    "\(status): on-screen symbol \(status.symbolName) does not exist")
            #expect(symbolExists(status.peerSymbolName),
                    "\(status): peer-device symbol \(status.peerSymbolName) does not exist")
        }
    }

    // REQ-COL-010: 接続状態は色だけでなく形でも区別する。同じ形を使い回すと区別にならない。
    // メニューバーの印は接続状態を示さない（Decision 0031）ので、ここでは見ない。
    @Test func connectionStatusSymbolsAreDistinct() {
        let onScreen = Set(ConnectionStatus.allCases.map(\.symbolName))
        #expect(onScreen.count == ConnectionStatus.allCases.count)
        let peer = Set(ConnectionStatus.allCases.map(\.peerSymbolName))
        #expect(peer.count == ConnectionStatus.allCases.count)
    }
}
