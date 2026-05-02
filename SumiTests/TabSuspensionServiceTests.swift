import BrowserServicesKit
import Navigation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionServiceTests: XCTestCase {
    private var now: Date!

    override func setUp() {
        super.setUp()
        now = Date()
    }

    override func tearDown() {
        now = nil
        super.tearDown()
    }

    func testActiveSelectedTabIsNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/selected", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        selected.lastSelectedAt = now.addingTimeInterval(-600)
        hidden.lastSelectedAt = now.addingTimeInterval(-1200)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.suspendedTabIDs, [hidden.id])
        XCTAssertFalse(selected.isSuspended)
        XCTAssertNotNil(harness.coordinator.getWebView(for: selected.id, in: harness.windowState.id))
    }

    func testVisibleSplitPanesAreNeverSuspended() {
        let harness = makeHarness()
        let left = makeTab("https://example.com/left", harness: harness)
        let right = makeTab("https://example.com/right", harness: harness)
        let hidden = makeTab("https://example.com/split-hidden", harness: harness)

        setCurrentTab(left, in: harness.windowState)
        var splitState = harness.browserManager.splitManager.getSplitState(for: harness.windowState.id)
        splitState.isSplit = true
        splitState.leftTabId = left.id
        splitState.rightTabId = right.id
        harness.browserManager.splitManager.setSplitState(splitState, for: harness.windowState.id)

        attachWebView(to: left, harness: harness)
        attachWebView(to: right, harness: harness)
        attachWebView(to: hidden, harness: harness)
        left.lastSelectedAt = now.addingTimeInterval(-1800)
        right.lastSelectedAt = now.addingTimeInterval(-1700)
        hidden.lastSelectedAt = now.addingTimeInterval(-1600)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.suspendedTabIDs, [hidden.id])
        XCTAssertFalse(left.isSuspended)
        XCTAssertFalse(right.isSuspended)
        XCTAssertNotNil(harness.coordinator.getWebView(for: left.id, in: harness.windowState.id))
        XCTAssertNotNil(harness.coordinator.getWebView(for: right.id, in: harness.windowState.id))
    }

    func testWarningPressureSuspendsOldestHiddenLRUTabOnly() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let oldest = makeTab("https://example.com/oldest", harness: harness)
        let recent = makeTab("https://example.com/recent", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: oldest, harness: harness)
        attachWebView(to: recent, harness: harness)
        oldest.lastSelectedAt = now.addingTimeInterval(-2400)
        recent.lastSelectedAt = now.addingTimeInterval(-60)

        let result = harness.service.handleMemoryPressure(.warning)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [oldest.id])
        XCTAssertTrue(oldest.isSuspended)
        XCTAssertFalse(recent.isSuspended)
    }

    func testRecentlySelectedHiddenTabIsNotSuspendedByMemoryPressure() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let recent = makeTab("https://example.com/recent", harness: harness)
        let old = makeTab("https://example.com/old", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: recent, harness: harness)
        attachWebView(to: old, harness: harness)
        recent.lastSelectedAt = now.addingTimeInterval(-120)
        old.lastSelectedAt = now.addingTimeInterval(-1200)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [old.id])
        XCTAssertFalse(recent.isSuspended)
        XCTAssertTrue(old.isSuspended)
    }

    func testHiddenTabWithoutLastSelectedAtIsSuspendedByMemoryPressure() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let neverSelected = makeTab("https://example.com/never-selected", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: neverSelected, harness: harness)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [neverSelected.id])
        XCTAssertTrue(neverSelected.isSuspended)
    }

    func testCriticalPressureSuspendsAllEligibleHiddenTabsInLRUOrder() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let oldest = makeTab("https://example.com/oldest", harness: harness)
        let middle = makeTab("https://example.com/middle", harness: harness)
        let newest = makeTab("https://example.com/newest", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: newest, harness: harness)
        attachWebView(to: oldest, harness: harness)
        attachWebView(to: middle, harness: harness)
        oldest.lastSelectedAt = now.addingTimeInterval(-3000)
        middle.lastSelectedAt = now.addingTimeInterval(-2000)
        newest.lastSelectedAt = now.addingTimeInterval(-1000)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 3)
        XCTAssertEqual(result.suspendedTabIDs, [oldest.id, middle.id, newest.id])
        XCTAssertTrue(oldest.isSuspended)
        XCTAssertTrue(middle.isSuspended)
        XCTAssertTrue(newest.isSuspended)
    }

    func testMemoryPressureCanSuspendPinnedHiddenRuntimeWithoutRemovingLauncherIdentity() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let pinned = makeTab("https://example.com/pinned", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)
        let originalID = pinned.id
        let originalURL = pinned.url

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: pinned, harness: harness)
        attachWebView(to: eligible, harness: harness)
        pinned.isPinned = true
        pinned.lastSelectedAt = now.addingTimeInterval(-3600)
        eligible.lastSelectedAt = now.addingTimeInterval(-1800)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 2)
        XCTAssertEqual(result.suspendedTabIDs, [pinned.id, eligible.id])
        XCTAssertTrue(pinned.isSuspended)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.id, originalID)
        XCTAssertEqual(pinned.url, originalURL)
        XCTAssertTrue(harness.browserManager.tabManager.tab(for: pinned.id) === pinned)
    }

    func testNonHTTPHiddenTabsAreNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let fileTab = makeTab("file:///tmp/suspension.html", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: fileTab, harness: harness)
        attachWebView(to: eligible, harness: harness)
        fileTab.lastSelectedAt = now.addingTimeInterval(-3600)
        eligible.lastSelectedAt = now.addingTimeInterval(-1800)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(fileTab.url.scheme, "file")
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(fileTab.isSuspended)
    }

    func testSelectedTabEligibilityIsRejectedWithReason() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: selected),
            .ineligible(reason: .selected)
        )
    }

    func testVisibleTabEligibilityIsRejectedWithReason() {
        let harness = makeHarness()
        let left = makeTab("https://example.com/left", harness: harness)
        let right = makeTab("https://example.com/right", harness: harness)

        setCurrentTab(left, in: harness.windowState)
        var splitState = harness.browserManager.splitManager.getSplitState(for: harness.windowState.id)
        splitState.isSplit = true
        splitState.leftTabId = left.id
        splitState.rightTabId = right.id
        harness.browserManager.splitManager.setSplitState(splitState, for: harness.windowState.id)
        attachWebView(to: left, harness: harness)
        attachWebView(to: right, harness: harness)

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: right),
            .ineligible(reason: .visible)
        )
    }

    func testLoadingTabEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.loadingState = .didCommit

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .loading)
        )
    }

    func testAudioTabEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .playingAudio)
        )
    }

    func testRecentlyAudibleTabEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.lastMediaActivityAt = now.addingTimeInterval(-30)

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .recentlyAudible)
        )
    }

    func testCameraCaptureEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()

        XCTAssertEqual(
            harness.service.suspensionEligibility(
                for: hidden,
                webViewStates: [.init(isCapturingCamera: true)]
            ),
            .ineligible(reason: .cameraCapture)
        )
    }

    func testMicrophoneCaptureEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()

        XCTAssertEqual(
            harness.service.suspensionEligibility(
                for: hidden,
                webViewStates: [.init(isCapturingMicrophone: true)]
            ),
            .ineligible(reason: .microphoneCapture)
        )
    }

    func testFullscreenEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()

        XCTAssertEqual(
            harness.service.suspensionEligibility(
                for: hidden,
                webViewStates: [.init(isFullscreen: true)]
            ),
            .ineligible(reason: .fullscreen)
        )
    }

    func testPictureInPictureEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.hasPictureInPictureVideo = true

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .pictureInPicture)
        )
    }

    func testPDFDocumentEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.isDisplayingPDFDocument = true

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .pdfDocument)
        )
    }

    func testPageVetoEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject()
        hidden.pageSuspensionVeto = .pageReportedUnableToSuspend

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .pageVeto)
        )
    }

    func testPageSuspensionRuntimeStateResetClearsNativeVetoAndDocumentFlags() {
        let tab = Tab(url: URL(string: "https://example.com/reset")!)
        tab.pageSuspensionVeto = .pageReportedUnableToSuspend
        tab.hasPictureInPictureVideo = true
        tab.isDisplayingPDFDocument = true

        tab.resetPageSuspensionRuntimeState()

        XCTAssertEqual(tab.pageSuspensionVeto, .none)
        XCTAssertFalse(tab.hasPictureInPictureVideo)
        XCTAssertFalse(tab.isDisplayingPDFDocument)
    }

    func testUnsupportedURLSchemeEligibilityIsRejectedWithReason() {
        let (harness, hidden) = makeEligibilitySubject(hiddenURL: "file:///tmp/suspension.html")

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: hidden),
            .ineligible(reason: .unsupportedURLScheme)
        )
    }

    func testNormalHiddenHTTPSTabEligibilityIsEligible() {
        let (harness, hidden) = makeEligibilitySubject()

        XCTAssertEqual(harness.service.suspensionEligibility(for: hidden), .eligible)
    }

    func testPinnedLauncherEligibilityPreservesLauncherIdentity() {
        let (harness, pinned) = makeEligibilitySubject(hiddenURL: "https://example.com/pinned")
        pinned.isPinned = true

        XCTAssertEqual(harness.service.suspensionEligibility(for: pinned), .eligible)
        XCTAssertNotNil(harness.browserManager.tabManager.tab(for: pinned.id))
        XCTAssertFalse(pinned.isSuspended)
    }

    func testEssentialShortcutLiveInstanceEligibilityPreservesLauncherIdentity() {
        let (harness, essential) = makeEligibilitySubject(hiddenURL: "https://example.com/essential")
        essential.isShortcutLiveInstance = true
        essential.shortcutPinRole = .essential

        XCTAssertEqual(harness.service.suspensionEligibility(for: essential), .eligible)
        XCTAssertNotNil(harness.browserManager.tabManager.tab(for: essential.id))
        XCTAssertFalse(essential.isSuspended)
    }

    func testPDFNavigationResponseUpdatesSuspensionDocumentStateWithoutBlocking() async {
        let tab = Tab(url: URL(string: "https://example.com/document.pdf")!)
        let responder = SumiTabLifecycleNavigationResponder(tab: tab)
        let response = URLResponse(
            url: tab.url,
            mimeType: "application/pdf",
            expectedContentLength: 42,
            textEncodingName: nil
        )

        let policy = await responder.decidePolicy(
            for: NavigationResponse(
                response: response,
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: nil
            )
        )

        XCTAssertNil(policy)
        XCTAssertTrue(tab.isDisplayingPDFDocument)
    }

    func testAlreadySuspendedAndUnloadedTabsAreSkipped() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let alreadySuspended = makeTab("https://example.com/already", harness: harness)
        let unloaded = makeTab("https://example.com/unloaded", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: alreadySuspended, harness: harness)
        attachWebView(to: eligible, harness: harness)
        alreadySuspended.isSuspended = true

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(unloaded.isSuspended)
    }

    func testSuspendingTabReleasesCoordinatorStateAndWebViewDelegates() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/release", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        let releasedWebView = attachWebView(to: hidden, harness: harness)
        hidden.installNavigationDelegate(on: releasedWebView)
        releasedWebView.uiDelegate = hidden
        XCTAssertNotNil(hidden.navigationDelegateBundle(for: releasedWebView))

        XCTAssertTrue(harness.service.suspend(hidden, reason: "test-release"))

        XCTAssertTrue(hidden.isSuspended)
        XCTAssertNil(hidden.existingWebView)
        XCTAssertNil(hidden.primaryWindowId)
        XCTAssertNil(harness.coordinator.getWebView(for: hidden.id, in: harness.windowState.id))
        XCTAssertNil(harness.coordinator.windowID(containing: releasedWebView))
        XCTAssertNil(releasedWebView.navigationDelegate)
        XCTAssertNil(releasedWebView.uiDelegate)
        XCTAssertNil(releasedWebView.superview)
        XCTAssertNil(hidden.navigationDelegateBundle(for: releasedWebView))
    }

    func testSelectingSuspendedTabRestoresOnlyThatTab() throws {
        let harness = makeHarness()
        let current = makeTab("https://example.com/current", harness: harness)
        let firstSuspended = makeTab("https://example.com/first", harness: harness)
        let secondSuspended = makeTab("https://example.com/second", harness: harness)

        setCurrentTab(current, in: harness.windowState)
        attachWebView(to: current, harness: harness)
        attachWebView(to: firstSuspended, harness: harness)
        attachWebView(to: secondSuspended, harness: harness)

        XCTAssertTrue(harness.service.suspend(firstSuspended, reason: "test-roundtrip"))
        XCTAssertTrue(harness.service.suspend(secondSuspended, reason: "test-roundtrip"))

        harness.browserManager.selectTab(
            firstSuspended,
            in: harness.windowState,
            loadPolicy: .immediate
        )

        let restoredWebView = try XCTUnwrap(firstSuspended.existingWebView)
        XCTAssertFalse(firstSuspended.isSuspended)
        XCTAssertTrue(secondSuspended.isSuspended)
        XCTAssertNil(secondSuspended.existingWebView)
        XCTAssertTrue(
            restoredWebView.configuration.userContentController
                .sumiUsesNormalTabBrowserServicesKitUserContentController
        )
        XCTAssertTrue(restoredWebView.configuration.userContentController is UserContentController)
    }

    func testMemoryPressureMonitorMapsWarningAndCriticalEvents() {
        let monitor = SumiMemoryPressureMonitor()
        var received: [String] = []
        monitor.eventHandler = { level in
            received.append(level.rawValue)
        }

        monitor.processMemoryPressureEventForTesting(.warning)
        monitor.processMemoryPressureEventForTesting([.warning, .critical])
        monitor.stop()

        XCTAssertEqual(received, ["warning", "critical"])
    }

    func testMemorySaverPolicyValuesMatchChromeLikePrompt22Modes() {
        let moderate = TabSuspensionPolicy(memoryMode: .moderate)
        let balanced = TabSuspensionPolicy(memoryMode: .balanced)
        let maximum = TabSuspensionPolicy(memoryMode: .maximum)
        let custom = TabSuspensionPolicy(memoryMode: .custom, customDeactivationDelay: 45 * 60)

        XCTAssertEqual(moderate.proactiveDeactivationDelay, 6 * 60 * 60)
        XCTAssertEqual(moderate.revisitProtectionLimit, 5)
        XCTAssertEqual(balanced.proactiveDeactivationDelay, 4 * 60 * 60)
        XCTAssertEqual(balanced.revisitProtectionLimit, 15)
        XCTAssertEqual(maximum.proactiveDeactivationDelay, 2 * 60 * 60)
        XCTAssertEqual(maximum.revisitProtectionLimit, 15)
        XCTAssertEqual(custom.proactiveDeactivationDelay, 45 * 60)
        XCTAssertEqual(custom.revisitProtectionLimit, 15)
        XCTAssertGreaterThan(moderate.proactiveDeactivationDelay, balanced.proactiveDeactivationDelay)
        XCTAssertGreaterThan(balanced.proactiveDeactivationDelay, maximum.proactiveDeactivationDelay)
    }

    func testProactivePolicyDefaultsToBalancedAndReadsSettingsLazily() {
        let harness = makeHarness(memoryMode: .balanced)

        XCTAssertEqual(
            harness.service.proactiveSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .balanced)
        )

        harness.settings.memoryMode = .maximum
        XCTAssertEqual(
            harness.service.proactiveSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .maximum)
        )

        harness.settings.memoryMode = .custom
        harness.settings.memorySaverCustomDeactivationDelay = 90 * 60
        XCTAssertEqual(
            harness.service.proactiveSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .custom, customDeactivationDelay: 90 * 60)
        )
    }

    func testHiddenTabStartsProactiveTimerAndVisibleTabCancelsIt() {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        let initialReconcileCount = harness.service.proactiveTimerReconcileCountForTesting
        harness.service.reconcileProactiveTimers(reason: "test-hidden")

        XCTAssertEqual(harness.service.proactiveTimerReconcileCountForTesting, initialReconcileCount + 1)
        XCTAssertEqual(harness.service.lastProactiveTimerReconcileReasonForTesting, "test-hidden")
        XCTAssertTrue(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
        XCTAssertEqual(
            harness.service.proactiveTimerStateForTesting(tabID: hidden.id)?.requestedDelay,
            4 * 60 * 60
        )

        setCurrentTab(hidden, in: harness.windowState)
        harness.service.reconcileProactiveTimers(reason: "test-visible")

        XCTAssertEqual(harness.service.proactiveTimerReconcileCountForTesting, initialReconcileCount + 2)
        XCTAssertEqual(harness.service.lastProactiveTimerReconcileReasonForTesting, "test-visible")
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
        XCTAssertEqual(harness.service.revisitCountForTesting(tabID: hidden.id), 1)
    }

    func testScheduledProactiveTimerReconcileCoalescesMultipleReasons() async {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        let initialReconcileCount = harness.service.proactiveTimerReconcileCountForTesting

        harness.service.scheduleProactiveTimerReconcile(reason: "visible-webviews-prepared")
        harness.service.scheduleProactiveTimerReconcile(reason: "tab-structure-changed")
        harness.service.scheduleProactiveTimerReconcile(reason: "visible-webviews-prepared")

        XCTAssertTrue(harness.service.isProactiveTimerReconcileScheduledForTesting)
        XCTAssertEqual(harness.service.proactiveTimerReconcileCountForTesting, initialReconcileCount)

        await harness.service.drainScheduledProactiveTimerReconcileForTesting()

        XCTAssertFalse(harness.service.isProactiveTimerReconcileScheduledForTesting)
        XCTAssertEqual(harness.service.proactiveTimerReconcileCountForTesting, initialReconcileCount + 1)
        XCTAssertEqual(
            harness.service.lastProactiveTimerReconcileReasonForTesting,
            "coalesced(tab-structure-changed,visible-webviews-prepared)"
        )
        XCTAssertTrue(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
        XCTAssertEqual(
            harness.service.proactiveTimerStateForTesting(tabID: hidden.id)?.requestedDelay,
            4 * 60 * 60
        )
    }

    func testScheduledProactiveTimerReconcileCleansRemovedTabTimers() async {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let removed = makeTab("https://example.com/removed", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: removed, harness: harness)
        harness.service.reconcileProactiveTimers(reason: "initial")
        XCTAssertTrue(harness.service.proactiveTimerTabIDsForTesting.contains(removed.id))
        let initialReconcileCount = harness.service.proactiveTimerReconcileCountForTesting

        harness.browserManager.tabManager.removeTab(removed.id)
        harness.service.scheduleProactiveTimerReconcile(reason: "tab-structure-changed")
        await harness.service.drainScheduledProactiveTimerReconcileForTesting()

        XCTAssertEqual(harness.service.proactiveTimerReconcileCountForTesting, initialReconcileCount + 1)
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(removed.id))
        XCTAssertNil(harness.service.proactiveTimerStateForTesting(tabID: removed.id))
    }

    func testModeAndCustomDelayChangesRebuildHiddenTabTimers() {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        harness.service.reconcileProactiveTimers(reason: "initial")
        let initialStarts = harness.service.proactiveTimerStartCountForTesting

        harness.settings.memoryMode = .maximum
        harness.service.rebuildProactiveTimers(reason: "mode-change")
        XCTAssertEqual(
            harness.service.proactiveTimerStateForTesting(tabID: hidden.id)?.requestedDelay,
            2 * 60 * 60
        )
        XCTAssertGreaterThan(harness.service.proactiveTimerStartCountForTesting, initialStarts)

        harness.settings.memoryMode = .custom
        harness.settings.memorySaverCustomDeactivationDelay = 30 * 60
        harness.service.rebuildProactiveTimers(reason: "custom-delay-change")
        XCTAssertEqual(
            harness.service.proactiveTimerStateForTesting(tabID: hidden.id)?.requestedDelay,
            30 * 60
        )
        XCTAssertFalse(selected.isSuspended)
        XCTAssertFalse(hidden.isSuspended)
    }

    func testProactiveTimerRearmsWhenLiveUptimeHasNotReachedDelay() {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/sleep-aware", harness: harness)

        harness.clock.liveUptime = 100
        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        harness.service.reconcileProactiveTimers(reason: "initial")

        harness.clock.liveUptime = 160
        harness.service.fireProactiveTimerForTesting(tabID: hidden.id)

        XCTAssertFalse(hidden.isSuspended)
        XCTAssertTrue(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
        XCTAssertEqual(
            harness.service.proactiveTimerStateForTesting(tabID: hidden.id)?.hiddenStartedAtLiveUptime,
            100
        )

        harness.clock.liveUptime = 100 + 4 * 60 * 60
        harness.service.fireProactiveTimerForTesting(tabID: hidden.id)

        XCTAssertTrue(hidden.isSuspended)
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
    }

    func testProactiveTimerFiringRechecksEligibility() {
        let harness = makeHarness(memoryMode: .maximum)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/page-veto", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        harness.service.reconcileProactiveTimers(reason: "initial")
        hidden.pageSuspensionVeto = .pageReportedUnableToSuspend

        harness.clock.liveUptime = 2 * 60 * 60
        harness.service.fireProactiveTimerForTesting(tabID: hidden.id)

        XCTAssertFalse(hidden.isSuspended)
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
    }

    func testAlreadySuspendedHiddenTabIsNotRepeatedlyProcessedByProactiveTimer() {
        let harness = makeHarness(memoryMode: .maximum)
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/already-suspended", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        harness.service.reconcileProactiveTimers(reason: "initial")
        hidden.isSuspended = true

        harness.clock.liveUptime = 2 * 60 * 60
        harness.service.fireProactiveTimerForTesting(tabID: hidden.id)

        XCTAssertTrue(hidden.isSuspended)
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(hidden.id))
    }

    func testRevisitProtectionPreventsProactiveTimerAndResetsOnNavigation() {
        let harness = makeHarness(memoryMode: .moderate)
        let selected = makeTab("https://example.com/current", harness: harness)
        let revisited = makeTab("https://example.com/revisited", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: revisited, harness: harness)

        for _ in 0...TabSuspensionPolicy.moderateRevisitProtectionLimit {
            setCurrentTab(selected, in: harness.windowState)
            harness.service.reconcileProactiveTimers(reason: "hidden")
            setCurrentTab(revisited, in: harness.windowState)
            harness.service.reconcileProactiveTimers(reason: "visible")
        }

        setCurrentTab(selected, in: harness.windowState)
        harness.service.reconcileProactiveTimers(reason: "hidden-after-limit")
        XCTAssertFalse(harness.service.proactiveTimerTabIDsForTesting.contains(revisited.id))
        XCTAssertGreaterThan(
            harness.service.revisitCountForTesting(tabID: revisited.id),
            TabSuspensionPolicy.moderateRevisitProtectionLimit
        )

        harness.service.resetRevisitProtection(for: revisited)
        XCTAssertTrue(harness.service.proactiveTimerTabIDsForTesting.contains(revisited.id))
        XCTAssertEqual(harness.service.revisitCountForTesting(tabID: revisited.id), 0)
    }

    func testMemoryPressureIgnoresRevisitProtection() {
        let harness = makeHarness(memoryMode: .moderate)
        let selected = makeTab("https://example.com/current", harness: harness)
        let revisited = makeTab("https://example.com/revisited-pressure", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: revisited, harness: harness)
        revisited.lastSelectedAt = now.addingTimeInterval(-3600)

        for _ in 0...TabSuspensionPolicy.moderateRevisitProtectionLimit {
            setCurrentTab(selected, in: harness.windowState)
            harness.service.reconcileProactiveTimers(reason: "hidden")
            setCurrentTab(revisited, in: harness.windowState)
            harness.service.reconcileProactiveTimers(reason: "visible")
        }
        setCurrentTab(selected, in: harness.windowState)
        harness.service.reconcileProactiveTimers(reason: "hidden-after-limit")

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.suspendedTabIDs, [revisited.id])
        XCTAssertTrue(revisited.isSuspended)
    }

    func testProactiveMemorySaverSuspendsPinnedRuntimeInAllModesWithoutDeletingLauncherIdentity() {
        for mode in SumiMemoryMode.allCases {
            let harness = makeHarness(memoryMode: mode, customDelay: 30 * 60)
            let selected = makeTab("https://example.com/current-\(mode.rawValue)", harness: harness)
            let pinned = makeTab("https://example.com/pinned-\(mode.rawValue)", harness: harness)
            let originalID = pinned.id
            let originalURL = pinned.url
            let originalTitle = pinned.name

            setCurrentTab(selected, in: harness.windowState)
            attachWebView(to: selected, harness: harness)
            attachWebView(to: pinned, harness: harness)
            pinned.isPinned = true
            harness.service.reconcileProactiveTimers(reason: "hidden-\(mode.rawValue)")

            let delay = harness.service.proactiveSuspensionPolicyForTesting().proactiveDeactivationDelay
            harness.clock.liveUptime = delay
            harness.service.fireProactiveTimerForTesting(tabID: pinned.id)

            XCTAssertTrue(pinned.isSuspended, "mode=\(mode.rawValue)")
            XCTAssertTrue(pinned.isPinned, "mode=\(mode.rawValue)")
            XCTAssertEqual(pinned.id, originalID, "mode=\(mode.rawValue)")
            XCTAssertEqual(pinned.url, originalURL, "mode=\(mode.rawValue)")
            XCTAssertEqual(pinned.name, originalTitle, "mode=\(mode.rawValue)")
            XCTAssertTrue(harness.browserManager.tabManager.tab(for: pinned.id) === pinned)
        }
    }

    func testProactiveMemorySaverSuspendsEssentialRuntimeInAllModesAndRestoreUsesExistingTabPath() throws {
        for mode in SumiMemoryMode.allCases {
            let harness = makeHarness(memoryMode: mode, customDelay: 30 * 60)
            let selected = makeTab("https://example.com/current-\(mode.rawValue)", harness: harness)
            let profileId = try XCTUnwrap(harness.browserManager.currentProfile?.id)
            let pin = makeShortcutPin(
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                index: 0,
                launchURL: URL(string: "https://example.com/essential-\(mode.rawValue)")!,
                title: "Essential \(mode.rawValue)",
                iconAsset: "star.fill"
            )

            harness.browserManager.tabManager.setPinnedTabs([pin], for: profileId)
            let liveTab = harness.browserManager.tabManager.activateShortcutPin(
                pin,
                in: harness.windowState.id,
                currentSpaceId: harness.windowState.currentSpaceId
            )

            setCurrentTab(selected, in: harness.windowState)
            attachWebView(to: selected, harness: harness)
            attachWebView(to: liveTab, harness: harness)
            harness.service.reconcileProactiveTimers(reason: "hidden-\(mode.rawValue)")

            let delay = harness.service.proactiveSuspensionPolicyForTesting().proactiveDeactivationDelay
            harness.clock.liveUptime = delay
            harness.service.fireProactiveTimerForTesting(tabID: liveTab.id)

            XCTAssertTrue(liveTab.isSuspended, "mode=\(mode.rawValue)")
            XCTAssertNil(liveTab.existingWebView, "mode=\(mode.rawValue)")
            assertShortcutPin(
                try XCTUnwrap(harness.browserManager.tabManager.essentialPins(for: profileId).first),
                matches: pin
            )
            XCTAssertTrue(
                harness.browserManager.tabManager.shortcutLiveTab(
                    for: pin.id,
                    in: harness.windowState.id
                ) === liveTab
            )

            let reactivated = harness.browserManager.tabManager.activateShortcutPin(
                pin,
                in: harness.windowState.id,
                currentSpaceId: harness.windowState.currentSpaceId
            )
            XCTAssertTrue(reactivated === liveTab)
            harness.browserManager.selectTab(
                reactivated,
                in: harness.windowState,
                loadPolicy: .immediate
            )
            _ = harness.coordinator.prepareVisibleWebViews(
                for: harness.windowState,
                browserManager: harness.browserManager
            )

            XCTAssertFalse(liveTab.isSuspended, "mode=\(mode.rawValue)")
            XCTAssertEqual(harness.coordinator.liveWebViews(for: liveTab).count, 1, "mode=\(mode.rawValue)")
            assertShortcutPin(
                try XCTUnwrap(harness.browserManager.tabManager.essentialPins(for: profileId).first),
                matches: pin
            )
        }
    }

    func testPrompt22DocumentationRecordsChromeLikeMemorySaverAndDDGSafeguards() throws {
        let source = try Self.source(named: "docs/sumi-performance-modular-execution-state.md")

        for requiredText in [
            "Prompt 22",
            "Moderate",
            "Balanced",
            "Maximum",
            "Custom Deactivation Delay",
            "6 hours",
            "4 hours",
            "2 hours",
            "per-tab one-shot",
            "sleep-aware",
            "revisit protection",
            "page-level canBeSuspended veto",
            "launcher identity",
        ] {
            XCTAssertTrue(
                source.contains(requiredText),
                "Missing Prompt 22 memory saver documentation text: \(requiredText)"
            )
        }
    }

    func testPrompt22WiresProactiveTimersWithoutEvictionOrOptionalModuleRuntimes() throws {
        let suspensionSource = try Self.source(named: "Sumi/Managers/TabSuspensionService.swift")
        let coordinatorSource = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        let changedSources = [
            suspensionSource,
            try Self.source(named: "Sumi/Models/Tab/Tab.swift"),
            try Self.source(named: "Sumi/Models/Tab/TabRuntimeState.swift"),
            try Self.source(named: "Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift"),
        ].joined(separator: "\n")

        XCTAssertTrue(suspensionSource.contains("TabSuspensionPolicy"))
        XCTAssertTrue(suspensionSource.contains("SumiMemoryMode"))
        XCTAssertTrue(suspensionSource.contains("memoryMode"))
        XCTAssertTrue(suspensionSource.contains("proactiveTimers"))
        XCTAssertTrue(suspensionSource.contains("armProactiveTimer"))
        XCTAssertTrue(suspensionSource.contains("SumiSuspensionClock"))
        XCTAssertTrue(suspensionSource.contains("revisitCounts"))
        XCTAssertFalse(suspensionSource.contains("evaluateIdleSuspension"))
        XCTAssertFalse(suspensionSource.contains("startIdleSuspensionScheduler"))
        XCTAssertFalse(suspensionSource.contains("tabUnloadTimeoutChanged"))
        XCTAssertFalse(suspensionSource.contains("canEvictHiddenWebView"))
        XCTAssertFalse(suspensionSource.contains("createWebViewInternal"))
        XCTAssertFalse(coordinatorSource.contains("suspensionEligibility("))
        XCTAssertTrue(coordinatorSource.contains("hiddenCloneCleanup"))
        XCTAssertFalse(coordinatorSource.contains("NormalTabWebViewFactory"))

        for forbiddenConstructor in [
            "SumiTrackingProtection(",
            "SumiContentBlockingService(",
            "ExtensionManager(",
            "NativeMessagingHandler(",
            "SumiScriptsManager(",
        ] {
            XCTAssertFalse(changedSources.contains(forbiddenConstructor))
        }
    }

    func testPrompt065PageVetoBridgeDoesNotChangeEvictionOrOptionalModuleRuntimes() throws {
        let tabScriptSource = try Self.source(named: "Sumi/Models/Tab/Tab+ScriptMessageHandler.swift")
        let lifecycleSource = try Self.source(named: "Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift")
        let coordinatorSource = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")

        XCTAssertTrue(tabScriptSource.contains("SumiTabSuspensionUserScript"))
        XCTAssertTrue(tabScriptSource.contains("window.__sumiTabSuspension"))
        XCTAssertTrue(tabScriptSource.contains("featureName: \"tabSuspension\""))
        XCTAssertTrue(tabScriptSource.contains("method: \"canBeSuspended\""))
        XCTAssertTrue(tabScriptSource.contains("pageSuspensionVeto"))
        XCTAssertTrue(tabScriptSource.contains("pageReportedUnableToSuspend"))
        XCTAssertTrue(lifecycleSource.contains("navigation.navigationAction.isForMainFrame"))
        XCTAssertTrue(lifecycleSource.contains("tab.resetPageSuspensionRuntimeState()"))

        XCTAssertFalse(tabScriptSource.contains("canEvictHiddenWebView"))
        XCTAssertFalse(tabScriptSource.contains("createWebViewInternal"))
        XCTAssertFalse(coordinatorSource.contains("SumiTabSuspensionUserScript"))

        for forbiddenConstructor in [
            "SumiTrackingProtection(",
            "SumiContentBlockingService(",
            "ExtensionManager(",
            "NativeMessagingHandler(",
            "SumiScriptsManager(",
            "UserScriptStore(",
        ] {
            XCTAssertFalse(tabScriptSource.contains(forbiddenConstructor))
        }
    }

    private struct Harness {
        let browserManager: BrowserManager
        let coordinator: WebViewCoordinator
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let settings: SumiSettingsService
        let service: TabSuspensionService
        let clock: TestSuspensionClock
    }

    private final class TestSuspensionClock: SumiSuspensionClock {
        var liveUptime: TimeInterval = 0
    }

    private func makeHarness(
        memoryMode: SumiMemoryMode = .balanced,
        customDelay: TimeInterval = SumiMemorySaverCustomDelay.defaultDelay
    ) -> Harness {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        let windowRegistry = WindowRegistry()
        let defaultsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: defaultsHarness.defaults)
        settings.memoryMode = memoryMode
        settings.memorySaverCustomDeactivationDelay = customDelay
        browserManager.sumiSettings = settings
        browserManager.tabManager.sumiSettings = settings
        browserManager.webViewCoordinator = coordinator
        browserManager.windowRegistry = windowRegistry

        let space = Space(name: "Suspension")
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let clock = TestSuspensionClock()
        let service = TabSuspensionService(
            memoryMonitor: nil,
            dateProvider: { [unowned self] in self.now },
            suspensionClock: clock,
            timerSleep: { _ in
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )
        service.attach(browserManager: browserManager)

        return Harness(
            browserManager: browserManager,
            coordinator: coordinator,
            windowRegistry: windowRegistry,
            windowState: windowState,
            settings: settings,
            service: service,
            clock: clock
        )
    }

    private func makeTab(_ url: String, harness: Harness) -> Tab {
        harness.browserManager.tabManager.createNewTab(
            url: url,
            in: harness.browserManager.tabManager.currentSpace,
            activate: false
        )
    }

    private func makeShortcutPin(
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        index: Int,
        launchURL: URL,
        title: String,
        iconAsset: String?
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            folderId: nil,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }

    private func assertShortcutPin(
        _ actual: ShortcutPin,
        matches expected: ShortcutPin,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.role, expected.role, file: file, line: line)
        XCTAssertEqual(actual.profileId, expected.profileId, file: file, line: line)
        XCTAssertEqual(actual.spaceId, expected.spaceId, file: file, line: line)
        XCTAssertEqual(actual.index, expected.index, file: file, line: line)
        XCTAssertEqual(actual.folderId, expected.folderId, file: file, line: line)
        XCTAssertEqual(actual.launchURL, expected.launchURL, file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, file: file, line: line)
        XCTAssertEqual(actual.systemIconName, expected.systemIconName, file: file, line: line)
        XCTAssertEqual(actual.iconAsset, expected.iconAsset, file: file, line: line)
    }

    private func makeEligibilitySubject(
        hiddenURL: String = "https://example.com/eligible"
    ) -> (Harness, Tab) {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab(hiddenURL, harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        return (harness, hidden)
    }

    @discardableResult
    private func attachWebView(to tab: Tab, harness: Harness) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        harness.coordinator.setWebView(webView, for: tab.id, in: harness.windowState.id)
        tab.assignWebViewToWindow(webView, windowId: harness.windowState.id)
        return webView
    }

    private func setCurrentTab(_ tab: Tab, in windowState: BrowserWindowState) {
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId
        windowState.isShowingEmptyState = false
    }

    private static func source(named path: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
