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
        await publishingGate.waitUntilEntered()

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

    func testCoordinatorPreparationDismissesCommandPaletteAndPreservesDraft() throws {
        let registry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: registry)
        let windowState = BrowserWindowState()
        registry.register(windowState)
        registry.setActive(windowState)
        browserManager.urlBarBundle.commandPalette.presentation.focus(
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
            modelContext: browserManager.modelContext,
            tabPersistence: browserManager.structuralPersistence,
            windowPersistence: browserManager.windowSessionPersistenceCoordinator,
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
            startupPersistence: BrowserManagerStartupPersistence(
                container: try ModelContainer(
                    for: SumiStartupPersistence.schema,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
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

private final class GatedPermissionPublisher: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseGate = DispatchSemaphore(value: 0)
    private var entered = false
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []
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
        let result: (shouldWait: Bool, waiters: [CheckedContinuation<Void, Never>]) = lock.withLock {
            stages.append(stage)
            ranOnMainThread = ranOnMainThread || Thread.isMainThread
            guard stage == .temporaryWrite, !entered else { return (false, []) }
            entered = true
            let waiters = enterWaiters
            enterWaiters.removeAll()
            return (true, waiters)
        }
        result.waiters.forEach { $0.resume() }
        if result.shouldWait {
            releaseGate.wait()
        }
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard entered == false else { return true }
                enterWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func resume() {
        releaseGate.signal()
    }
}
