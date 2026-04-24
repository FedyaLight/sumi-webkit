import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class SidebarThemeResolutionTests: XCTestCase {
    func testDefaultLightWorkspaceResolvesLightBeforeAndAfterTabActivation() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults)
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

        XCTAssertEqual(before.workspacePrimaryHex, "#F4EFDF")
        XCTAssertEqual(before.chromeColorScheme, .light)
        XCTAssertEqual(after.chromeColorScheme, .light)
        XCTAssertEqual(after.chromeDarknessProgress, 0, accuracy: 0.0001)
    }

    func testExplicitDarkWindowSchemeDarkensDefaultWorkspaceBeforeAndAfterTabActivation() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults, windowSchemeMode: .dark)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)
        let before = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .dark
        )

        windowState.currentSpaceId = UUID()
        windowState.currentTabId = UUID()
        windowState.isShowingEmptyState = false

        let after = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .dark
        )

        XCTAssertEqual(before.workspacePrimaryHex, "#F4EFDF")
        XCTAssertEqual(before.chromeColorScheme, .dark)
        XCTAssertEqual(before.chromeDarknessProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(after.chromeColorScheme, .dark)
        XCTAssertEqual(after.chromeDarknessProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(after.workspacePrimaryHex, before.workspacePrimaryHex)
        XCTAssertEqual(after, before)
    }

    func testAutoWindowSchemeFollowsResolvedGlobalSchemeForDefaultWorkspace() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults, windowSchemeMode: .auto)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)

        let lightSnapshot = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )
        let darkSnapshot = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .dark
        )

        XCTAssertEqual(lightSnapshot.chromeColorScheme, .light)
        XCTAssertEqual(lightSnapshot.chromeDarknessProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(darkSnapshot.chromeColorScheme, .dark)
        XCTAssertEqual(darkSnapshot.chromeDarknessProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(lightSnapshot.workspacePrimaryHex, darkSnapshot.workspacePrimaryHex)
    }

    func testExplicitFirstLightMonoWorkspaceKeepsDarkTextInDarkWindowScheme() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults, windowSchemeMode: .dark)
        let lightMonoTheme = try XCTUnwrap(
            SumiWorkspaceThemePresets.groups.first?.presets.first?.workspaceTheme
        )
        let windowState = BrowserWindowState(initialWorkspaceTheme: lightMonoTheme)

        let snapshot = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .dark
        )
        let tokens = windowState
            .resolvedThemeContext(global: .dark, settings: settings)
            .tokens(settings: settings)

        XCTAssertTrue(WorkspaceTheme.default.visuallyEquals(lightMonoTheme))
        XCTAssertTrue(lightMonoTheme.usesExplicitColorScheme)
        XCTAssertEqual(snapshot.chromeColorScheme, .light)
        XCTAssertEqual(snapshot.chromeDarknessProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(tokens.primaryText, Color.black.opacity(0.84))
    }

    func testActivatingTabDoesNotChangeSidebarThemeSnapshotForSameSpace() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)
        windowState.currentSpaceId = UUID()
        windowState.isShowingEmptyState = true

        let before = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )

        windowState.currentTabId = UUID()
        windowState.isShowingEmptyState = false

        let after = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )

        XCTAssertEqual(after, before)
    }

    func testIdleSidebarThemeContextIgnoresStaleTransitionThemes() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)
        windowState.previousWorkspaceTheme = .incognito
        windowState.targetWorkspaceTheme = .incognito
        windowState.themeTransitionProgress = 0
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = UUID()

        let snapshot = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )

        XCTAssertEqual(snapshot.workspacePrimaryHex, "#F4EFDF")
        XCTAssertEqual(snapshot.sourceWorkspacePrimaryHex, "#F4EFDF")
        XCTAssertEqual(snapshot.targetWorkspacePrimaryHex, "#F4EFDF")
        XCTAssertEqual(snapshot.chromeColorScheme, .light)
        XCTAssertEqual(snapshot.sourceChromeColorScheme, .light)
        XCTAssertEqual(snapshot.targetChromeColorScheme, .light)
        XCTAssertEqual(snapshot.chromeDarknessProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.transitionProgress, 1, accuracy: 0.0001)
    }

    func testSidebarThemeSnapshotUsesResolvedThemeContextValues() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults)
        let windowState = BrowserWindowState(initialWorkspaceTheme: .default)
        let context = windowState.resolvedThemeContext(global: .light, settings: settings)
        let snapshot = SidebarThemeResolutionSnapshot.make(
            windowState: windowState,
            settings: settings,
            globalColorScheme: .light
        )
        let tokens = context.tokens(settings: settings)

        XCTAssertEqual(snapshot.workspacePrimaryHex, context.workspaceTheme.gradient.primaryColorHex)
        XCTAssertEqual(snapshot.sourceWorkspacePrimaryHex, context.sourceWorkspaceTheme.gradient.primaryColorHex)
        XCTAssertEqual(snapshot.targetWorkspacePrimaryHex, context.targetWorkspaceTheme.gradient.primaryColorHex)
        XCTAssertEqual(snapshot.chromeColorScheme, context.chromeColorScheme)
        XCTAssertEqual(snapshot.sourceChromeColorScheme, context.sourceChromeColorScheme)
        XCTAssertEqual(snapshot.targetChromeColorScheme, context.targetChromeColorScheme)
        XCTAssertEqual(snapshot.chromeDarknessProgress, context.chromeDarknessProgress, accuracy: 0.0001)
        XCTAssertEqual(tokens.primaryText, ThemeContrastResolver.primaryText(for: context.chromeColorScheme))
    }

    func testSpaceGradientBackgroundUsesResolvedChromeTokensForBaseColor() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Browser/Window/SpaceGradientBackgroundView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Environment(\\.resolvedThemeContext)"))
        XCTAssertTrue(source.contains("@Environment(\\.sumiSettings)"))
        XCTAssertTrue(source.contains("themeContext.tokens(settings: sumiSettings)"))
        XCTAssertTrue(source.contains("chromeTokens.windowBackground"))
        XCTAssertTrue(source.contains("case .toolbarChrome"))
        XCTAssertTrue(source.contains("ZenWorkspaceThemeResolver.resolve"))
        XCTAssertFalse(source.contains("chromeDarknessProgress"))
        XCTAssertFalse(source.contains("Color(.windowBackgroundColor)"))
    }

    func testSidebarColumnHostIsPaintlessAndDoesNotLeakAppKitWindowBackground() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/SidebarColumnViewController.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("override var isOpaque: Bool"))
        XCTAssertTrue(source.contains("SidebarHostingView<Content: View>: NSHostingView<Content>"))
        XCTAssertTrue(source.contains("SidebarHostingController<Content: View>"))
        XCTAssertTrue(source.contains("SidebarColumnPaintlessChrome.configure"))
        XCTAssertTrue(source.contains("NSColor.clear.cgColor"))
        XCTAssertTrue(source.contains("view.layer?.isOpaque = false"))
        XCTAssertFalse(source.contains("windowBackgroundColor"))
    }

    func testDockedSidebarBackgroundUsesResolvedThemeContext() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/SidebarHoverOverlayView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var drawsSidebarChromeBackground"))
        XCTAssertTrue(source.contains("presentationContext.mode != .collapsedHidden"))
        XCTAssertTrue(source.contains("themeContext.tokens(settings: sumiSettings).windowBackground"))
        XCTAssertTrue(source.contains("SpaceGradientBackgroundView(surface: .toolbarChrome)"))
        XCTAssertTrue(source.contains(".opacity(drawsSidebarChromeBackground ? 1 : 0)"))
    }

    func testBrowserWindowShellDoesNotUseDynamicAppKitBackgroundForChromeFallback() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Window/SumiBrowserWindow.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("static let backgroundColor = NSColor.clear"))
        XCTAssertTrue(source.contains("static let isOpaque = false"))
        XCTAssertTrue(source.contains("contentView?.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertFalse(source.contains("static let backgroundColor = NSColor.windowBackgroundColor"))
    }

    func testWebsiteCompositorContainersArePaintlessChromeFallbacks() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteView.swift"
            ),
            encoding: .utf8
        )
        let containerSource = try XCTUnwrap(source.range(of: "// MARK: - Container View"))
            .lowerBound
        let webColumnSource = String(source[containerSource...])

        XCTAssertTrue(webColumnSource.contains("WebColumnPaintlessChrome.configure"))
        XCTAssertTrue(webColumnSource.contains("view.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(webColumnSource.contains("override var isOpaque: Bool { false }"))
        XCTAssertFalse(webColumnSource.contains("NSColor.windowBackgroundColor.setFill()"))
    }

    func testWebViewHostIsPaintlessChromeFallback() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "final class SumiWebViewContainerView"))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "private struct HistorySwipeProtectionContext"))
            .lowerBound
        let hostSource = String(source[start..<end])

        XCTAssertTrue(hostSource.contains("override var isOpaque: Bool { false }"))
        XCTAssertTrue(hostSource.contains("configurePaintlessChrome()"))
        XCTAssertTrue(hostSource.contains("layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertFalse(hostSource.contains("NSColor.windowBackgroundColor.setFill()"))
    }

    private func makeThemeSettings(
        defaults: UserDefaults,
        windowSchemeMode: WindowSchemeMode = .light
    ) -> SumiSettingsService {
        let settings = SumiSettingsService(userDefaults: defaults)
        settings.windowSchemeMode = windowSchemeMode
        settings.themeUseSystemColors = false
        return settings
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}
