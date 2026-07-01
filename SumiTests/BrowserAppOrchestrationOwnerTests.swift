import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserAppOrchestrationOwnerTests: XCTestCase {
    func testSetupWiresApplicationRuntimeDependenciesOnce() {
        let harness = makeHarness()

        let firstSetup = harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        let secondSetup = harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertTrue(firstSetup)
        XCTAssertFalse(secondSetup)
        XCTAssertIdentical(harness.appDelegate.windowRegistry, harness.windowRegistry)
        XCTAssertIdentical(
            harness.appDelegate.mouseButtonRouter,
            harness.browserManager.appCommandRouter
        )
        XCTAssertIdentical(
            harness.appDelegate.tabCommandRouter,
            harness.browserManager.appCommandRouter
        )
        XCTAssertIdentical(
            harness.appDelegate.windowRouter,
            harness.browserManager.appCommandRouter
        )
        XCTAssertIdentical(
            harness.appDelegate.terminationHandler as AnyObject?,
            harness.browserManager.appCommandRouter
        )
        XCTAssertNotNil(harness.appDelegate.appLifecycleHandler)
        XCTAssertNotIdentical(harness.appDelegate.appLifecycleHandler as AnyObject?, harness.browserManager)
        XCTAssertIdentical(harness.appDelegate.settingsHandler, harness.settingsManager)
        XCTAssertIdentical(harness.appDelegate.shortcutManager, harness.keyboardShortcutManager)
        XCTAssertIdentical(harness.browserManager.webViewCoordinator, harness.webViewCoordinator)
        XCTAssertIdentical(harness.browserManager.windowRegistry, harness.windowRegistry)
        XCTAssertIdentical(harness.browserManager.sumiSettings, harness.settingsManager)
        XCTAssertIdentical(
            harness.browserManager.keyboardShortcutManager,
            harness.keyboardShortcutManager
        )
        XCTAssertIdentical(harness.browserManager.tabManager.sumiSettings, harness.settingsManager)
        XCTAssertNotNil(harness.browserManager.windowShellContentViewFactory)
        XCTAssertEqual(harness.startUpdaterCallCount(), 1)
    }

    func testSetupInstallsWindowRegistryCallbacks() {
        let harness = makeHarness()

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertNotNil(harness.windowRegistry.onWindowRegister)
        XCTAssertNotNil(harness.windowRegistry.onWindowClose)
        XCTAssertNotNil(harness.windowRegistry.onActiveWindowChange)
        XCTAssertNotNil(harness.windowRegistry.onWindowVisibilityChange)
        XCTAssertNotNil(harness.windowRegistry.onAllWindowsClosed)
    }

    private func makeHarness() -> Harness {
        let owner = BrowserAppOrchestrationOwner()
        let appDelegate = AppDelegate()
        let nowPlayingController = SumiNativeNowPlayingController()
        let settingsManager = SumiSettingsService(nowPlayingController: nowPlayingController)
        settingsManager.sidebarMiniPlayerEnabled = false
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowRegistry = WindowRegistry()
        let webViewCoordinator = WebViewCoordinator()
        let keyboardShortcutManager = KeyboardShortcutManager(installEventMonitor: false)
        var startUpdaterCallCount = 0
        let factory: BrowserWindowShellService.ContentViewFactory = { _, _, _ in
            NSView()
        }
        let dependencies = BrowserAppOrchestrationOwner.Dependencies(
            appDelegate: appDelegate,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            webViewCoordinator: webViewCoordinator,
            settingsManager: settingsManager,
            keyboardShortcutManager: keyboardShortcutManager,
            nowPlayingController: nowPlayingController,
            windowShellContentViewFactory: factory,
            fallbackPersistenceSave: { /* No-op. */ },
            startUpdater: {
                startUpdaterCallCount += 1
            }
        )

        return Harness(
            owner: owner,
            appDelegate: appDelegate,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            webViewCoordinator: webViewCoordinator,
            settingsManager: settingsManager,
            keyboardShortcutManager: keyboardShortcutManager,
            dependencies: dependencies,
            startUpdaterCallCount: { startUpdaterCallCount }
        )
    }
}

@MainActor
private struct Harness {
    let owner: BrowserAppOrchestrationOwner
    let appDelegate: AppDelegate
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let webViewCoordinator: WebViewCoordinator
    let settingsManager: SumiSettingsService
    let keyboardShortcutManager: KeyboardShortcutManager
    let dependencies: BrowserAppOrchestrationOwner.Dependencies
    let startUpdaterCallCount: () -> Int
}
