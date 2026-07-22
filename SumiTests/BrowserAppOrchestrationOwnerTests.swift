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
        XCTAssertNotNil(harness.appDelegate.mouseButtonRouter)
        XCTAssertTrue(
            harness.appDelegate.externalURLHandler is ExternalURLTabOpeningService
        )
        XCTAssertNotNil(harness.appDelegate.terminationCoordinator)
        XCTAssertNotNil(harness.appDelegate.appLifecycleHandler)
        XCTAssertNotIdentical(harness.appDelegate.appLifecycleHandler as AnyObject?, harness.browserManager)
        XCTAssertIdentical(harness.appDelegate.settingsHandler, harness.settingsManager)
        XCTAssertIdentical(harness.appDelegate.shortcutManager, harness.keyboardShortcutManager)
        XCTAssertIdentical(
            harness.dependencies.webViewLifecycle,
            harness.browserManager.webViewRuntime.lifecycleService
        )
        XCTAssertIdentical(harness.browserManager.windowRegistry, harness.windowRegistry)
        XCTAssertIdentical(harness.browserManager.sumiSettings, harness.settingsManager)
        XCTAssertIdentical(
            harness.browserManager.keyboardShortcutManager,
            harness.keyboardShortcutManager
        )
        XCTAssertIdentical(
            harness.browserManager.runtimePortConnection.current?.settings,
            harness.settingsManager
        )
        XCTAssertNotNil(harness.browserManager.windowShellContentViewFactory)
        XCTAssertEqual(harness.startUpdaterCallCount(), 1)
    }

    func testSetupInstallsWindowRegistryCallbacks() {
        let harness = makeHarness()

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertTrue(harness.windowRegistry.hasInstalledEventSink)
    }

    func testSetupRejectsPreinstalledRegistrySinkBeforeMutatingAppGraph() {
        let harness = makeHarness()
        installWindowRegistryTestEventSink(on: harness.windowRegistry)

        XCTAssertFalse(
            harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        )
        XCTAssertNil(harness.appDelegate.windowRegistry)
        XCTAssertIdentical(
            harness.browserManager.windowRegistry,
            harness.windowRegistry
        )
        XCTAssertEqual(harness.startUpdaterCallCount(), 0)
    }

    func testSetupRestoresExistingAndFutureWindowRegistrations() {
        let harness = makeHarness()
        let existingWindow = BrowserWindowState()
        let futureWindow = BrowserWindowState()
        harness.windowRegistry.register(existingWindow)

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)
        harness.windowRegistry.register(futureWindow)

        XCTAssertTrue(
            harness.browserManager.tabResidenceAuthority.owns(existingWindow)
        )
        XCTAssertTrue(
            harness.browserManager.tabResidenceAuthority.owns(futureWindow)
        )
    }

    func testSetupAttachesExactExtensionCommandSurface() throws {
        let harness = makeHarness()

        harness.owner.setupIfNeeded(dependencies: harness.dependencies)

        XCTAssertIdentical(
            harness.keyboardShortcutManager.extensionsModule,
            harness.browserManager.optionalModules.extensions
        )
        XCTAssertFalse(
            harness.browserManager.optionalModules.extensions.hasLoadedRuntime
        )
    }

    func testFullSetupGraphReleasesBrowserManagerAndDisablesLateMouseCommands() async throws {
        let owner = BrowserAppOrchestrationOwner()
        let appDelegate = AppDelegate()
        let nowPlayingController = SumiNativeNowPlayingController()
        let settings = SumiSettingsService(nowPlayingController: nowPlayingController)
        let registry = WindowRegistry()
        let shortcuts = KeyboardShortcutManager(installEventMonitor: false)
        var browserManager: BrowserManager? = BrowserManager(
            windowRegistry: registry,
            nowPlayingController: nowPlayingController
        )
        weak let releasedBrowserManager = browserManager
        weak var releasedRestorationService: BrowserWindowSessionRestorationService?
        weak var releasedActivationService: BrowserWindowActivationService?
        weak var releasedWindowExtensionPublication:
            WindowExtensionPublicationTransaction?
        weak var releasedProfileManager: ProfileManager?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            releasedProfileManager = browserManager.profileManager
            releasedRestorationService = browserManager.windowSessionBundle.restoration
            releasedActivationService = browserManager.windowActivation
            releasedWindowExtensionPublication =
                browserManager.windowExtensionPublication
            let contentFactory: BrowserWindowShellService.ContentViewFactory = { [weak browserManager] _, _ in
                guard browserManager != nil else { return NSView() }
                return NSView()
            }
            owner.setupIfNeeded(
                dependencies: BrowserAppOrchestrationOwner.Dependencies(
                    appDelegate: appDelegate,
                    browserManager: browserManager,
                    webViewLifecycle: browserManager.webViewRuntime.lifecycleService,
                    settingsManager: settings,
                    keyboardShortcutManager: shortcuts,
                    nowPlayingController: nowPlayingController,
                    windowShellContentViewFactory: contentFactory,
                    fallbackPersistenceSave: { /* No-op. */ },
                    startUpdater: { /* No-op. */ }
                )
            )
        }

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedRestorationService)
        XCTAssertNil(releasedActivationService)
        XCTAssertNil(releasedWindowExtensionPublication)
        XCTAssertNil(releasedProfileManager)
        XCTAssertNotNil(appDelegate.terminationCoordinator)
        XCTAssertNil(appDelegate.terminationCoordinator?.acquireFinalizationLease())
        let lateWindowState = BrowserWindowState()
        registry.register(lateWindowState)
        registry.setActive(lateWindowState)
        registry.notifyWindowVisibilityChanged(lateWindowState)
        appDelegate.mouseButtonRouter?.focusFloatingBar(
            in: lateWindowState,
            prefill: "late",
            navigateCurrentTab: true
        )
        XCTAssertFalse(lateWindowState.presentationState.isFloatingBarVisible)
        registry.unregister(lateWindowState.id)
    }

    private func makeHarness() -> Harness {
        let owner = BrowserAppOrchestrationOwner()
        let appDelegate = AppDelegate()
        let nowPlayingController = SumiNativeNowPlayingController()
        let settingsManager = SumiSettingsService(nowPlayingController: nowPlayingController)
        settingsManager.sidebarMiniPlayerEnabled = false
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            nowPlayingController: nowPlayingController
        )
        let keyboardShortcutManager = KeyboardShortcutManager(installEventMonitor: false)
        var startUpdaterCallCount = 0
        let factory: BrowserWindowShellService.ContentViewFactory = { _, _ in
            NSView()
        }
        let dependencies = BrowserAppOrchestrationOwner.Dependencies(
            appDelegate: appDelegate,
            browserManager: browserManager,
            webViewLifecycle: browserManager.webViewRuntime.lifecycleService,
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
            settingsManager: settingsManager,
            keyboardShortcutManager: keyboardShortcutManager,
            dependencies: dependencies,
            startUpdaterCallCount: { startUpdaterCallCount }
        )
    }

    private static func makeKeyDownEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: 7
        )
    }
}

@MainActor
private struct Harness {
    let owner: BrowserAppOrchestrationOwner
    let appDelegate: AppDelegate
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let settingsManager: SumiSettingsService
    let keyboardShortcutManager: KeyboardShortcutManager
    let dependencies: BrowserAppOrchestrationOwner.Dependencies
    let startUpdaterCallCount: () -> Int
}
