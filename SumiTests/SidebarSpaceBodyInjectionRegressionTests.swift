import Combine
import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpaceBodyInjectionRegressionTests: XCTestCase {
    func testSidebarStructuralInvalidationTracksProfileRuntimeState() {
        let browserManager = BrowserManager()
        let context = WindowViewBrowserContext(browserManager: browserManager)
        var invalidationCount = 0
        let cancellable = context.sidebarStructuralInvalidation.sink {
            invalidationCount += 1
        }
        let initialInvalidationCount = invalidationCount

        browserManager.isTransitioningProfile = true
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 1)

        browserManager.isTransitioningProfile = false
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 2)

        browserManager.currentProfile = Profile(name: "Sidebar Runtime")
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 3)

        browserManager.tabStructuralRevision &+= 1
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 4)

        cancellable.cancel()
    }

    func testSidebarColumnHostedRootCarriesInjectedDragState() throws {
        let nowPlayingController = SumiNativeNowPlayingController()
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.sidebarDragState.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }

        let root = SidebarColumnHostedRoot.view(
            browserContext: SidebarBrowserContext.live(browserManager: browserManager),
            hostActions: SidebarHostActions(
                updateSidebarWidth: { _, _, _ in },
                persistWindowSession: { _ in },
                dismissWorkspaceThemePickerIfNeededCommitting: {}
            ),
            structuralInvalidation: Empty().eraseToAnyPublisher(),
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            nowPlayingController: nowPlayingController,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState,
            presentationContext: .docked(sidebarWidth: 280)
        )

        XCTAssertTrue(root.environmentContext.sidebarDragState === dragState)
        XCTAssertTrue(root.environmentContext.sidebarDragState.locationTracker === dragState.locationTracker)
        XCTAssertFalse(root.environmentContext.sidebarDragState === SidebarDragState.shared)
        XCTAssertTrue(root.environmentContext.nowPlayingController === nowPlayingController)
        XCTAssertTrue(root.environmentContext.browserContext.extensionSurfaceStore === browserManager.extensionSurfaceStore)
        XCTAssertEqual(root.presentationContext, .docked(sidebarWidth: 280))
    }
}
