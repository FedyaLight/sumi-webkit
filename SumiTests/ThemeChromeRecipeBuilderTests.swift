import AppKit
import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class ThemeChromeRecipeBuilderTests: XCTestCase {
    func testFloatingBarSolidBackgroundLightIsOpaqueWhite() {
        let color = ThemeChromeRecipeBuilder.floatingBarSolidBackground(scheme: .light)
        let c = color.sRGBComponents
        XCTAssertEqual(c.red, 1, accuracy: 0.02)
        XCTAssertEqual(c.green, 1, accuracy: 0.02)
        XCTAssertEqual(c.blue, 1, accuracy: 0.02)
        XCTAssertEqual(c.alpha, 1, accuracy: 0.02)
    }

    func testFloatingBarSolidBackgroundDarkMatchesCanonicalHex() {
        let color = ThemeChromeRecipeBuilder.floatingBarSolidBackground(scheme: .dark)
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

    func testFloatingBarTokenUsesSolidBackgroundInDarkRecipe() {
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
        let token = tokens.floatingBarBackground.sRGBComponents
        let expected = ThemeChromeRecipeBuilder.floatingBarSolidBackground(scheme: .dark).sRGBComponents
        XCTAssertEqual(token.red, expected.red, accuracy: 0.02)
        XCTAssertEqual(token.green, expected.green, accuracy: 0.02)
        XCTAssertEqual(token.blue, expected.blue, accuracy: 0.02)
        XCTAssertEqual(token.alpha, expected.alpha, accuracy: 0.02)
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
