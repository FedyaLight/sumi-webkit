import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class ThemeChromeRecipeBuilderTests: XCTestCase {
    func testCommandPaletteSolidBackgroundLightIsOpaqueWhite() {
        let color = ThemeChromeRecipeBuilder.commandPaletteSolidBackground(scheme: .light)
        let c = color.sRGBComponents
        XCTAssertEqual(c.red, 1, accuracy: 0.02)
        XCTAssertEqual(c.green, 1, accuracy: 0.02)
        XCTAssertEqual(c.blue, 1, accuracy: 0.02)
        XCTAssertEqual(c.alpha, 1, accuracy: 0.02)
    }

    func testCommandPaletteSolidBackgroundDarkMatchesCanonicalHex() {
        let color = ThemeChromeRecipeBuilder.commandPaletteSolidBackground(scheme: .dark)
        let expected = Color(hex: "1C1C1E")
        let a = color.sRGBComponents
        let b = expected.sRGBComponents
        XCTAssertEqual(a.red, b.red, accuracy: 0.02)
        XCTAssertEqual(a.green, b.green, accuracy: 0.02)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.02)
        XCTAssertEqual(a.alpha, b.alpha, accuracy: 0.02)
    }

    func testUrlBarHubVeilGradientBottomStopDiffersForActiveVsInactive() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.sourceChromeColorScheme = .light
        context.targetChromeColorScheme = .light
        context.transitionProgress = 1.0

        let tokens = context.tokens(settings: settings)
        let inactive = ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
            tokens: tokens,
            isActive: false,
            isHovered: false
        )
        let active = ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
            tokens: tokens,
            isActive: true,
            isHovered: false
        )
        XCTAssertEqual(inactive.count, 2)
        XCTAssertEqual(active.count, 2)
        XCTAssertNotEqual(
            inactive[1],
            active[1],
            "Inactive vs active should change the bottom veil stop"
        )
    }

    func testCommandPaletteBackgroundDiffersFromPanelBackgroundInRecipe() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .dark
        context.chromeColorScheme = .dark
        context.sourceChromeColorScheme = .dark
        context.targetChromeColorScheme = .dark
        context.transitionProgress = 1.0

        let tokens = context.tokens(settings: settings)
        let panel = tokens.panelBackground.sRGBComponents
        let palette = tokens.commandPaletteBackground.sRGBComponents
        let distance = abs(panel.red - palette.red)
            + abs(panel.green - palette.green)
            + abs(panel.blue - palette.blue)
        XCTAssertGreaterThan(
            distance,
            0.05,
            "In dark chrome, floating palette (#1C1C1E) should differ from the neutral panel lift"
        )
    }
}
