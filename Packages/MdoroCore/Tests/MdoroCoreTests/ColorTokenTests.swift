import Testing
import Foundation
@testable import MdoroCore

// REQ-COL-020: checks the contrast ratio of every token, and the ΔE of the three session colours
// under colour vision simulation. The bars are the per-role guarantees of 8.5.3, and a minimum
// ΔE of 14.
//
// The colour vision simulation is Viénot, Brettel & Mollon (1999). The table in 8.5.5 was measured
// with the same model. Swapping the model moves the numbers, but **never move the bar (ΔE 14).**

private let allModes = ColorMode.allCases

// The guarantees of 8.5.3 go to two decimal places. Judged without that precision, 1.10 falls
// under the boundary as 1.09967.
// The accessibility floors (3.0 / 4.5) are compared as they are, with no rounding.
private func atSpecPrecision(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

@Suite("Color token contrast (REQ-COL-020)")
struct ColorContrastTests {

    @Test func subtleStaysWithinSurfaceRange() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                for role in [HueRole.subtle, .subtleHover] {
                    let ratio = atSpecPrecision(p.color(hue, role).contrastRatio(against: p.bg))
                    #expect(ratio >= 1.10 && ratio <= 1.60,
                            "\(mode)/\(hue)-\(role): \(ratio) is outside 1.10–1.60; a surface must stay just barely distinct from bg")
                }
            }
        }
    }

    @Test func lineStaysWithinBorderRange() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let ratio = atSpecPrecision(p.color(hue, .line).contrastRatio(against: p.bg))
                #expect(ratio >= 2.00 && ratio <= 2.45, "\(mode)/\(hue)-line: \(ratio) is outside 2.00–2.45")
            }
        }
    }

    // A non-text graphic that carries meaning (the progress ring, the state dot) is 3.0 or above,
    // per WCAG 1.4.11.
    @Test func graphicMeetsNonTextContrast() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let ratio = p.color(hue, .graphic).contrastRatio(against: p.bg)
                #expect(ratio >= 3.0, "\(mode)/\(hue)-graphic: \(ratio) is below 3.0")
            }
        }
    }

    // A fill that carries text is 4.5 or above against the background and against the foreground
    // (-on-solid) alike.
    @Test func solidCarriesTextInBothDirections() {
        for mode in allModes {
            let p = ColorPalette.palette(for: mode)
            for hue in ColorHue.allCases {
                let onSolid = p.color(hue, .onSolid)
                for role in [HueRole.solid, .solidHover] {
                    let fill = p.color(hue, role)
                    #expect(fill.contrastRatio(against: p.bg) >= 4.5,
                            "\(mode)/\(hue)-\(role): against bg \(fill.contrastRatio(against: p.bg))")
                    #expect(fill.contrastRatio(against: onSolid) >= 4.5,
                            "\(mode)/\(hue)-\(role): against on-solid \(fill.contrastRatio(against: onSolid))")
                }
            }
        }
    }

    // -text is checked against all four surfaces: bg / bg-sunken / surface / surface-raised.
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
            // text-disabled is used on disabled elements only, so it falls outside the 4.5 bar (8.5.3).
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

    // Catches a hex copied down wrongly. It has to match the "against bg" column of 8.5.3.
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
            #expect(abs(actual - expected) < 0.01, "\(mode)/\(name): measured \(actual) does not match \(expected) as recorded in 8.5.3")
        }
    }
}

@Suite("Distinguishable under color vision deficiency (REQ-COL-020 / 021)")
struct ColorVisionTests {

    private func sessionGraphics(_ mode: ColorMode) -> (focus: SRGBColor, short: SRGBColor, long: SRGBColor) {
        let p = ColorPalette.palette(for: mode)
        return (p.color(.ink, .graphic), p.color(.sage, .graphic), p.color(.ochre, .graphic))
    }

    // The three session colours stay distinguishable even once the hue is gone. The bar is a
    // minimum ΔE of 14 (8.5.1 / REQ-COL-020).
    @Test func sessionColorsStayDistinguishable() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            for vision in ColorVision.allCases {
                let pairs: [(String, SRGBColor, SRGBColor)] = [
                    ("Focus/Short", focus, short), ("Focus/Long", focus, long), ("Short/Long", short, long),
                ]
                for (label, a, b) in pairs {
                    let delta = vision.simulate(a).deltaE(from: vision.simulate(b))
                    #expect(delta >= 14, "\(mode)/\(vision)/\(label): ΔE \(delta) is below 14")
                }
            }
        }
    }

    // REQ-COL-021: the absolute-luminance steps Long < Focus < Short hold in both modes.
    // Never make a change that levels the three colours to the same lightness.
    @Test func sessionLuminanceOrderIsPreserved() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            #expect(long.relativeLuminance < focus.relativeLuminance,
                    "\(mode): Long \(long.relativeLuminance) must be darker than Focus \(focus.relativeLuminance)")
            #expect(focus.relativeLuminance < short.relativeLuminance,
                    "\(mode): Focus \(focus.relativeLuminance) must be darker than Short \(short.relativeLuminance)")
        }
    }

    // Confirms the steps are a width that was intended, not one that happened to fall out.
    @Test func sessionLuminanceStepsAreSubstantial() {
        for mode in allModes {
            let (focus, short, long) = sessionGraphics(mode)
            #expect(focus.relativeLuminance - long.relativeLuminance > 0.05, "\(mode): the Long-to-Focus luminance step is too shallow")
            #expect(short.relativeLuminance - focus.relativeLuminance > 0.05, "\(mode): the Focus-to-Short luminance step is too shallow")
        }
    }
}

@Suite("Role mapping (8.5.4 / REQ-COL-011 / 012)")
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

    // REQ-COL-012: danger (Clay) must never stand for a session type.
    @Test func dangerIsNeverASessionRole() {
        #expect(!ColorRole.danger.isSessionRole)
        #expect(ColorRole.allCases.filter(\.isSessionRole).allSatisfy { $0.hue != .clay })
    }

    // REQ-COL-011: sessionLongBreak and warning share the Ochre hue, so the treatment tells them
    // apart. Only -graphic and -text may be used for a session state, which rules out the banner
    // treatment. Warning is allowed one, and so is any other state that needs attention (REQ-UIX-046).
    @Test func sessionRolesAreRestrictedToGraphicAndText() {
        for role in ColorRole.allCases where role.isSessionRole {
            #expect(role.permittedRoles == [.graphic, .text], "\(role) permits too many hue roles")
            #expect(!role.allowsBannerTreatment, "\(role) must not allow banner treatment")
        }
        #expect(ColorRole.warning.allowsBannerTreatment)
        #expect(ColorRole.warning.permittedRoles.contains(.subtle))
        #expect(ColorRole.sessionLongBreak.hue == ColorRole.warning.hue, "the restriction assumes both share the Ochre hue")
    }

    // REQ-COL-010 / 013: never colour alone, so the progress ring's stroke style differs per type.
    @Test func sessionTypesHaveDistinctRingStyles() {
        let styles = SessionType.allCases.map(\.progressRingStyle)
        #expect(Set(styles).count == SessionType.allCases.count, "two session types share the same ring style")
    }
}
