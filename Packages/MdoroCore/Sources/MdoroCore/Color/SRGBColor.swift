import Foundation

// REQ-COL-005 / 020: colour is held as a computable value so contrast ratio and ΔE can be
// checked automatically. The hex string is an output; every comparison goes through the
// conversions here.
public struct SRGBColor: Equatable, Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    // A malformed string is a mistake to catch at design time, so this traps instead of being optional.
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

    // MARK: - Linearisation

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

    // MARK: - Luminance and contrast

    // REQ-COL-021 / 8.5.5: the WCAG 2.x relative luminance. "Absolute luminance" means this value too.
    public var relativeLuminance: Double {
        let (r, g, b) = linear
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // The WCAG 2.x contrast ratio (1.0 to 21.0).
    public func contrastRatio(against other: SRGBColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // MARK: - OKLab

    // 8.5.5: ΔE is Euclidean distance in OKLab — measured in a perceptually uniform space.
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

    // Scaled by 100 to match the notation of 8.5.5 (below 10 is a risk of confusion).
    public func deltaE(from other: SRGBColor) -> Double {
        let a = oklab, b = other.oklab
        let dL = a.L - b.L, da = a.a - b.a, db = a.b - b.b
        return (dL * dL + da * da + db * db).squareRoot() * 100
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
