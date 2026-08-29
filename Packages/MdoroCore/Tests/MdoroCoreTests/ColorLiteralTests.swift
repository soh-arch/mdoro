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

// SwiftUI の色リテラル。`.clear` は色を持たないので除く。
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

// POL-049: `.primary` / `.secondary` are not hues, which is why they were left out above —
// but they are the OS choosing the text colour, and the app draws its own ground. Two
// palettes on one surface do not agree; 8.5's text tokens are the ones REQ-COL-020 measures
// against that ground, and the OS's are measured against nothing the app controls.
private let systemTextColours = ["primary", "secondary"]

// Everything that draws on a ground the app paints. **`PomodoroWidget` is not here.**
//
// REQ-UIX-027 (MUST) says the Live Activity must not take 8.5's tokens as they stand: 8.5.3
// guarantees them against `--bg`, and the lock screen's container is a different ground.
// REQ-COL-022 excludes the menu bar for the half of that reason they share — a ground the
// app does not paint; its other half, no information on colour alone, is its own. On that
// container the clause leaves the foreground to the system, and a palette colour there would
// be fixed and guaranteed against nothing (facts: docs/PLATFORM.md). The extension also has no
// `Theme` to ask: the appearance preference is per device (Decision 0027) and lives in the
// app, so a role there would mean putting the preference on the wire.
private let paletteOnlySources = [
    "PomodoroMac/PomodoroMac/Views",
    "PomodoroMac/PomodoroiOS/Views",
]

// `.primary,` `.primary)` and `Color.primary` are colours. `WidgetFontSize.secondary` is a
// size and `theme.textSecondary` is already a role, so what is in front decides as much as
// what follows: only the bare form and SwiftUI's own style types produce a colour.
private let styleTypesThatCarryThem = ["", "Color", "ShapeStyle", "HierarchicalShapeStyle", "AnyShapeStyle"]

private func osTextColours(in text: String) -> [String] {
    var found: [String] = []
    for name in systemTextColours {
        var searched = text.startIndex..<text.endIndex
        while let range = text.range(of: ".\(name)", range: searched) {
            let next = range.upperBound
            let ends = next == text.endIndex
                || !(text[next].isLetter || text[next].isNumber || text[next] == "_")

            var start = range.lowerBound
            while start > text.startIndex {
                let previous = text.index(before: start)
                guard text[previous].isLetter || text[previous].isNumber || text[previous] == "_" else { break }
                start = previous
            }
            let owner = String(text[start..<range.lowerBound])

            if ends, styleTypesThatCarryThem.contains(owner) { found.append(".\(name)") }
            searched = next..<text.endIndex
        }
    }
    return found
}

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

    // POL-049: the OS's text colours are a second palette on a ground the app painted.
    @Test func noViewLetsTheOSChooseItsTextColour() throws {
        for directory in paletteOnlySources {
            for (name, text) in try swiftFiles(under: directory, recursive: true) {
                let found = osTextColours(in: text)
                #expect(
                    found.isEmpty,
                    "POL-049: \(name) writes \(found.joined(separator: ", ")) — ask the theme for textPrimary / textSecondary"
                )
            }
        }
    }

    @Test func theScanTellsAColourFromAName() {
        #expect(osTextColours(in: "Text(x).foregroundStyle(.secondary)") == [".secondary"])
        #expect(osTextColours(in: "let c = Color.primary") == [".primary"])
        #expect(osTextColours(in: ".foregroundStyle(on ? .secondary : .primary)") == [".primary", ".secondary"])
        // Not colours: a font size, a role the theme already answers, a longer name.
        #expect(osTextColours(in: "size: WidgetFontSize.secondary").isEmpty)
        #expect(osTextColours(in: ".foregroundStyle(theme.textSecondary)").isEmpty)
        #expect(osTextColours(in: "let x = value.primaryKey").isEmpty)
    }

    @Test func everyPaletteOnlyDirectoryIsActuallyRead() throws {
        for directory in paletteOnlySources {
            #expect(!(try swiftFiles(under: directory, recursive: true)).isEmpty,
                    "\(directory) は読めていない。移動したか、名前が変わっている")
        }
    }

    // The exclusion above has to stay a decision and not a path that quietly holds nothing.
    // REQ-UIX-027 leaves the Live Activity's foreground to the system because 8.5.3's
    // guarantees are against `--bg` and not the lock screen's container (facts:
    // docs/PLATFORM.md), and the extension has no `Theme` to name a role with. If a theme
    // ever reaches it, that reasoning has changed and this test is where it gets read again.
    @Test func theLiveActivityIsLeftToTheSystemOnPurpose() throws {
        let widget = try swiftFiles(under: "PomodoroMac/PomodoroWidget", recursive: true)
        #expect(!widget.isEmpty, "the widget は読めていない")
        for (name, text) in widget {
            #expect(
                !text.contains("theme."),
                "REQ-UIX-027: \(name) now has a palette to ask, so POL-049's exclusion needs revisiting"
            )
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
