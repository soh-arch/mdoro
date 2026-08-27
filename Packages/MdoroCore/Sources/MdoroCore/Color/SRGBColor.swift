import Foundation

// REQ-COL-020: コントラスト比と ΔE を自動検証するため、色を計算可能な値として保持する。
// 8.5 のトークン表は hex で書かれているが、hex は生成物であり (REQ-COL-005)、
// 比較・検証はすべてここでの数値変換を通して行う。
public struct SRGBColor: Equatable, Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    // 8.5.3 のトークン表をそのまま書き写せるようにする。不正な文字列は設計時に気づくべき誤りなので
    // Optional にせず停止させる。
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        precondition(digits.count == 6, "hex must have 6 digits: \(hex)")
        guard let value = UInt32(digits, radix: 16) else {
            preconditionFailure("hex is not readable: \(hex)")
        }
        self.red = Double((value >> 16) & 0xFF) / 255
        self.green = Double((value >> 8) & 0xFF) / 255
        self.blue = Double(value & 0xFF) / 255
    }

    public var hex: String {
        func channel(_ v: Double) -> Int { Int((v.clamped01 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    // MARK: - 線形化

    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func delinearize(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }

    public var linear: (r: Double, g: Double, b: Double) {
        (Self.linearize(red), Self.linearize(green), Self.linearize(blue))
    }

    public init(linearR: Double, linearG: Double, linearB: Double) {
        self.init(
            red: Self.delinearize(linearR.clamped01),
            green: Self.delinearize(linearG.clamped01),
            blue: Self.delinearize(linearB.clamped01)
        )
    }

    // MARK: - 輝度とコントラスト

    // WCAG 2.x の相対輝度。REQ-COL-021 が順序の維持を求める「絶対輝度」もこの値を指す (8.5.5)。
    public var relativeLuminance: Double {
        let (r, g, b) = linear
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // WCAG 2.x のコントラスト比 (1.0〜21.0)。
    public func contrastRatio(against other: SRGBColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // MARK: - OKLab

    // 8.5.5 の ΔE は OKLab 上のユークリッド距離。知覚的に均等な空間で測るため、
    // 色相が失われたときに明度差が効いているかを正しく評価できる。
    public var oklab: (L: Double, a: Double, b: Double) {
        let (r, g, b) = linear
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    // 8.5.5 の表記に合わせ 100 倍した値を返す (「10 未満で混同リスク」の尺度)。
    public func deltaE(from other: SRGBColor) -> Double {
        let a = oklab, b = other.oklab
        let dL = a.L - b.L, da = a.a - b.a, db = a.b - b.b
        return (dL * dL + da * da + db * db).squareRoot() * 100
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
