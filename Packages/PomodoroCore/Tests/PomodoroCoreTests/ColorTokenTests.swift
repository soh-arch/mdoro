import Testing
import Foundation
@testable import PomodoroCore

// REQ-COL-020: 全トークンのコントラスト比と、セッション3色の色覚シミュレーション下 ΔE を検証する。
// 基準は 8.5.3 の役ごとの保証値、および ΔE 最小 14。
//
// 色覚シミュレーションは Viénot, Brettel & Mollon (1999) を線形 sRGB に適用したもの。
// 仕様書 8.5.5 の表もこのモデルで測り直した値に更新してある。モデルを差し替えると数値は動くが、
// 判定基準 (ΔE 14) は動かさないこと。

private let allModes = ColorMode.allCases

// 8.5.3 は保証値を小数第2位まで記載している。範囲の上下端はその精度で判定しないと、
// 記載どおり 1.10 の値が 1.09967 として境界を割る。
// 一方、アクセシビリティの下限 (3.0 / 4.5) は丸めずそのまま比較する。
private func atSpecPrecision(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

@Suite("カラートークンのコントラスト (REQ-COL-020)")
struct ColorContrastTests {

    @Test func subtleStaysWithinSurfaceRange() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                for role in [HueRole.subtle, .subtleHover] {
                    let ratio = atSpecPrecision(p.color(hue, role).contrastRatio(against: p.bg))
                    #expect(ratio >= 1.10 && ratio <= 1.60,
                            "\(mode)/\(hue)-\(role): \(ratio) は 1.10–1.60 の範囲外。面として認識できる最小差を守る")
                }
            }
        }
    }

    @Test func lineStaysWithinBorderRange() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let ratio = atSpecPrecision(p.color(hue, .line).contrastRatio(against: p.bg))
                #expect(ratio >= 2.00 && ratio <= 2.45, "\(mode)/\(hue)-line: \(ratio) は 2.00–2.45 の範囲外")
            }
        }
    }

    // 意味を持つ非テキスト図形 (進行リング・状態ドット) は WCAG 1.4.11 の 3.0 以上。
    @Test func graphicMeetsNonTextContrast() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let ratio = p.color(hue, .graphic).contrastRatio(against: p.bg)
                #expect(ratio >= 3.0, "\(mode)/\(hue)-graphic: \(ratio) が 3.0 を下回る")
            }
        }
    }

    // 文字が乗る塗りは、背景に対しても前景 (-on-solid) に対しても 4.5 以上。
    @Test func solidCarriesTextInBothDirections() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let onSolid = p.color(hue, .onSolid)
                for role in [HueRole.solid, .solidHover] {
                    let fill = p.color(hue, role)
                    #expect(fill.contrastRatio(against: p.bg) >= 4.5,
                            "\(mode)/\(hue)-\(role): 対 bg \(fill.contrastRatio(against: p.bg))")
                    #expect(fill.contrastRatio(against: onSolid) >= 4.5,
                            "\(mode)/\(hue)-\(role): 対 on-solid \(fill.contrastRatio(against: onSolid))")
                }
            }
        }
    }

    // -text の検証は bg / bg-sunken / surface / surface-raised の4面すべてに対して行う。
    @Test func hueTextMeetsAllFourSurfaces() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let text = p.color(hue, .text)
                for surface in p.textBackgrounds {
                    let ratio = text.contrastRatio(against: surface)
                    #expect(ratio >= 4.5, "\(mode)/\(hue)-text on \(surface.hex): \(ratio)")
                }
            }
        }
    }

    @Test func neutralTextMeetsAllFourSurfaces() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            // text-disabled は「無効化された要素のみ」に用いるため 4.5 の対象外 (8.5.3)。
            let tokens: [(String, SRGBColor)] = [
                ("text", p.textPrimary), ("text-muted", p.textSecondary), ("text-faint", p.textTertiary),
            ]
            for (name, color) in tokens {
                for surface in p.textBackgrounds {
                    let ratio = color.contrastRatio(against: surface)
                    #expect(ratio >= 4.5, "\(mode)/\(name) on \(surface.hex): \(ratio)")
                }
            }
        }
    }

    // hex の書き写し間違いを検出する。8.5.3 の「対 bg」列と一致すること。
    @Test func recordedContrastAnchorsAreReproduced() {
        let anchors: [(ColorMode, String, SRGBColor, Double)] = {
            let l = ColorPalette.light, d = ColorPalette.dark
            return [
                (.light, "text", l.textPrimary, 14.97), (.light, "text-muted", l.textSecondary, 7.67),
                (.light, "text-faint", l.textTertiary, 4.90), (.light, "border-strong", l.borderStrong, 3.10),
                (.light, "ink-graphic", l.color(.ink, .graphic), 4.63),
                (.light, "sage-graphic", l.color(.sage, .graphic), 3.37),
                (.light, "ochre-graphic", l.color(.ochre, .graphic), 6.63),
                (.light, "clay-graphic", l.color(.clay, .graphic), 5.39),
                (.dark, "text", d.textPrimary, 15.04), (.dark, "text-muted", d.textSecondary, 7.62),
                (.dark, "text-faint", d.textTertiary, 5.94), (.dark, "border-strong", d.borderStrong, 3.30),
                (.dark, "ink-graphic", d.color(.ink, .graphic), 6.99),
                (.dark, "sage-graphic", d.color(.sage, .graphic), 10.05),
                (.dark, "ochre-graphic", d.color(.ochre, .graphic), 4.82),
                (.dark, "clay-graphic", d.color(.clay, .graphic), 6.18),
            ]
        }()
        for (mode, name, color, expected) in anchors {
            let actual = color.contrastRatio(against: ColorPalette.palette(for: mode).bg)
            #expect(abs(actual - expected) < 0.01, "\(mode)/\(name): 実測 \(actual) が 8.5.3 の記載 \(expected) と一致しない")
        }
    }
}

@Suite("色覚多様性下での識別性 (REQ-COL-020 / 021)")
struct ColorVisionTests {

    private func sessionGraphics(_ mode: ColorMode) -> (focus: SRGBColor, short: SRGBColor, long: SRGBColor) {
        let p = ColorPalette.palette(for: mode)
        return (p.color(.ink, .graphic), p.color(.sage, .graphic), p.color(.ochre, .graphic))
    }

    // セッション3色は、色相が失われても識別できること。基準は ΔE 最小 14 (8.5.1 / REQ-COL-020)。
    @Test func sessionColorsStayDistinguishable() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            for vision in ColorVision.allCases {
                let pairs: [(String, SRGBColor, SRGBColor)] = [
                    ("Focus/Short", focus, short), ("Focus/Long", focus, long), ("Short/Long", short, long),
                ]
                for (label, a, b) in pairs {
                    let delta = vision.simulate(a).deltaE(from: vision.simulate(b))
                    #expect(delta >= 14, "\(mode)/\(vision)/\(label): ΔE \(delta) が 14 を下回る")
                }
            }
        }
    }

    // REQ-COL-021: 絶対輝度の段差 Long < Focus < Short を両モードで維持する。
    // 3色を同一明度に揃える変更を行ってはならない。
    @Test func sessionLuminanceOrderIsPreserved() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            #expect(long.relativeLuminance < focus.relativeLuminance,
                    "\(mode): Long \(long.relativeLuminance) は Focus \(focus.relativeLuminance) より暗いこと")
            #expect(focus.relativeLuminance < short.relativeLuminance,
                    "\(mode): Focus \(focus.relativeLuminance) は Short \(short.relativeLuminance) より暗いこと")
        }
    }

    // 段差が「たまたま」ではなく意図された幅であることを確かめる。
    @Test func sessionLuminanceStepsAreSubstantial() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            #expect(focus.relativeLuminance - long.relativeLuminance > 0.05, "\(mode): Long→Focus の段差が浅い")
            #expect(short.relativeLuminance - focus.relativeLuminance > 0.05, "\(mode): Focus→Short の段差が浅い")
        }
    }
}

@Suite("役割マッピング (8.5.4 / REQ-COL-011 / 012)")
struct ColorRoleTests {

    @Test func roleMappingFollowsSpec() {
        #expect(ColorRole.sessionFocus.hue == .ink)
        #expect(ColorRole.sessionShortBreak.hue == .sage)
        #expect(ColorRole.sessionLongBreak.hue == .ochre)
        #expect(ColorRole.accentPrimary.hue == .ink)
        #expect(ColorRole.success.hue == .sage)
        #expect(ColorRole.warning.hue == .ochre)
        #expect(ColorRole.danger.hue == .clay)
    }

    @Test func sessionTypesMapToTheirRoles() {
        #expect(SessionType.work.colorRole == .sessionFocus)
        #expect(SessionType.shortBreak.colorRole == .sessionShortBreak)
        #expect(SessionType.longBreak.colorRole == .sessionLongBreak)
    }

    // REQ-COL-012: danger (Clay) をセッション種別に使ってはならない。
    @Test func dangerIsNeverASessionRole() {
        #expect(!ColorRole.danger.isSessionRole)
        #expect(ColorRole.allCases.filter(\.isSessionRole).allSatisfy { $0.hue != .clay })
    }

    // REQ-COL-011: sessionLongBreak と warning は Ochre を共有するため treatment で区別する。
    // セッション状態に使えるのは -graphic と -text のみ。バナー表現は warning に予約する。
    @Test func sessionRolesAreRestrictedToGraphicAndText() {
        for role in ColorRole.allCases where role.isSessionRole {
            #expect(role.permittedRoles == [.graphic, .text], "\(role) に許される役が広すぎる")
            #expect(!role.allowsBannerTreatment, "\(role) にバナー表現を許してはならない")
        }
        #expect(ColorRole.warning.allowsBannerTreatment)
        #expect(ColorRole.warning.permittedRoles.contains(.subtle))
        #expect(ColorRole.sessionLongBreak.hue == ColorRole.warning.hue, "同じ Ochre を共有していることが前提")
    }

    // REQ-COL-010 / 013: 色だけに頼らせないため、進行リングの線種も種別ごとに変える。
    @Test func sessionTypesHaveDistinctRingStyles() {
        let styles = SessionType.allCases.map(\.progressRingStyle)
        #expect(Set(styles).count == SessionType.allCases.count, "線種が重複している")
    }
}
