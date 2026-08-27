#if canImport(SwiftUI)
import SwiftUI

// REQ-COL-001: ビュー内に色リテラルを書かせないための橋渡し。
// Mac 版と iPhone 版で二重に実装しないよう共有コードに置く (REQ-PRT-001)。
// 具体的な配色の引き回し方 (Environment に載せるか等) は UI 層の判断に委ねる。

public extension SwiftUI.Color {
    init(_ token: SRGBColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: 1)
    }

    init(_ token: SRGBColor, opacity: Double) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: opacity)
    }
}

public extension ColorMode {
    // REQ-COL-003: システムの外観設定に追従する経路。
    // ライト固定・ダーク固定は UI 層が ColorMode を直接指定して実現する。
    init(_ scheme: SwiftUI.ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

public extension ColorPalette {
    // REQ-COL-002: 役割名で引く。色相名トークンを直接参照させない。
    func color(_ role: ColorRole, _ hueRole: HueRole) -> SwiftUI.Color {
        SwiftUI.Color(role.color(hueRole, in: self))
    }

    var overlayColor: SwiftUI.Color {
        SwiftUI.Color(overlay, opacity: overlayOpacity)
    }
}
#endif
