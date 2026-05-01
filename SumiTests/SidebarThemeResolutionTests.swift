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
        let nativeSurfaceContext = windowState
            .resolvedThemeContext(global: .dark, settings: settings)
            .nativeSurfaceThemeContext
        let nativeSurfaceTokens = nativeSurfaceContext.tokens(settings: settings)

        XCTAssertTrue(WorkspaceTheme.default.visuallyEquals(lightMonoTheme))
        XCTAssertTrue(lightMonoTheme.usesExplicitColorScheme)
        XCTAssertEqual(snapshot.chromeColorScheme, .light)
        XCTAssertEqual(snapshot.chromeDarknessProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(tokens.primaryText, Color.black.opacity(0.84))
        XCTAssertEqual(nativeSurfaceContext.globalColorScheme, .dark)
        XCTAssertEqual(nativeSurfaceContext.chromeColorScheme, .dark)
        XCTAssertEqual(nativeSurfaceContext.sourceChromeColorScheme, .dark)
        XCTAssertEqual(nativeSurfaceContext.targetChromeColorScheme, .dark)
        XCTAssertEqual(nativeSurfaceTokens.primaryText, Color.white.opacity(0.92))
        XCTAssertEqual(nativeSurfaceContext.nativeSurfaceSelectionBackground, Color.white.opacity(0.16))
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

    func testWindowBackgroundOwnsSingleResolvedChromeGradientLayer() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "App/Window/WindowView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SpaceGradientBackgroundView(surface: .toolbarChrome)"))
        XCTAssertTrue(source.contains("BrowserChromeGeometry.elementSeparation"))
        XCTAssertFalse(source.contains("windowBackgroundColor"))
        XCTAssertFalse(source.contains("tokens(settings: sumiSettings).windowBackground"))
    }

    func testWindowViewRendersDockedSidebarAsRealLayoutColumn() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "App/Window/WindowView.swift"
            ),
            encoding: .utf8
        )
        let layoutStart = try XCTUnwrap(source.range(of: "private func SidebarWebViewStack()"))
            .lowerBound
        let layoutEnd = try XCTUnwrap(source.range(of: "private func WebContent()"))
            .lowerBound
        let layoutSource = String(source[layoutStart..<layoutEnd])

        XCTAssertFalse(source.contains("SidebarDockedSpacer"))
        XCTAssertTrue(layoutSource.contains("let sidebarPosition = sumiSettings.sidebarPosition"))
        XCTAssertTrue(layoutSource.contains("let shellEdge = sidebarPosition.shellEdge"))
        XCTAssertTrue(layoutSource.contains("if sidebarVisible && shellEdge.isLeft"))
        XCTAssertTrue(layoutSource.contains("if sidebarVisible && shellEdge.isRight"))
        XCTAssertTrue(layoutSource.contains("SidebarDockedColumn(sidebarPosition: sidebarPosition)"))
        XCTAssertTrue(layoutSource.contains("WebContent()"))
        let leftSidebarRange = try XCTUnwrap(
            layoutSource.range(of: "if sidebarVisible && shellEdge.isLeft")
        )
        let webContentRange = try XCTUnwrap(layoutSource.range(of: "WebContent()"))
        let rightSidebarRange = try XCTUnwrap(
            layoutSource.range(of: "if sidebarVisible && shellEdge.isRight")
        )
        XCTAssertLessThan(
            leftSidebarRange.lowerBound,
            webContentRange.lowerBound
        )
        XCTAssertLessThan(
            webContentRange.lowerBound,
            rightSidebarRange.lowerBound
        )
        XCTAssertTrue(layoutSource.contains("SidebarPresentationContext.docked("))
        XCTAssertTrue(layoutSource.contains("sidebarPosition: sidebarPosition"))
        XCTAssertTrue(layoutSource.contains("SidebarColumnRepresentable("))
        XCTAssertTrue(layoutSource.contains(".frame(width: presentationContext.sidebarWidth)"))
        XCTAssertFalse(layoutSource.contains("Color.clear"))
    }

    func testWindowViewUsesCustomBrowserTrafficLightsAndHoverOverlayOnly() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "App/Window/WindowView.swift"
            ),
            encoding: .utf8
        )
        let sidebarHeaderSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Navigation/Sidebar/SidebarHeader.swift"
            ),
            encoding: .utf8
        )
        let dockedStart = try XCTUnwrap(source.range(of: "private func SidebarDockedColumn(sidebarPosition: SidebarPosition)"))
            .lowerBound
        let dockedEnd = try XCTUnwrap(source.range(of: "private func WebContent()"))
            .lowerBound
        let dockedSource = String(source[dockedStart..<dockedEnd])

        XCTAssertTrue(source.contains("if !windowState.isSidebarVisible"))
        XCTAssertTrue(source.contains("SidebarHoverOverlayView()"))
        XCTAssertTrue(source.contains("shouldRenderParentBrowserTrafficLights"))
        XCTAssertTrue(source.contains("BrowserWindowTrafficLights("))
        XCTAssertFalse(source.contains("BrowserWindowNativeTrafficLightVisibilityBridge("))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(sidebarHeaderSource.contains("sumiSettings.sidebarPosition.shellEdge.isLeft"))
        XCTAssertFalse(sidebarHeaderSource.contains("BrowserWindowTrafficLightPlaceholderCluster("))
        XCTAssertFalse(dockedSource.contains("SidebarHoverOverlayView"))
    }

    func testBrowserChromeGeometryUsesZenContentRadiusFormula() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = makeThemeSettings(defaults: harness.defaults)

        let defaultGeometry = BrowserChromeGeometry(settings: settings)
        XCTAssertEqual(defaultGeometry.elementSeparation, 8)
        XCTAssertEqual(defaultGeometry.outerRadius, 7)
        XCTAssertEqual(defaultGeometry.contentRadius, 5)

        settings.themeBorderRadius = 14
        let wideGeometry = BrowserChromeGeometry(settings: settings)
        XCTAssertEqual(wideGeometry.outerRadius, 14)
        XCTAssertEqual(wideGeometry.contentRadius, 10)

        settings.themeBorderRadius = 6
        let clampedGeometry = BrowserChromeGeometry(settings: settings)
        XCTAssertEqual(clampedGeometry.outerRadius, 6)
        XCTAssertEqual(clampedGeometry.contentRadius, 5)
    }

    func testSidebarColumnHostIsPaintlessAndDoesNotLeakAppKitWindowBackground() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/SidebarColumnContainerView.swift"
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

    func testOnlyCollapsedSidebarHostedRootDrawsOwnResolvedThemeBackground() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/SidebarColumnRepresentable.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var collapsedSidebarChromeBackground"))
        XCTAssertTrue(source.contains("if presentationContext.isCollapsedOverlay"))
        XCTAssertTrue(source.contains("presentationContext.mode == .collapsedVisible"))
        XCTAssertTrue(source.contains("environmentContext.resolvedThemeContext"))
        XCTAssertTrue(source.contains(".tokens(settings: environmentContext.sumiSettings)"))
        XCTAssertTrue(source.contains(".windowBackground"))
        XCTAssertTrue(source.contains("SpaceGradientBackgroundView(surface: .toolbarChrome)"))
        XCTAssertFalse(source.contains("drawsSidebarChromeBackground"))
    }

    func testSidebarHoverOverlayOnlyChoosesCollapsedPresentationContexts() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/SidebarHoverOverlayView.swift"
            ),
            encoding: .utf8
        )
        let contextStart = try XCTUnwrap(source.range(of: "private var presentationContext"))
            .lowerBound
        let contextEnd = try XCTUnwrap(source.range(of: "var body"))
            .lowerBound
        let contextSource = String(source[contextStart..<contextEnd])

        XCTAssertFalse(contextSource.contains(".docked("))
        XCTAssertTrue(contextSource.contains(".collapsedVisible("))
        XCTAssertTrue(contextSource.contains(".collapsedHidden("))
        XCTAssertTrue(contextSource.contains("sidebarPosition: sumiSettings.sidebarPosition"))
        XCTAssertTrue(source.contains("Color.clear"))
        XCTAssertTrue(source.contains(".frame(width: hoverManager.triggerWidth)"))
        XCTAssertTrue(source.contains("presentationContext.shellEdge.overlayAlignment"))
        XCTAssertTrue(source.contains("presentationContext.shellEdge.frameAlignment"))
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
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let containerSource = try XCTUnwrap(source.range(of: "// MARK: - Container View"))
            .lowerBound
        let webColumnSource = String(source[containerSource...])

        XCTAssertTrue(webColumnSource.contains("WebColumnPaintlessChrome.configure"))
        XCTAssertTrue(webColumnSource.contains("view.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(webColumnSource.contains("override var isOpaque: Bool { false }"))
        XCTAssertTrue(webColumnSource.contains("view.layer?.cornerRadius = cornerRadius"))
        XCTAssertTrue(webColumnSource.contains("view.layer?.masksToBounds = clipsToBounds"))
        XCTAssertTrue(webColumnSource.contains("singlePaneView.setChromeGeometry(chromeGeometry)"))
        XCTAssertTrue(webColumnSource.contains("chromeGeometry.elementSeparation"))
        XCTAssertFalse(webColumnSource.contains("NSColor.windowBackgroundColor.setFill()"))
    }

    func testWebsiteChromeSurfacesUseResolvedTokensAndZenGeometry() throws {
        let websiteSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteView.swift"
            ),
            encoding: .utf8
        )
        let browserSurfaceSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/BrowserContentSurface.swift"
            ),
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let emptySource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/EmptyWebsiteView.swift"
            ),
            encoding: .utf8
        )
        let historySource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/History/SumiHistoryTabRootView.swift"
            ),
            encoding: .utf8
        )
        let bookmarksSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Bookmarks/SumiBookmarksTabRootView.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/Settings/SumiSettingsTabRootView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(websiteSource.contains("BrowserChromeGeometry(settings: sumiSettings)"))
        XCTAssertTrue(websiteSource.contains(".browserContentSurface("))
        XCTAssertTrue(websiteSource.contains("themeContext.tokens(settings: sumiSettings).windowBackground"))
        XCTAssertTrue(websiteSource.contains("themeContext.nativeSurfaceThemeContext.tokens(settings: sumiSettings).windowBackground"))
        XCTAssertTrue(websiteSource.contains("background: nativeSurfaceContentSurfaceBackground"))
        XCTAssertTrue(browserSurfaceSource.contains("struct BrowserContentSurfaceModifier"))
        XCTAssertTrue(browserSurfaceSource.contains("RoundedRectangle("))
        XCTAssertTrue(browserSurfaceSource.contains("cornerRadius: geometry.contentRadius"))
        XCTAssertTrue(compositorSource.contains("WindowWebContentController"))
        XCTAssertTrue(compositorSource.contains("TabCompositorWrapper"))
        XCTAssertTrue(emptySource.contains("BrowserChromeGeometry(settings: sumiSettings)"))
        XCTAssertTrue(emptySource.contains("themeContext.tokens(settings: sumiSettings)"))
        XCTAssertTrue(emptySource.contains(".windowBackground"))
        XCTAssertTrue(historySource.contains("surfaceThemeContext.tokens(settings: sumiSettings)"))
        XCTAssertTrue(historySource.contains("tokens.windowBackground"))
        XCTAssertTrue(bookmarksSource.contains("surfaceThemeContext.tokens(settings: sumiSettings)"))
        XCTAssertTrue(bookmarksSource.contains("tokens.windowBackground"))
        XCTAssertTrue(settingsSource.contains("surfaceThemeContext.tokens(settings: sumiSettingsModel)"))
        XCTAssertTrue(settingsSource.contains("tokens.windowBackground"))
        XCTAssertTrue(historySource.contains("themeContext.nativeSurfaceThemeContext"))
        XCTAssertTrue(bookmarksSource.contains("themeContext.nativeSurfaceThemeContext"))
        XCTAssertTrue(settingsSource.contains("themeContext.nativeSurfaceThemeContext"))
        XCTAssertTrue(historySource.contains("nativeSurfaceSelectionBackground"))
        XCTAssertTrue(bookmarksSource.contains("nativeSurfaceSelectionBackground"))
        XCTAssertTrue(settingsSource.contains("nativeSurfaceSelectionBackground"))
        XCTAssertTrue(historySource.contains(".environment(\\.colorScheme, surfaceThemeContext.chromeColorScheme)"))
        XCTAssertTrue(bookmarksSource.contains(".environment(\\.colorScheme, surfaceThemeContext.chromeColorScheme)"))
        XCTAssertTrue(settingsSource.contains(".environment(\\.colorScheme, surfaceThemeContext.chromeColorScheme)"))
        XCTAssertFalse(historySource.contains("isSelected ? tokens.accent"))
        XCTAssertFalse(bookmarksSource.contains("selected ? tokens.accent"))
        XCTAssertFalse(settingsSource.contains("selected ? tokens.accent"))

        for source in [historySource, bookmarksSource] {
            XCTAssertFalse(source.contains("windowBackgroundColor"))
            XCTAssertFalse(source.contains("controlBackgroundColor"))
            XCTAssertFalse(source.contains("separatorColor"))
        }

        let resolvedChromeSurfaceSources = [
            websiteSource,
            browserSurfaceSource,
            emptySource,
            historySource,
            bookmarksSource,
            settingsSource
        ].joined(separator: "\n")
        XCTAssertFalse(resolvedChromeSurfaceSources.contains("Color(nsColor: .windowBackgroundColor)"))
        XCTAssertFalse(resolvedChromeSurfaceSources.contains("Color(.windowBackgroundColor)"))
    }

    func testFloatingChromeSurfacesUseResolvedTokenFills() throws {
        let surfaceSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Theme/FloatingChromeSurface.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(surfaceSource.contains("enum FloatingChromeSurfaceRole"))
        XCTAssertTrue(surfaceSource.contains("tokens.commandPaletteBackground"))
        XCTAssertTrue(surfaceSource.contains("tokens.commandPaletteChipBackground"))
        XCTAssertTrue(surfaceSource.contains("tokens.commandPaletteRowHover"))
        XCTAssertTrue(surfaceSource.contains("tokens.commandPaletteRowSelected"))
        XCTAssertTrue(surfaceSource.contains("themeContext.tokens(settings: sumiSettings)"))
        XCTAssertFalse(surfaceSource.contains("windowBackgroundColor"))
        XCTAssertFalse(surfaceSource.contains("controlBackgroundColor"))
    }

    func testTargetedFloatingSurfacesDoNotUseAppKitBackgroundColors() throws {
        let paths = [
            "Sumi/Managers/DialogManager/DialogManager.swift",
            "Sumi/Components/EmojiPicker/SumiEmojiPickerPanel.swift",
            "Sumi/Managers/SumiScripts/UI/SumiScriptsPopupView.swift",
            "Sumi/Managers/ExternalMiniWindowManager/MiniBrowserWindowView.swift"
        ]

        for path in paths {
            let source = try String(
                contentsOf: Self.repoRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains("windowBackgroundColor"), path)
            XCTAssertFalse(source.contains("controlBackgroundColor"), path)
        }

        let dialogSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/DialogManager/DialogManager.swift"
            ),
            encoding: .utf8
        )
        let emojiSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Components/EmojiPicker/SumiEmojiPickerPanel.swift"
            ),
            encoding: .utf8
        )
        let scriptsSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/SumiScripts/UI/SumiScriptsPopupView.swift"
            ),
            encoding: .utf8
        )
        let miniSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/ExternalMiniWindowManager/MiniBrowserWindowView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(dialogSource.contains(".floatingChromeSurface("))
        XCTAssertTrue(emojiSource.contains("FloatingChromeSurfaceFill(.panel)"))
        XCTAssertTrue(scriptsSource.contains("FloatingChromeSurfaceFill(.panel)"))
        XCTAssertTrue(scriptsSource.contains("FloatingChromeSurfaceFill(.elevated)"))
        XCTAssertTrue(miniSource.contains("FloatingChromeSurfaceFill(.panel)"))
    }

    func testMiniBrowserWindowUsesNeutralResolvedThemeContext() throws {
        let managerSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift"
            ),
            encoding: .utf8
        )
        let themeSource = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sumi/Managers/ExternalMiniWindowManager/MiniBrowserWindowThemeContext.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(managerSource.contains("let resolvedSettings = settings ?? SumiSettingsService()"))
        XCTAssertTrue(managerSource.contains("MiniBrowserWindowThemeContextResolver.make("))
        XCTAssertTrue(managerSource.contains(".environment(\\.sumiSettings, resolvedSettings)"))
        XCTAssertTrue(managerSource.contains(".environment(\\.resolvedThemeContext, neutralThemeContext)"))
        XCTAssertTrue(themeSource.contains("settings.windowSchemeMode"))
        XCTAssertTrue(themeSource.contains("workspaceTheme: .default"))
        XCTAssertTrue(themeSource.contains("sourceWorkspaceTheme: .default"))
        XCTAssertTrue(themeSource.contains("targetWorkspaceTheme: .default"))
        XCTAssertFalse(themeSource.contains("ZenWorkspaceThemeResolver.resolve"))
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
