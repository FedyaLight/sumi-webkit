import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionArchitectureTests: XCTestCase {
    func testTabWithoutCommittedReplicaEvidenceFailsClosed() {
        let tab = makeTab(path: "awaiting-document-evidence")
        let evaluator = TabSuspensionEligibilityEvaluator()
        let context = TabSuspensionEvaluationContext(
            visibleTabIDs: [],
            selectedTabIDs: [],
            policy: TabSuspensionPolicy(memoryMode: .balanced)
        )

        XCTAssertEqual(
            evaluator.tabIneligibility(for: tab, context: context),
            .ineligible(reason: .documentEvidencePending)
        )
    }

    func testInstallPublishesCompletePolicyAndVisibilityContextToCatalog() {
        let harness = TabSuspensionHarness(installImmediately: false)
        let windowID = UUID()
        let visibleTabID = UUID()
        let splitTabID = UUID()
        let selectedTabID = UUID()
        harness.memoryMode = .custom
        harness.customDeactivationDelay = 90 * 60
        harness.energySaverActive = true
        harness.visibleTabIDsByWindow = [windowID: [visibleTabID, splitTabID]]
        harness.selectedTabIDs = [selectedTabID]

        harness.install()

        XCTAssertEqual(harness.refreshedLazyRestoreContexts.count, 1)
        let context = harness.refreshedLazyRestoreContexts[0]
        XCTAssertEqual(context.visibleTabIDs, [visibleTabID, splitTabID])
        XCTAssertEqual(context.selectedTabIDs, [selectedTabID])
        XCTAssertEqual(context.policy.memoryMode, .custom)
        XCTAssertEqual(context.policy.proactiveDeactivationDelay, 60 * 60)
        XCTAssertEqual(
            context.policy.revisitProtectionLimit,
            TabSuspensionPolicy.customRevisitProtectionLimit
        )
    }

    func testGlobalVisibilityQueryDoesNotReadPolicySelectionOrCatalog() {
        let harness = TabSuspensionHarness()
        let visibleTabID = UUID()
        harness.visibleTabIDsByWindow = [UUID(): [visibleTabID]]
        harness.resetReadCounts()

        XCTAssertEqual(harness.controller.globallyVisibleTabIDs(), [visibleTabID])
        XCTAssertEqual(harness.visibleTabIDsByWindowReadCount, 1)
        XCTAssertEqual(harness.policyReadCount, 0)
        XCTAssertEqual(harness.selectedTabIDsReadCount, 0)
        XCTAssertEqual(harness.allKnownTabsReadCount, 0)
    }

    func testMemoryPressureWithNoLiveWebViewsEvaluatesRuntimeWithoutSuspending() {
        let harness = TabSuspensionHarness()
        let tab = makeTab(path: "no-live-webviews")
        harness.tabs = [tab]
        harness.resetReadCounts()

        harness.memoryMonitor.emit(.warning)

        XCTAssertEqual(harness.policyReadCount, 1)
        XCTAssertEqual(harness.allKnownTabsReadCount, 1)
        XCTAssertEqual(harness.selectedTabIDsReadCount, 1)
        XCTAssertEqual(harness.visibleTabIDsByWindowReadCount, 1)
        XCTAssertFalse(tab.suspensionState.isSuspended)
        XCTAssertEqual(harness.refreshedLazyRestoreContexts.count, 0)
    }

    func testControllerStartsAndStopsMemoryMonitorOnlyAroundInstalledRuntime() {
        let monitor = SuspensionMemoryMonitorProbe()
        var controller: TabSuspensionController? = TabSuspensionController(
            memoryMonitor: monitor
        )

        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertNil(monitor.eventHandler)

        controller?.install(
            runtime: TabSuspensionRuntimePorts(
                context: .inactive,
                webView: .inactive,
                catalog: .inactive
            )
        )

        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertNotNil(monitor.eventHandler)

        controller = nil

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertNil(monitor.eventHandler)
    }

    func testMemoryPressureMarksTabSuspendedOnlyAfterWebKitMutationCommits() {
        let monitor = SuspensionMemoryMonitorProbe()
        let commitProbe = SuspensionCommitProbe()
        let webView = WKWebView()
        let url = URL(string: "https://example.com/transaction")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: url)
        let tab = Tab(
            url: url,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let suspensionDate = Date(timeIntervalSince1970: 123)
        let controller = TabSuspensionController(
            memoryMonitor: monitor,
            dateProvider: { suspensionDate }
        )
        establishAllowedSuspensionDocument(
            on: webView,
            for: tab,
            transaction: transaction
        )
        controller.install(
            runtime: TabSuspensionRuntimePorts(
                context: TabSuspensionContextRuntime(
                    selectedTabIDs: { [] },
                    visibleTabIDsByWindow: { [:] }
                ),
                webView: TabSuspensionWebViewRuntime(
                    liveWebViews: { _ in [webView] },
                    suspendWebViews: { _, reason in
                        commitProbe.reasons.append(reason)
                        return commitProbe.shouldCommit
                    },
                    isProtectedFromCompositorMutation: { _ in false }
                ),
                catalog: TabSuspensionCatalogRuntime(
                    allKnownTabs: { [tab] },
                    refreshLazyRestoreQueue: { _ in }
                )
            )
        )

        monitor.emit(.warning)
        XCTAssertFalse(tab.suspensionState.isSuspended)

        commitProbe.shouldCommit = true
        monitor.emit(.warning)

        XCTAssertTrue(tab.suspensionState.isSuspended)
        XCTAssertEqual(tab.lastSelectedAt, suspensionDate)
        XCTAssertEqual(
            commitProbe.reasons,
            ["memory-pressure-warning", "memory-pressure-warning"]
        )
    }

    func testControllerDoesNoRuntimeTimerOrMonitorWorkBeforeInstall() async {
        let monitor = SuspensionMemoryMonitorProbe()
        var policyReadCount = 0
        var timerSleepCount = 0
        let controller = TabSuspensionController(
            memoryMonitor: monitor,
            timerSleep: { _ in
                timerSleepCount += 1
            }
        )
        controller.configurePolicy {
            policyReadCount += 1
            return TabSuspensionPolicy(memoryMode: .balanced)
        }

        controller.scheduleReconciliation(reason: "before-install")
        controller.navigationDidStart(for: makeTab(path: "before-install"))
        await Task.yield()

        XCTAssertEqual(policyReadCount, 0)
        XCTAssertEqual(timerSleepCount, 0)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertNil(monitor.eventHandler)
    }

    func testPolicyRebuildClearsStaleHiddenIntervalForNowVisibleTab() {
        let clock = MutableSuspensionClock(liveUptime: 0)
        var visibleTabIDs: Set<UUID> = []
        let webView = WKWebView()
        let url = URL(string: "https://example.com/rebuild")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: url)
        let tab = Tab(
            url: url,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let controller = TabSuspensionController(
            memoryMonitor: nil,
            suspensionClock: clock,
            timerSleep: { _ in
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
        establishAllowedSuspensionDocument(
            on: webView,
            for: tab,
            transaction: transaction
        )
        controller.install(
            runtime: TabSuspensionRuntimePorts(
                context: TabSuspensionContextRuntime(
                    selectedTabIDs: { [] },
                    visibleTabIDsByWindow: { [UUID(): visibleTabIDs] }
                ),
                webView: TabSuspensionWebViewRuntime(
                    liveWebViews: { _ in [webView] },
                    suspendWebViews: { _, _ in true },
                    isProtectedFromCompositorMutation: { _ in false }
                ),
                catalog: TabSuspensionCatalogRuntime(
                    allKnownTabs: { [tab] },
                    refreshLazyRestoreQueue: { _ in }
                )
            )
        )

        XCTAssertEqual(
            controller.scheduledTimerDeadlineForTesting,
            TabSuspensionPolicy.balancedProactiveDeactivationDelay
        )

        clock.liveUptime = 10
        visibleTabIDs = [tab.id]
        controller.configurePolicy {
            TabSuspensionPolicy(memoryMode: .balanced)
        }
        XCTAssertNil(controller.scheduledTimerDeadlineForTesting)

        clock.liveUptime = 20
        visibleTabIDs = []
        controller.configurePolicy {
            TabSuspensionPolicy(memoryMode: .balanced)
        }
        XCTAssertEqual(
            controller.scheduledTimerDeadlineForTesting,
            20 + TabSuspensionPolicy.balancedProactiveDeactivationDelay
        )
    }

    private func makeTab(path: String) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(path)")!,
            loadsCachedFaviconOnInit: false
        )
    }

    private func establishAllowedSuspensionDocument(
        on webView: WKWebView,
        for tab: Tab,
        transaction: TabMainFrameRuntimeTransaction
    ) {
        _ = tab.beginMainFrameNavigationIntent(to: tab.url)
        guard let submission = tab.mainFrameLoads.claimDirectSubmission(on: webView) else {
            return XCTFail("Expected main-frame submission lease")
        }
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        XCTAssertTrue(transaction.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: tab.url,
            isPDF: false
        ).shouldPublishSharedEffects)
        guard let lease = tab.committedDocumentRuntime.lease(for: webView) else {
            return XCTFail("Expected committed-document lease")
        }
        guard let token = tab.committedDocumentRuntime
            .suspensionActivationToken(for: webView) else {
            return XCTFail("Expected exact document suspension token")
        }
        XCTAssertTrue(tab.committedDocumentRuntime.recordSuspensionReport(
            TabDocumentSuspensionReport(
                documentNonce: "test-document",
                documentLeaseToken: token,
                sequence: 1,
                canBeSuspended: true,
                hasPictureInPictureVideo: false
            ),
            from: webView,
            matching: lease
        ))
        withExtendedLifetime(navigation) {}
    }
}

@MainActor
private final class TabSuspensionHarness {
    let memoryMonitor = SuspensionMemoryMonitorProbe()
    private(set) var controller: TabSuspensionController!
    var memoryMode: SumiMemoryMode = .balanced
    var customDeactivationDelay: TimeInterval = SumiMemorySaverCustomDelay.defaultDelay
    var energySaverActive = false
    var tabs: [Tab] = []
    var selectedTabIDs: Set<UUID> = []
    var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
    private(set) var refreshedLazyRestoreContexts: [TabSuspensionEvaluationContext] = []
    private(set) var policyReadCount = 0
    private(set) var allKnownTabsReadCount = 0
    private(set) var selectedTabIDsReadCount = 0
    private(set) var visibleTabIDsByWindowReadCount = 0

    init(installImmediately: Bool = true) {
        let controller = TabSuspensionController(
            memoryMonitor: memoryMonitor,
            timerSleep: { _ in /* No-op. */ }
        )
        self.controller = controller
        controller.configurePolicy { [weak self] in
            guard let self else {
                return TabSuspensionPolicy(memoryMode: .balanced)
            }
            policyReadCount += 1
            return TabSuspensionPolicy(
                memoryMode: memoryMode,
                customDeactivationDelay: customDeactivationDelay,
                energySaverActive: energySaverActive
            )
        }
        if installImmediately {
            install()
        }
    }

    func install() {
        controller.install(
            runtime: TabSuspensionRuntimePorts(
                context: TabSuspensionContextRuntime(
                    selectedTabIDs: { [weak self] in
                        self?.selectedTabIDsReadCount += 1
                        return self?.selectedTabIDs ?? []
                    },
                    visibleTabIDsByWindow: { [weak self] in
                        self?.visibleTabIDsByWindowReadCount += 1
                        return self?.visibleTabIDsByWindow ?? [:]
                    }
                ),
                webView: TabSuspensionWebViewRuntime(
                    liveWebViews: { _ in [] },
                    suspendWebViews: { _, _ in false },
                    isProtectedFromCompositorMutation: { _ in false }
                ),
                catalog: TabSuspensionCatalogRuntime(
                    allKnownTabs: { [weak self] in
                        self?.allKnownTabsReadCount += 1
                        return self?.tabs ?? []
                    },
                    refreshLazyRestoreQueue: { [weak self] context in
                        self?.refreshedLazyRestoreContexts.append(context)
                    }
                )
            )
        )
    }

    func resetReadCounts() {
        refreshedLazyRestoreContexts.removeAll()
        policyReadCount = 0
        allKnownTabsReadCount = 0
        selectedTabIDsReadCount = 0
        visibleTabIDsByWindowReadCount = 0
    }
}

private final class MutableSuspensionClock: SumiSuspensionClock {
    var liveUptime: TimeInterval

    init(liveUptime: TimeInterval) {
        self.liveUptime = liveUptime
    }
}

@MainActor
private final class SuspensionCommitProbe {
    var shouldCommit = false
    var reasons: [String] = []
}

@MainActor
private final class SuspensionMemoryMonitorProbe: SumiMemoryPressureMonitoring {
    var eventHandler: ((SumiMemoryPressureLevel) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ level: SumiMemoryPressureLevel) {
        eventHandler?(level)
    }
}
