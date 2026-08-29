#if canImport(SwiftUI)
import SwiftUI

// REQ-COL-001 / REQ-PRT-001: the bridge that keeps colour literals out of the views.

public extension SwiftUI.Color {
    init(_ token: SRGBColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: 1)
    }

    init(_ token: SRGBColor, opacity: Double) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: opacity)
    }
}

public extension ColorMode {
    // REQ-COL-003: the path that follows the system appearance. To fix it instead, the UI layer
    // names a ColorMode itself.
    init(_ scheme: SwiftUI.ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

public extension ColorPalette {
    // REQ-COL-002: looked up by role name. A hue token is never referenced directly.
    func color(_ role: ColorRole, _ hueRole: HueRole) -> SwiftUI.Color {
        SwiftUI.Color(role.color(hueRole, in: self))
    }

    var overlayColor: SwiftUI.Color {
        SwiftUI.Color(overlay, opacity: overlayOpacity)
    }
}
#endif
