import Foundation

// REQ-COL-020: セッション3色が色覚多様性下でも識別できることを検証するための変換 (8.5.5)。
// Viénot, Brettel & Mollon (1999) の二色覚シミュレーション。線形 sRGB に対して適用する。
public enum ColorVision: String, CaseIterable, Sendable {
    case normal      // 一般
    case deuteranope // 2型 (deutan)
    case protanope   // 1型 (protan)

    public func simulate(_ color: SRGBColor) -> SRGBColor {
        guard self != .normal else { return color }
        let (r, g, b) = color.linear

        // 線形 RGB → LMS
        let l = 17.8824 * r + 43.5161 * g + 4.11935 * b
        let m = 3.45565 * r + 27.1554 * g + 3.86714 * b
        let s = 0.0299566 * r + 0.184309 * g + 1.46709 * b

        // 失われた錐体の応答を、残る2つから再構成する。
        let l2: Double, m2: Double, s2: Double
        switch self {
        case .protanope:
            l2 = 2.02344 * m - 2.52581 * s
            m2 = m
            s2 = s
        case .deuteranope:
            l2 = l
            m2 = 0.494207 * l + 1.24827 * s
            s2 = s
        case .normal:
            l2 = l; m2 = m; s2 = s
        }

        // LMS → 線形 RGB
        return SRGBColor(
            linearR: 0.080944 * l2 - 0.130504 * m2 + 0.116721 * s2,
            linearG: -0.0102485 * l2 + 0.0540194 * m2 - 0.113615 * s2,
            linearB: -0.000365294 * l2 - 0.00412163 * m2 + 0.693513 * s2
        )
    }
}
