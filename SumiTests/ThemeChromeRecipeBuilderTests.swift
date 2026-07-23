import AppKit
@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class ThemeChromeRecipeBuilderTests: XCTestCase {
    func testTransitionProgressValuesReuseSingleRecipeBuild() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        ChromeThemeCacheDiagnostics.resetForTests()

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.sourceChromeColorScheme = .dark
        context.targetChromeColorScheme = .light
        context.chromeColorScheme = .light
        context.isInteractiveTransition = true

        context.transitionProgress = 0
        let source = context.tokens(settings: settings).primaryText.sRGBComponents
        context.transitionProgress = 0.5
        let midpoint = context.tokens(settings: settings).primaryText.sRGBComponents
        context.transitionProgress = 1
        let target = context.tokens(settings: settings).primaryText.sRGBComponents

        XCTAssertEqual(ThemeChromeRecipeBuilder.recipeBuildCountForTests, 1)
        XCTAssertEqual(midpoint.red, source.red + ((target.red - source.red) * 0.5), accuracy: 0.0001)
        XCTAssertEqual(midpoint.green, source.green + ((target.green - source.green) * 0.5), accuracy: 0.0001)
        XCTAssertEqual(midpoint.blue, source.blue + ((target.blue - source.blue) * 0.5), accuracy: 0.0001)
        XCTAssertEqual(midpoint.alpha, source.alpha + ((target.alpha - source.alpha) * 0.5), accuracy: 0.0001)
    }

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

    func testCommandPaletteTokenUsesSolidBackgroundInDarkRecipe() {
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
        let token = tokens.commandPaletteBackground.sRGBComponents
        let expected = ThemeChromeRecipeBuilder.commandPaletteSolidBackground(scheme: .dark).sRGBComponents
        XCTAssertEqual(token.red, expected.red, accuracy: 0.02)
        XCTAssertEqual(token.green, expected.green, accuracy: 0.02)
        XCTAssertEqual(token.blue, expected.blue, accuracy: 0.02)
        XCTAssertEqual(token.alpha, expected.alpha, accuracy: 0.02)
    }

    func testTextTokensInterpolateDuringChromeSchemeTransition() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.sourceChromeColorScheme = .dark
        context.targetChromeColorScheme = .light
        context.transitionProgress = 0.5

        let token = context.tokens(settings: settings).primaryText.sRGBComponents
        let dark = ThemeContrastResolver.primaryText(for: .dark).sRGBComponents
        let light = ThemeContrastResolver.primaryText(for: .light).sRGBComponents
        let expectedRed = dark.red + ((light.red - dark.red) * 0.5)
        let expectedAlpha = dark.alpha + ((light.alpha - dark.alpha) * 0.5)

        XCTAssertEqual(token.red, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.green, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.blue, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.alpha, expectedAlpha, accuracy: 0.02)
        XCTAssertNotEqual(token.red, dark.red, accuracy: 0.02)
        XCTAssertNotEqual(token.red, light.red, accuracy: 0.02)
    }

    func testChromeControlBackgroundTokensInterpolateDuringChromeSchemeTransition() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.sourceChromeColorScheme = .dark
        context.targetChromeColorScheme = .light
        context.transitionProgress = 0.5

        let token = context.tokens(settings: settings).chromeControlHoverBackground.sRGBComponents
        let dark = ThemeContrastResolver.primaryText(for: .dark).opacity(0.20).sRGBComponents
        let light = ThemeContrastResolver.primaryText(for: .light).opacity(0.10).sRGBComponents
        let expectedRed = dark.red + ((light.red - dark.red) * 0.5)
        let expectedAlpha = dark.alpha + ((light.alpha - dark.alpha) * 0.5)

        XCTAssertEqual(token.red, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.green, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.blue, expectedRed, accuracy: 0.02)
        XCTAssertEqual(token.alpha, expectedAlpha, accuracy: 0.02)
    }

    func testPopoverActionDisabledAlphaIsCanonicalZeroPointFourFive() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.transitionProgress = 1.0

        let token = context.tokens(settings: settings).popoverActionDisabledAlpha
        XCTAssertEqual(token, 0.45, accuracy: 0.0001)
    }

    func testPopoverActionDisabledAlphaMirrorsURLBarHubNativeStyle() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.transitionProgress = 1.0

        let token = context.tokens(settings: settings).popoverActionDisabledAlpha
        XCTAssertEqual(
            token,
            URLBarHubNativeStyle.popoverActionDisabledAlpha,
            accuracy: 0.0001,
            "Native-style mirror must stay in lockstep with the chrome theme token"
        )
    }

    func testFindInPagePaintUsesOpaqueSurfacesInLightRecipe() {
        let paint = findInPagePaint(scheme: .light)

        XCTAssertEqual(Self.alpha(of: paint.shellBackground), 1, accuracy: 0.02)
        XCTAssertEqual(Self.alpha(of: paint.fieldUnfocused), 1, accuracy: 0.02)
        XCTAssertEqual(Self.alpha(of: paint.fieldFocused), 1, accuracy: 0.02)
    }

    func testFindInPagePaintUsesOpaqueSurfacesInDarkRecipe() {
        let paint = findInPagePaint(scheme: .dark)

        XCTAssertEqual(Self.alpha(of: paint.shellBackground), 1, accuracy: 0.02)
        XCTAssertEqual(Self.alpha(of: paint.fieldUnfocused), 1, accuracy: 0.02)
        XCTAssertEqual(Self.alpha(of: paint.fieldFocused), 1, accuracy: 0.02)
    }

    private func findInPagePaint(scheme: ColorScheme) -> FindInPageChromePaint {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = scheme
        context.chromeColorScheme = scheme
        context.sourceChromeColorScheme = scheme
        context.targetChromeColorScheme = scheme
        context.transitionProgress = 1.0

        return FindInPageChromePaint.resolve(tokens: context.tokens(settings: settings))
    }

    private static func alpha(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return alpha
    }
}
