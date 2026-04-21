import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class ThemeContrastResolverTests: XCTestCase {
    func testDarkAccentPrefersDarkChromeScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let theme = makeTheme(hex: "#121212")
        settings.themeUseSystemColors = false

        let scheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: theme,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertEqual(scheme, .dark)
    }

    func testLightAccentPrefersLightChromeScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let theme = makeTheme(hex: "#F7ECD9")
        settings.themeUseSystemColors = false

        let scheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: theme,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertEqual(scheme, .light)
    }

    func testUseSystemColorsShortCircuitsToGlobalScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeUseSystemColors = true

        let darkResult = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: makeTheme(hex: "#202020"),
            globalWindowScheme: .dark,
            settings: settings
        )
        let lightResult = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: makeTheme(hex: "#202020"),
            globalWindowScheme: .light,
            settings: settings
        )

        XCTAssertEqual(darkResult, .dark)
        XCTAssertEqual(lightResult, .light)
    }

    func testOpacityDoesNotAffectResolvedChromeScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeUseSystemColors = false

        let lowOpacityScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: makeTheme(hex: "#E6B9D5", opacity: WorkspaceGradientTheme.minimumOpacity),
            globalWindowScheme: .dark,
            settings: settings
        )
        let highOpacityScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: makeTheme(hex: "#E6B9D5", opacity: WorkspaceGradientTheme.maximumOpacity),
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertEqual(lowOpacityScheme, highOpacityScheme)
    }

    func testContrastingShadeProducesReadableForegroundForDarkAccent() {
        let background = Color(hex: "#0E3B5A")
        let shade = ThemeContrastResolver.contrastingShade(
            of: background,
            targetRatio: 4.5,
            directionPreference: .preferLight,
            minimumBlend: 0.68
        )

        XCTAssertNotNil(shade)
        XCTAssertGreaterThanOrEqual(background.contrastRatio(with: shade!), 4.5)
    }

    func testContrastingShadeProducesReadableForegroundForLightAccent() {
        let background = Color(hex: "#F7E7BF")
        let shade = ThemeContrastResolver.contrastingShade(
            of: background,
            targetRatio: 4.5,
            directionPreference: .preferDark,
            minimumBlend: 0.6
        )

        XCTAssertNotNil(shade)
        XCTAssertGreaterThanOrEqual(background.contrastRatio(with: shade!), 4.5)
    }

    private func makeTheme(
        hex: String,
        opacity: Double = 0.72
    ) -> WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: hex,
                        isPrimary: true,
                        algorithm: .floating,
                        lightness: WorkspaceThemeColor.defaultLightness(for: hex),
                        position: .monochrome
                    )
                ],
                opacity: opacity,
                texture: 0.2
            )
        )
    }
}
