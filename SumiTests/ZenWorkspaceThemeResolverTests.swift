import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class ZenWorkspaceThemeResolverTests: XCTestCase {
    func testDefaultWorkspaceFollowsExplicitDarkWindowScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults, windowSchemeMode: .dark)

        let resolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertEqual(resolution.primaryHex, "#F4EFDF")
        XCTAssertEqual(resolution.chromeColorScheme, .dark)
        XCTAssertEqual(resolution.toolbarTextColor, Color.white.opacity(0.8))
        XCTAssertFalse(resolution.isThemeExplicitScheme)
    }

    func testDarkWorkspacePresetResolvesDarkFromWorkspaceColor() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults, windowSchemeMode: .light)
        let darkTheme = try XCTUnwrap(
            SumiWorkspaceThemePresets.groups
                .first(where: { $0.name == "Dark Mono" })?
                .presets
                .first?
                .workspaceTheme
        )

        let resolution = ZenWorkspaceThemeResolver.resolve(
            theme: darkTheme,
            globalWindowScheme: .light,
            settings: settings
        )

        XCTAssertEqual(resolution.primaryHex, "#5D566A")
        XCTAssertEqual(resolution.chromeColorScheme, .dark)
        XCTAssertEqual(resolution.toolbarTextColor, Color.white.opacity(0.8))
        XCTAssertTrue(resolution.isThemeExplicitScheme)
    }

    func testExplicitLightMonoPresetKeepsLightChromeInDarkWindowScheme() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults, windowSchemeMode: .dark)
        let lightMonoTheme = try XCTUnwrap(
            SumiWorkspaceThemePresets.groups
                .first(where: { $0.name == "Light Mono" })?
                .presets
                .first?
                .workspaceTheme
        )

        let resolution = ZenWorkspaceThemeResolver.resolve(
            theme: lightMonoTheme,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertTrue(WorkspaceTheme.default.visuallyEquals(lightMonoTheme))
        XCTAssertFalse(WorkspaceTheme.default.usesExplicitColorScheme)
        XCTAssertTrue(lightMonoTheme.usesExplicitColorScheme)
        XCTAssertEqual(resolution.primaryHex, "#F4EFDF")
        XCTAssertEqual(resolution.chromeColorScheme, .light)
        XCTAssertEqual(resolution.toolbarTextColor, Color.black.opacity(0.8))
        XCTAssertTrue(resolution.isThemeExplicitScheme)
    }

    func testExplicitLightMonoToolbarSurfaceStillRespondsToWindowScheme() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)
        let lightMonoTheme = try XCTUnwrap(
            SumiWorkspaceThemePresets.groups
                .first(where: { $0.name == "Light Mono" })?
                .presets
                .first?
                .workspaceTheme
        )

        let lightResolution = ZenWorkspaceThemeResolver.resolve(
            theme: lightMonoTheme,
            globalWindowScheme: .light,
            settings: settings
        )
        let darkResolution = ZenWorkspaceThemeResolver.resolve(
            theme: lightMonoTheme,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertEqual(lightResolution.chromeColorScheme, .light)
        XCTAssertEqual(darkResolution.chromeColorScheme, .light)
        XCTAssertEqual(lightResolution.backgroundGradient.primaryColorHex, darkResolution.backgroundGradient.primaryColorHex)
        XCTAssertNotEqual(lightResolution.toolbarGradient.primaryColorHex, darkResolution.toolbarGradient.primaryColorHex)
        XCTAssertEqual(lightResolution.toolbarGradient.opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(darkResolution.toolbarGradient.opacity, 1, accuracy: 0.0001)
    }

    func testDefaultWorkspaceAutoFollowsResolvedGlobalScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults, windowSchemeMode: .auto)

        let darkResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .dark,
            settings: settings
        )
        let lightResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .light,
            settings: settings
        )

        XCTAssertEqual(darkResolution.chromeColorScheme, .dark)
        XCTAssertEqual(lightResolution.chromeColorScheme, .light)
        XCTAssertFalse(darkResolution.isThemeExplicitScheme)
        XCTAssertFalse(lightResolution.isThemeExplicitScheme)
    }

    func testOpeningTabDoesNotChangeWorkspaceThemeResolution() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)
        let before = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )

        windowState.currentSpaceId = UUID()
        windowState.currentTabId = UUID()
        windowState.isShowingEmptyState = false

        let after = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )

        XCTAssertEqual(after.workspacePrimaryHex, before.workspacePrimaryHex)
        XCTAssertEqual(after.chromeColorScheme, before.chromeColorScheme)
        XCTAssertEqual(after.chromeDarknessProgress, before.chromeDarknessProgress, accuracy: 0.0001)
    }

    func testSystemColorsStillFollowGlobalScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)
        settings.themeUseSystemColors = true

        let darkResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .dark,
            settings: settings
        )
        let lightResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .light,
            settings: settings
        )

        XCTAssertEqual(darkResolution.chromeColorScheme, .dark)
        XCTAssertEqual(lightResolution.chromeColorScheme, .light)
    }

    func testWorkspacePrimaryColorFeedsChromeAccentToken() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .light
        context.chromeColorScheme = .light
        context.sourceChromeColorScheme = .light
        context.targetChromeColorScheme = .light
        context.workspaceTheme = .default
        context.sourceWorkspaceTheme = .default
        context.targetWorkspaceTheme = .default

        let tokens = context.tokens(settings: settings)
        let expected = Color(hex: "#F4EFDF").sRGBComponents
        let actual = tokens.accent.sRGBComponents

        XCTAssertEqual(actual.red, expected.red, accuracy: 0.01)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.01)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.01)
    }

    func testBackgroundGradientUsesZenResolvedColorsAndOriginalOpacity() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)
        let lightMonoTheme = SumiWorkspaceThemePresets.groups[0].presets[0].workspaceTheme
        let resolution = ZenWorkspaceThemeResolver.resolve(
            theme: lightMonoTheme,
            globalWindowScheme: .light,
            settings: settings
        )

        XCTAssertEqual(resolution.backgroundGradient.opacity, lightMonoTheme.gradient.opacity, accuracy: 0.0001)
        XCTAssertNotEqual(
            resolution.backgroundGradient.primaryColorHex,
            lightMonoTheme.gradient.primaryColorHex
        )
    }

    func testDefaultThemeSurfacesFollowWindowSchemeLikeZenDefaultCSS() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeSettings(defaults: harness.defaults)

        let lightResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .light,
            settings: settings
        )
        let darkResolution = ZenWorkspaceThemeResolver.resolve(
            theme: .default,
            globalWindowScheme: .dark,
            settings: settings
        )

        XCTAssertFalse(lightResolution.isThemeExplicitScheme)
        XCTAssertFalse(darkResolution.isThemeExplicitScheme)
        XCTAssertEqual(lightResolution.backgroundGradient.primaryColorHex, "#EBEBEB")
        XCTAssertEqual(darkResolution.backgroundGradient.primaryColorHex, "#1B1B1B")
        XCTAssertNotEqual(lightResolution.toolbarGradient.primaryColorHex, darkResolution.toolbarGradient.primaryColorHex)
        XCTAssertEqual(lightResolution.backgroundGradient.opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(darkResolution.backgroundGradient.opacity, 1, accuracy: 0.0001)
    }

    private func makeSettings(
        defaults: UserDefaults,
        windowSchemeMode: WindowSchemeMode = .light
    ) -> SumiSettingsService {
        let settings = SumiSettingsService(userDefaults: defaults)
        settings.windowSchemeMode = windowSchemeMode
        settings.themeUseSystemColors = false
        return settings
    }
}
