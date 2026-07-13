import Combine
import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpaceBodyInjectionRegressionTests: XCTestCase {
    func testSidebarUpdateStreamsSeparateInventoryFromProfileRuntime() {
        let browserManager = BrowserManager()
        let context = WindowViewBrowserContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            defaultBrowserService: SumiDefaultBrowserService()
        )
        var invalidationCount = 0
        let inventoryCancellable = context.sidebarUpdates.inventoryRevision.sink { _ in
            invalidationCount += 1
        }
        let profileCancellable = context.sidebarUpdates.profileRuntimeChanged.sink {
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

        inventoryCancellable.cancel()
        profileCancellable.cancel()
    }

    func testSidebarColumnHostedRootCarriesInjectedDragState() throws {
        let nowPlayingController = SumiNativeNowPlayingController()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        windowRegistry.register(windowState)
        browserManager.windowRegistry = windowRegistry
        let viewContext = WindowViewBrowserContext.make(
            browserManager: browserManager,
            updaterService: updaterService,
            defaultBrowserService: SumiDefaultBrowserService()
        )
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.sidebarDragState.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }

        let environmentContext = SidebarHostEnvironmentContext(
            browserContext: viewContext.sidebarBrowserContext,
            hostActions: SidebarHostActions(
                updateSidebarWidth: { _, _, _ in /* No-op. */ },
                persistWindowSession: { _ in /* No-op. */ },
                dismissThemePickerCommittingIfNeeded: { /* No-op. */ }
            ),
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState
        )
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: .docked(sidebarWidth: 280),
            inventory: viewContext.sidebarInventory,
            selection: viewContext.sidebarSelection,
            pinProjection: viewContext.sidebarPinProjection,
            pinCommands: viewContext.sidebarPinCommands,
            spaceLifecycle: viewContext.sidebarSpaceLifecycle,
            regularTabs: viewContext.sidebarRegularTabs,
            dragTransactions: viewContext.sidebarDragTransactions,
            updateStreams: viewContext.sidebarUpdates
        )

        XCTAssertIdentical(root.environmentContext.sidebarDragState, dragState)
        XCTAssertIdentical(root.environmentContext.sidebarDragState.locationTracker, dragState.locationTracker)
        XCTAssertIdentical(root.environmentContext.nowPlayingController, nowPlayingController)
        XCTAssertIdentical(root.environmentContext.updaterService, updaterService)
        XCTAssertIdentical(
            root.environmentContext.browserContext.extensionSurfaceStore,
            browserManager.optionalModules.extensions.surfaceStore
        )
        XCTAssertEqual(root.presentationContext, .docked(sidebarWidth: 280))
    }
}
