import Foundation

// REQ-COL-020: the transform used to check that the three session colours stay distinguishable
// under colour vision deficiency (8.5.5). The dichromat simulation of Viénot, Brettel & Mollon
// (1999), applied to linear sRGB.
public enum ColorVision: String, CaseIterable, Sendable {
    case normal      // ordinary vision
    case deuteranope // type 2 (deutan)
    case protanope   // type 1 (protan)

    public func simulate(_ color: SRGBColor) -> SRGBColor {
        guard self != .normal else { return color }
        let (r, g, b) = color.linear

        // linear RGB → LMS
        let l = 17.8824 * r + 43.5161 * g + 4.11935 * b
        let m = 3.45565 * r + 27.1554 * g + 3.86714 * b
        let s = 0.0299566 * r + 0.184309 * g + 1.46709 * b

        // Rebuild the missing cone's response from the two that remain.
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

        // LMS → linear RGB
        return SRGBColor(
            linearR: 0.080944 * l2 - 0.130504 * m2 + 0.116721 * s2,
            linearG: -0.0102485 * l2 + 0.0540194 * m2 - 0.113615 * s2,
            linearB: -0.000365294 * l2 - 0.00412163 * m2 + 0.693513 * s2
        )
    }
}
