import Testing
import Foundation
@testable import MdoroCore

// REQ-COL-001 / 002 / Decision 0007: a view names a role and the palette answers with a
// colour. A hue written into a view leaves that route entirely — nothing checks its contrast,
// nothing swaps it between light and dark, and REQ-COL-020 measures a value the screen no
// longer shows. The audit (POL-041) found six of them still in the Mac's views, two of which
// sat in a file where the same kind of line had already been converted, so this is the sort
// of thing that comes back one line at a time.
//
// The palette cannot catch this on its own: a view that never calls it is exactly the case.
// So the check reads the app's source, which is also how `MenuBarMarkTests` reaches the
// asset catalogue. `swift test` cannot link the app targets, and the Mac's own test target
// does not run in CI, so this is where the rule can actually be held.

// SwiftUI の色リテラル。`.clear` は色を持たないので除く。`.primary` / `.secondary` は
// OS の意味色であって色相ではない（役割名への置き換えは意匠の判断なので、ここでは見ない）。
private let hueLiterals = [
    "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue",
    "indigo", "purple", "pink", "brown", "gray", "grey", "black", "white",
]

// Views and widgets: everything that draws. `MdoroCore` is excluded on purpose — the palette
// is where the values are allowed to be written down.
private let drawingSources = [
    "PomodoroMac/PomodoroMac/Views",
    "PomodoroMac/PomodoroiOS/Views",
    "PomodoroMac/PomodoroWidget",
]

// `.red,` `.red)` `Color.red` all match; `WidgetFontSize.secondary` and a name that merely
// starts with one of these do not, because the character after has to end the token.
private func literals(in text: String) -> [String] {
    var found: [String] = []
    for hue in hueLiterals {
        var searched = text.startIndex..<text.endIndex
        while let range = text.range(of: ".\(hue)", range: searched) {
            let next = range.upperBound
            let ends = next == text.endIndex
                || !(text[next].isLetter || text[next].isNumber || text[next] == "_")
            if ends { found.append(".\(hue)") }
            searched = next..<text.endIndex
        }
    }
    return found
}

@Suite("Views name a role, not a colour (REQ-COL-001 / 002 / Decision 0007)")
struct ColorLiteralTests {

    @Test func noViewWritesAHueOfItsOwn() throws {
        for directory in drawingSources {
            for (name, text) in try swiftFiles(under: directory, recursive: true) {
                let found = literals(in: text)
                #expect(
                    found.isEmpty,
                    "REQ-COL-001: \(name) writes \(found.joined(separator: ", ")) — ask the theme for a role instead"
                )
            }
        }
    }

    // 走査そのものが生きていることを確かめる。**空振りする検査は、通っている検査と区別がつかない。**
    @Test func theScanWouldSeeAHueIfOneCameBack() {
        #expect(literals(in: "Text(x).foregroundStyle(.red)") == [".red"])
        #expect(literals(in: "let c = Color.orange") == [".orange"])
        #expect(literals(in: "size: WidgetFontSize.secondary") == [])
        #expect(literals(in: "let redacted = value.redacted") == [])
    }

    // 走査するつもりだった場所が本当に読めていること。パスが動けば黙って0件になる。
    @Test func everyDrawingDirectoryIsActuallyRead() throws {
        for directory in drawingSources {
            let files = try swiftFiles(under: directory, recursive: true)
            #expect(!files.isEmpty, "\(directory) は読めていない。移動したか、名前が変わっている")
        }
    }

    // REQ-COL-011 / 012 と同じ罠。`-line` を文字色に渡すと `precondition` で落ちるので、
    // POL-041 で選んだ役と役割の組が実行時に通ることを、実際に引いて確かめる。
    @Test func theRolesTheViewsNowAskForAreAllowed() {
        for mode in ColorMode.allCases {
            let palette = ColorPalette.palette(for: mode)
            for role in [ColorRole.danger, .warning] {
                #expect(role.permittedRoles.contains(.text), "\(role) は -text を許していない")
                _ = role.color(.text, in: palette)
            }
        }
    }
}
