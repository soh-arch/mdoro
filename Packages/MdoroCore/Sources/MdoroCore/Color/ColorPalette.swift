import Foundation

// REQ-COL-003: two palettes, light and dark. The three-way choice — follow the system, or fix
// either one — is resolved by the UI layer and never reaches here.
public enum ColorMode: String, CaseIterable, Sendable {
    case light
    case dark
}

// REQ-COL-002 / 8.5.2: views never reference this directly. They reference ColorRole.
public enum ColorHue: String, CaseIterable, Sendable {
    case ink    // indigo 235°
    case sage   // celadon 142°
    case ochre  // yellow ochre 66°
    case clay   // red ochre 30°
}

// The five roles of 8.5.3. **Take the wrong one and the contrast guarantee is gone.**
public enum HueRole: String, CaseIterable, Sendable {
    case subtle
    case subtleHover
    case line
    case graphic
    case solid
    case solidHover
    case text
    case onSolid
}

public struct HueSet: Sendable {
    public let subtle, subtleHover, line, graphic, solid, solidHover, text, onSolid: SRGBColor

    public subscript(role: HueRole) -> SRGBColor {
        switch role {
        case .subtle: return subtle
        case .subtleHover: return subtleHover
        case .line: return line
        case .graphic: return graphic
        case .solid: return solid
        case .solidHover: return solidHover
        case .text: return text
        case .onSolid: return onSolid
        }
    }
}

// 8.5.3 token definitions. REQ-COL-001: the only source of colour. No colour literal may be
// written inside a view.
public struct ColorPalette: Sendable {
    public let bg: SRGBColor            // --bg
    public let bgSunken: SRGBColor      // --bg-sunken
    public let surface: SRGBColor       // --surface
    public let surfaceRaised: SRGBColor // --surface-raised
    public let borderSubtle: SRGBColor  // --border-subtle
    public let border: SRGBColor        // --border
    public let borderStrong: SRGBColor  // --border-strong
    public let textDisabled: SRGBColor  // --text-disabled
    public let textTertiary: SRGBColor  // --text-faint
    public let textSecondary: SRGBColor // --text-muted
    public let textPrimary: SRGBColor   // --text
    public let focusRing: SRGBColor     // --focus-ring
    public let overlay: SRGBColor       // the colour component of --overlay
    public let overlayOpacity: Double   // the opacity of --overlay

    private let ink: HueSet
    private let sage: HueSet
    private let ochre: HueSet
    private let clay: HueSet

    public func hue(_ hue: ColorHue) -> HueSet {
        switch hue {
        case .ink: return ink
        case .sage: return sage
        case .ochre: return ochre
        case .clay: return clay
        }
    }

    public func color(_ hue: ColorHue, _ role: HueRole) -> SRGBColor {
        self.hue(hue)[role]
    }

    // REQ-COL-020: `-text` guarantees at least 4.5 against all four of these surfaces.
    public var textBackgrounds: [SRGBColor] { [bg, bgSunken, surface, surfaceRaised] }

    public static func palette(for mode: ColorMode) -> ColorPalette {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        }
    }

    public static let light = ColorPalette(
        bg: SRGBColor(hex: "#F7F3ED"),
        bgSunken: SRGBColor(hex: "#F0ECE4"),
        surface: SRGBColor(hex: "#FFFEFB"),
        surfaceRaised: SRGBColor(hex: "#FFFFFF"),
        borderSubtle: SRGBColor(hex: "#D8D3CB"),
        border: SRGBColor(hex: "#B5B0A7"),
        borderStrong: SRGBColor(hex: "#908A80"),
        textDisabled: SRGBColor(hex: "#918C82"),
        textTertiary: SRGBColor(hex: "#70695F"),
        textSecondary: SRGBColor(hex: "#534C41"),
        textPrimary: SRGBColor(hex: "#231E16"),
        focusRing: SRGBColor(hex: "#22759E"),
        overlay: SRGBColor(hex: "#231E16"),
        overlayOpacity: 0.38,
        ink: HueSet(
            subtle: SRGBColor(hex: "#DDEBF4"), subtleHover: SRGBColor(hex: "#CEE1EC"),
            line: SRGBColor(hex: "#93B1C3"), graphic: SRGBColor(hex: "#22759E"),
            solid: SRGBColor(hex: "#22759E"), solidHover: SRGBColor(hex: "#0F6992"),
            text: SRGBColor(hex: "#316A89"), onSolid: SRGBColor(hex: "#FFFFFF")
        ),
        sage: HueSet(
            subtle: SRGBColor(hex: "#E1ECE0"), subtleHover: SRGBColor(hex: "#D4E2D2"),
            line: SRGBColor(hex: "#9CB29A"), graphic: SRGBColor(hex: "#648F5F"),
            solid: SRGBColor(hex: "#4F794A"), solidHover: SRGBColor(hex: "#436D3F"),
            text: SRGBColor(hex: "#486E44"), onSolid: SRGBColor(hex: "#FFFFFF")
        ),
        ochre: HueSet(
            subtle: SRGBColor(hex: "#F3E7DC"), subtleHover: SRGBColor(hex: "#EBDBCD"),
            line: SRGBColor(hex: "#C0A892"), graphic: SRGBColor(hex: "#7E4A01"),
            solid: SRGBColor(hex: "#9B621B"), solidHover: SRGBColor(hex: "#8F5607"),
            text: SRGBColor(hex: "#845C32"), onSolid: SRGBColor(hex: "#FFFFFF")
        ),
        clay: HueSet(
            subtle: SRGBColor(hex: "#F7E5E2"), subtleHover: SRGBColor(hex: "#F0D9D5"),
            line: SRGBColor(hex: "#C7A49E"), graphic: SRGBColor(hex: "#9F4A3E"),
            solid: SRGBColor(hex: "#AB5649"), solidHover: SRGBColor(hex: "#9E493D"),
            text: SRGBColor(hex: "#8E554B"), onSolid: SRGBColor(hex: "#FFFFFF")
        )
    )

    public static let dark = ColorPalette(
        bg: SRGBColor(hex: "#13110D"),
        bgSunken: SRGBColor(hex: "#090705"),
        surface: SRGBColor(hex: "#1E1B17"),
        surfaceRaised: SRGBColor(hex: "#282520"),
        borderSubtle: SRGBColor(hex: "#39362F"),
        border: SRGBColor(hex: "#524D45"),
        borderStrong: SRGBColor(hex: "#6B665C"),
        textDisabled: SRGBColor(hex: "#666157"),
        textTertiary: SRGBColor(hex: "#969084"),
        textSecondary: SRGBColor(hex: "#ABA497"),
        textPrimary: SRGBColor(hex: "#EBE5DA"),
        focusRing: SRGBColor(hex: "#58A6D1"),
        overlay: SRGBColor(hex: "#13110D"),
        overlayOpacity: 0.62,
        ink: HueSet(
            subtle: SRGBColor(hex: "#1F2A31"), subtleHover: SRGBColor(hex: "#293842"),
            line: SRGBColor(hex: "#3A5566"), graphic: SRGBColor(hex: "#58A6D1"),
            solid: SRGBColor(hex: "#58A6D1"), solidHover: SRGBColor(hex: "#65B3DF"),
            text: SRGBColor(hex: "#5D97B8"), onSolid: SRGBColor(hex: "#13110D")
        ),
        sage: HueSet(
            subtle: SRGBColor(hex: "#232B22"), subtleHover: SRGBColor(hex: "#2E392C"),
            line: SRGBColor(hex: "#435641"), graphic: SRGBColor(hex: "#9BC996"),
            solid: SRGBColor(hex: "#7DA877"), solidHover: SRGBColor(hex: "#8AB685"),
            text: SRGBColor(hex: "#729A6E"), onSolid: SRGBColor(hex: "#13110D")
        ),
        ochre: HueSet(
            subtle: SRGBColor(hex: "#30281F"), subtleHover: SRGBColor(hex: "#403428"),
            line: SRGBColor(hex: "#634E39"), graphic: SRGBColor(hex: "#AF7431"),
            solid: SRGBColor(hex: "#CE9251"), solidHover: SRGBColor(hex: "#DC9F5E"),
            text: SRGBColor(hex: "#B2875D"), onSolid: SRGBColor(hex: "#13110D")
        ),
        clay: HueSet(
            subtle: SRGBColor(hex: "#332724"), subtleHover: SRGBColor(hex: "#44322F"),
            line: SRGBColor(hex: "#684B45"), graphic: SRGBColor(hex: "#D57B6D"),
            solid: SRGBColor(hex: "#E18577"), solidHover: SRGBColor(hex: "#EF9283"),
            text: SRGBColor(hex: "#BE8076"), onSolid: SRGBColor(hex: "#13110D")
        )
    )
}
