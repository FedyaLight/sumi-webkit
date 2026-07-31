import AppKit
import Foundation
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserTerminationRuntimeLeaseTests: XCTestCase {
    func testFinalizationFlushesPermissionStateToBrowserDatabase() async throws {
        let database = try SumiDatabase.inMemory()
        let authority = SumiPermissionPersistenceAuthority(
            database: database
        )
        let siteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: authority
        )
        let browserManager = try makeBrowserManager(
            permissionSiteActivityStore: siteActivityStore
        )
        let origin = SumiPermissionOrigin(string: "https://example.com")
        let key = SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "termination-flush"
        )
        browserManager.permissionRuntime.cancelPermissionEventObservation()
        let lease = makeLease(browserManager)
        await lease.finalizeTermination()

        XCTAssertEqual(
            siteActivityStore.persistenceDiagnostics.successfulWriteCount,
            1
        )
        let persisted = try database.read {
            try $0.permissionAuxiliary.load()
        }
        XCTAssertEqual(
            persisted.siteActivityRecords.first?.lastState,
            .allow
        )
    }

    func testFinalizationWaitsForSiteDataCleanupBeforeReleasingBrowserResources() async throws {
        let browserManager = try makeBrowserManager()
        let profile = Profile(name: "Termination")
        browserManager.profileManager.profiles = [profile]
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Termination"
        )
        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.glanceManager.presentExternalURL(
            try XCTUnwrap(URL(string: "https://glance.example/page")),
            from: sourceTab
        )
        let siteDataPolicy = GatedTerminationSiteDataPolicy()
        let lease = makeLease(browserManager, siteDataPolicy: siteDataPolicy)

        let finalization = Task { @MainActor in
            await lease.finalizeTermination()
        }
        await siteDataPolicy.waitUntilStarted()

        XCTAssertNotNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(siteDataPolicy.profileIDs, [profile.id])

        siteDataPolicy.resumeCleanup()
        await finalization.value

        XCTAssertNil(browserManager.glanceManager.currentSession)
    }

    func testCoordinatorPreparationDismissesCommandPaletteAndPreservesDraft() throws {
        let registry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: registry)
        let windowState = BrowserWindowState()
        registry.register(windowState)
        registry.setActive(windowState)
        browserManager.urlBarBundle.commandPalettePresentation.focus(
            in: windowState,
            prefill: "https://draft.example/path",
            navigateCurrentTab: true,
            reason: .keyboard
        )
        let coordinator = BrowserTerminationCoordinator(
            browserRuntime: browserManager
        )

        coordinator.prepareForTermination()

        XCTAssertFalse(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPaletteDraftText, "https://draft.example/path")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
    }

    func testCoordinatorDoesNotRetainBrowserRuntimeGraph() throws {
        var browserManager: BrowserManager? = try makeBrowserManager()
        let coordinator = BrowserTerminationCoordinator(
            browserRuntime: try XCTUnwrap(browserManager)
        )
        weak let releasedBrowserManager = browserManager
        weak let releasedRuntimeConnection = browserManager?.runtimePortConnection
        weak let releasedProfileManager = browserManager?.profileManager

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedRuntimeConnection)
        XCTAssertNil(releasedProfileManager)
        XCTAssertNil(coordinator.acquireFinalizationLease())
    }

    func testAcquiredLeaseKeepsRuntimeAliveThroughCleanupAndClosesAuxiliaryWindows() async throws {
        let windowRegistry = WindowRegistry()
        var browserManager: BrowserManager? = try makeBrowserManager(
            windowRegistry: windowRegistry
        )
        weak let releasedBrowserManager = browserManager
        let browserWindow = makeBrowserWindow()
        var lease: BrowserTerminationRuntimeLease?
        var auxiliarySessions: AuxiliaryWindowSessionRegistry?
        var popupWebView: WKWebView?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let sourceTab = configureAuxiliaryWindowSource(
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                browserWindow: browserWindow
            )
            let auxiliaryWindows = browserManager.auxiliaryWindows
            popupWebView = auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(
                    url: try XCTUnwrap(URL(string: "https://popup.example/path"))
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: sourceTab,
                shouldActivateApp: false
            )
            auxiliarySessions = auxiliaryWindows.sessions
            lease = makeLease(browserManager)
        }

        let retainedPopupWebView = try XCTUnwrap(popupWebView)
        let retainedAuxiliarySessions = try XCTUnwrap(auxiliarySessions)
        XCTAssertTrue(retainedAuxiliarySessions.contains(retainedPopupWebView))

        browserManager = nil
        XCTAssertNotNil(releasedBrowserManager)

        await lease?.finalizeTermination()

        XCTAssertFalse(retainedAuxiliarySessions.contains(retainedPopupWebView))
        lease = nil
        XCTAssertNil(releasedBrowserManager)
    }

    func testBrowserRuntimeDeinitPerformsTerminalAuxiliaryCleanupWithoutLease() async throws {
        let windowRegistry = WindowRegistry()
        var browserManager: BrowserManager? = try makeBrowserManager(
            windowRegistry: windowRegistry
        )
        weak let releasedBrowserManager = browserManager
        let browserWindow = makeBrowserWindow()
        var auxiliarySessions: AuxiliaryWindowSessionRegistry?
        var popupWebView: WKWebView?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let sourceTab = configureAuxiliaryWindowSource(
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                browserWindow: browserWindow
            )
            let auxiliaryWindows = browserManager.auxiliaryWindows
            popupWebView = auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(
                    url: try XCTUnwrap(URL(string: "https://popup.example/path"))
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: sourceTab,
                shouldActivateApp: false
            )
            auxiliarySessions = auxiliaryWindows.sessions
        }

        let retainedPopupWebView = try XCTUnwrap(popupWebView)
        let retainedAuxiliarySessions = try XCTUnwrap(auxiliarySessions)
        XCTAssertTrue(retainedAuxiliarySessions.contains(retainedPopupWebView))

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertFalse(retainedAuxiliarySessions.contains(retainedPopupWebView))
    }

    private func makeLease(
        _ browserManager: BrowserManager,
        siteDataPolicy: (any BrowserSiteDataPolicyEnforcing)? = nil
    ) -> BrowserTerminationRuntimeLease {
        BrowserTerminationRuntimeLease(
            browserRuntime: browserManager,
            tabPersistence: browserManager.structuralPersistence,
            windowPersistence: browserManager.windowSessionPersistenceCoordinator,
            cleanup: browserManager.shutdownCleanupService,
            siteDataPolicy: siteDataPolicy
                ?? browserManager.dataServices.siteDataPolicyEnforcementService,
            profiles: browserManager.profileManager
        )
    }

    private func configureAuxiliaryWindowSource(
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        browserWindow: NSWindow
    ) -> Tab {
        let profile = Profile(name: "Auxiliary termination")
        let space = Space(name: "Auxiliary termination", profileId: profile.id)
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.bindAppKitWindow(browserWindow, to: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.selectTab(sourceTab, in: windowState)
        return sourceTab
    }

    private func makeBrowserWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    private func makeBrowserManager(
        windowRegistry: WindowRegistry = WindowRegistry(),
        permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil
    ) throws -> BrowserManager {
        BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try SumiDatabase.inMemory()
            ),
            permissionSiteActivityStore: permissionSiteActivityStore
        )
    }
}

@MainActor
private final class GatedTerminationSiteDataPolicy: BrowserSiteDataPolicyEnforcing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cleanupStarted = false
    private(set) var profileIDs: [UUID] = []

    func attachDestructiveCleanupPreparer(
        _: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {}

    func setBlockStorage(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) async {}

    func setDeleteWhenAllWindowsClosed(
        _: Bool,
        forHost _: String,
        profile _: Profile?
    ) {}

    func enforceBlockStorageIfNeeded(for _: URL?, profile _: Profile?) {}

    func performAllWindowsClosedCleanup(profiles: [Profile]) async {
        cleanupStarted = true
        profileIDs = profiles.map(\.id)
        let startWaiters = startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard cleanupStarted == false else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeCleanup() {
        continuation?.resume()
        continuation = nil
    }
}
