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

// **A missing SF Symbol name is not an error; nothing is drawn.**
// Name one that does not exist and the whole menu bar item disappears. When a name is added, add
// it here.
@Suite("SF Symbol names exist (REQ-UIX-030 / 035)")
struct SymbolNameTests {

    // `peerSymbolName` branches on `#if os(macOS)`, so only the name for the side the tests ran on
    // goes through. **The other name is checked by naming it.** The SF Symbols catalogue is common
    // to both platforms.
    @Test func peerSymbolsOfBothPlatformsExist() {
        for name in ["iphone.gen3", "iphone.gen3.slash",
                     "laptopcomputer", "laptopcomputer.slash",
                     "arrow.trianglehead.2.clockwise",
                     // The names used by the settings tabs and the task list are checked here too.
                     "timer", "gearshape", "folder", "paintpalette",
                     "largecircle.fill.circle", "circle",
                     // The session symbols of the Live Activity.
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

    // REQ-COL-010: connection state is told apart by shape as well as colour. Reusing one shape
    // tells nothing apart. The menu bar mark does not show the connection state (Decision 0031),
    // so it is not looked at here.
    @Test func connectionStatusSymbolsAreDistinct() {
        let onScreen = Set(ConnectionStatus.allCases.map(\.symbolName))
        #expect(onScreen.count == ConnectionStatus.allCases.count)
        let peer = Set(ConnectionStatus.allCases.map(\.peerSymbolName))
        #expect(peer.count == ConnectionStatus.allCases.count)
    }
}
