import AppKit
import Foundation
import SumiDomain
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserTerminationRuntimeLeaseTests: XCTestCase {
    func testFinalizationAwaitsOffMainPermissionPublication() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiPermissionTermination-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "SumiPermissionTermination-\(UUID().uuidString)")
        )
        let publishingGate = GatedPermissionPublisher()
        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            storageDirectory: directory,
            publishingFaultInjector: { stage, _ in publishingGate.observe(stage) }
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
        XCTAssertFalse(publishingGate.didEnter)

        let lease = makeLease(browserManager)
        var didFinalize = false
        let finalization = Task { @MainActor in
            await lease.finalizeTermination()
            didFinalize = true
        }
        await waitUntil { publishingGate.didEnter }

        XCTAssertFalse(publishingGate.didRunOnMainThread)
        XCTAssertFalse(didFinalize)

        publishingGate.resume()
        await finalization.value

        XCTAssertEqual(
            siteActivityStore.persistenceDiagnostics.successfulWriteCount,
            1
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.canonicalFileName
                ).path
            )
        )
        XCTAssertTrue(
            SumiPermissionCanonicalSnapshotPublisher.Stage.allCases.allSatisfy {
                publishingGate.observedStages.contains($0)
            }
        )
    }

    func testFinalizationWaitsForSiteDataCleanupBeforeReleasingBrowserResources() async throws {
        let browserManager = try makeBrowserManager()
        var backgroundMediaEnergySaverReads = 0
        browserManager.backgroundMediaOptimizationService.attach(
            runtime: SumiBackgroundMediaOptimizationRuntime(
                liveWebViewEntries: { _ in [] },
                energySaverActive: {
                    backgroundMediaEnergySaverReads += 1
                    return false
                },
                allKnownTabs: { [] },
                visibleTabIDsByWindow: { [:] }
            )
        )
        let profile = Profile(name: "Termination")
        browserManager.profileManager.profiles = [profile]
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Termination"
        )
        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
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
        await waitUntil { siteDataPolicy.cleanupStarted }

        XCTAssertNotNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(siteDataPolicy.profileIDs, [profile.id])
        browserManager.backgroundMediaOptimizationService.reconcileNow(
            reason: "termination-in-progress"
        )
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(
            reason: "termination-in-progress"
        )
        NotificationCenter.default.post(
            name: .sumiEnergySaverPolicyChanged,
            object: nil
        )
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(backgroundMediaEnergySaverReads, 0)

        siteDataPolicy.resumeCleanup()
        await finalization.value

        XCTAssertNil(browserManager.glanceManager.currentSession)
    }

    func testCoordinatorPreparationDismissesFloatingBarAndPreservesDraft() throws {
        let browserManager = try makeBrowserManager()
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        browserManager.windowRegistry = registry
        registry.register(windowState)
        registry.setActive(windowState)
        browserManager.urlBarBundle.floatingBar.presentation.focus(
            in: windowState,
            prefill: "https://draft.example/path",
            navigateCurrentTab: true,
            reason: .keyboard
        )
        let coordinator = BrowserTerminationCoordinator(
            browserRuntime: browserManager
        )

        coordinator.prepareForTermination()

        XCTAssertFalse(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://draft.example/path")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testCoordinatorDoesNotRetainBrowserRuntimeGraph() throws {
        var browserManager: BrowserManager? = try makeBrowserManager()
        let coordinator = BrowserTerminationCoordinator(
            browserRuntime: try XCTUnwrap(browserManager)
        )
        weak let releasedBrowserManager = browserManager
        weak let releasedTabManager = browserManager?.tabManager
        weak let releasedProfileManager = browserManager?.profileManager

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedTabManager)
        XCTAssertNil(releasedProfileManager)
        XCTAssertNil(coordinator.acquireFinalizationLease())
    }

    func testAcquiredLeaseKeepsRuntimeAliveThroughCleanupAndClosesAuxiliaryWindows() async throws {
        var browserManager: BrowserManager? = try makeBrowserManager()
        weak let releasedBrowserManager = browserManager
        let windowRegistry = WindowRegistry()
        let browserWindow = makeBrowserWindow()
        var lease: BrowserTerminationRuntimeLease?
        var auxiliarySessions: AuxiliaryWindowSessionRegistry?
        var popupWebView: WKWebView?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            browserManager.windowRegistry = windowRegistry
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
        await waitUntil { releasedBrowserManager == nil }
    }

    func testBrowserRuntimeDeinitPerformsTerminalAuxiliaryCleanupWithoutLease() async throws {
        var browserManager: BrowserManager? = try makeBrowserManager()
        weak let releasedBrowserManager = browserManager
        let windowRegistry = WindowRegistry()
        let browserWindow = makeBrowserWindow()
        var auxiliarySessions: AuxiliaryWindowSessionRegistry?
        var popupWebView: WKWebView?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            browserManager.windowRegistry = windowRegistry
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

        await waitUntil { releasedBrowserManager == nil }
        XCTAssertFalse(retainedAuxiliarySessions.contains(retainedPopupWebView))
    }

    private func makeLease(
        _ browserManager: BrowserManager,
        siteDataPolicy: (any BrowserSiteDataPolicyEnforcing)? = nil
    ) -> BrowserTerminationRuntimeLease {
        BrowserTerminationRuntimeLease(
            browserRuntime: browserManager,
            modelContext: browserManager.modelContext,
            tabManager: browserManager.tabManager,
            windowPersistence: browserManager.windowSessionBundle.persistence,
            backgroundMediaOptimization: browserManager.backgroundMediaOptimizationService,
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
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.bindAppKitWindow(browserWindow, to: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
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
        permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil
    ) throws -> BrowserManager {
        BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try ModelContainer(
                    for: SumiStartupPersistence.schema,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            ),
            permissionSiteActivityStore: permissionSiteActivityStore
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while predicate() == false, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                XCTFail("Wait was cancelled: \(error)")
                return
            }
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class GatedTerminationSiteDataPolicy: BrowserSiteDataPolicyEnforcing {
    private var continuation: CheckedContinuation<Void, Never>?
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
        await withCheckedContinuation { continuation = $0 }
    }

    func resumeCleanup() {
        continuation?.resume()
        continuation = nil
    }
}

private final class GatedPermissionPublisher: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseGate = DispatchSemaphore(value: 0)
    private var entered = false
    private var ranOnMainThread = false
    private var stages: [SumiPermissionCanonicalSnapshotPublisher.Stage] = []

    var didEnter: Bool {
        lock.withLock { entered }
    }

    var didRunOnMainThread: Bool {
        lock.withLock { ranOnMainThread }
    }

    var observedStages: [SumiPermissionCanonicalSnapshotPublisher.Stage] {
        lock.withLock { stages }
    }

    func observe(_ stage: SumiPermissionCanonicalSnapshotPublisher.Stage) {
        let shouldWait = lock.withLock {
            stages.append(stage)
            ranOnMainThread = ranOnMainThread || Thread.isMainThread
            guard stage == .temporaryWrite, !entered else { return false }
            entered = true
            return true
        }
        if shouldWait {
            releaseGate.wait()
        }
    }

    func resume() {
        releaseGate.signal()
    }
}
