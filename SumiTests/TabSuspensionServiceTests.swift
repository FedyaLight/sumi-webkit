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

    func testPinnedHiddenTabsAreNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let pinned = makeTab("https://example.com/pinned", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: pinned, harness: harness)
        attachWebView(to: eligible, harness: harness)
        pinned.isPinned = true
        pinned.lastSelectedAt = now.addingTimeInterval(-3600)
        eligible.lastSelectedAt = now.addingTimeInterval(-1800)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(pinned.isSuspended)
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

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: pinned),
            .ineligible(reason: .launcherRuntimeSuspensionDeferred)
        )
        XCTAssertNotNil(harness.browserManager.tabManager.tab(for: pinned.id))
        XCTAssertFalse(pinned.isSuspended)
    }

    func testEssentialShortcutLiveInstanceEligibilityPreservesLauncherIdentity() {
        let (harness, essential) = makeEligibilitySubject(hiddenURL: "https://example.com/essential")
        essential.isShortcutLiveInstance = true
        essential.shortcutPinRole = .essential

        XCTAssertEqual(
            harness.service.suspensionEligibility(for: essential),
            .ineligible(reason: .launcherRuntimeSuspensionDeferred)
        )
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
        XCTAssertNil(harness.coordinator.getWebViewHost(for: hidden.id, in: harness.windowState.id))
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

    func testMemoryModePoliciesRankAggression() {
        let lightweight = TabSuspensionPolicy(memoryMode: .lightweight)
        let balanced = TabSuspensionPolicy(memoryMode: .balanced)
        let performance = TabSuspensionPolicy(memoryMode: .performance)

        XCTAssertEqual(lightweight.idleThreshold, 10 * 60)
        XCTAssertEqual(balanced.idleThreshold, 30 * 60)
        XCTAssertEqual(performance.idleThreshold, 90 * 60)
        XCTAssertLessThan(lightweight.idleThreshold, balanced.idleThreshold)
        XCTAssertLessThan(balanced.idleThreshold, performance.idleThreshold)

        XCTAssertEqual(lightweight.maximumWarmHiddenWebViewCount, 0)
        XCTAssertEqual(balanced.maximumWarmHiddenWebViewCount, 2)
        XCTAssertEqual(performance.maximumWarmHiddenWebViewCount, 5)
        XCTAssertLessThan(lightweight.maximumWarmHiddenWebViewCount, balanced.maximumWarmHiddenWebViewCount)
        XCTAssertLessThan(balanced.maximumWarmHiddenWebViewCount, performance.maximumWarmHiddenWebViewCount)

        XCTAssertEqual(lightweight.evaluationInterval, 60)
        XCTAssertEqual(balanced.evaluationInterval, 120)
        XCTAssertEqual(performance.evaluationInterval, 300)
        XCTAssertLessThan(lightweight.evaluationInterval, balanced.evaluationInterval)
        XCTAssertLessThan(balanced.evaluationInterval, performance.evaluationInterval)

        XCTAssertFalse(lightweight.allowsLauncherRuntimeSuspension)
        XCTAssertFalse(balanced.allowsLauncherRuntimeSuspension)
        XCTAssertFalse(performance.allowsLauncherRuntimeSuspension)
    }

    func testIdleSuspensionPolicyDefaultsToBalancedMemoryMode() {
        let harness = makeHarness()

        XCTAssertEqual(
            harness.service.idleSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .balanced)
        )
    }

    func testIdleSuspensionReadsCurrentMemoryModeLazily() {
        let harness = makeHarness(memoryMode: .balanced)

        XCTAssertEqual(
            harness.service.idleSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .balanced)
        )

        harness.settings.memoryMode = .performance

        XCTAssertEqual(
            harness.service.idleSuspensionPolicyForTesting(),
            TabSuspensionPolicy(memoryMode: .performance)
        )
    }

    func testBalancedIdleEvaluationSuspendsEligibleHiddenTabsOutsideWarmSet() {
        let harness = makeHarness(memoryMode: .balanced)
        let selected = makeTab("https://example.com/current", harness: harness)
        let oldest = makeTab("https://example.com/oldest", harness: harness)
        let middle = makeTab("https://example.com/middle", harness: harness)
        let warmOlder = makeTab("https://example.com/warm-older", harness: harness)
        let warmNewest = makeTab("https://example.com/warm-newest", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: oldest, harness: harness)
        attachWebView(to: middle, harness: harness)
        attachWebView(to: warmOlder, harness: harness)
        attachWebView(to: warmNewest, harness: harness)
        oldest.lastSelectedAt = now.addingTimeInterval(-7200)
        middle.lastSelectedAt = now.addingTimeInterval(-6600)
        warmOlder.lastSelectedAt = now.addingTimeInterval(-5400)
        warmNewest.lastSelectedAt = now.addingTimeInterval(-4800)

        let result = harness.service.evaluateIdleSuspension()

        XCTAssertEqual(result.memoryMode, .balanced)
        XCTAssertEqual(result.candidateCount, 4)
        XCTAssertEqual(result.warmTabCount, 2)
        XCTAssertEqual(result.warmWebViewCount, 2)
        XCTAssertEqual(result.suspendedTabIDs, [oldest.id, middle.id])
        XCTAssertTrue(oldest.isSuspended)
        XCTAssertTrue(middle.isSuspended)
        XCTAssertFalse(warmOlder.isSuspended)
        XCTAssertFalse(warmNewest.isSuspended)
    }

    func testLightweightIdleEvaluationUsesShortestThresholdAndNoWarmSet() {
        let harness = makeHarness(memoryMode: .lightweight)
        let selected = makeTab("https://example.com/current", harness: harness)
        let old = makeTab("https://example.com/old", harness: harness)
        let recent = makeTab("https://example.com/recent", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: old, harness: harness)
        attachWebView(to: recent, harness: harness)
        old.lastSelectedAt = now.addingTimeInterval(-601)
        recent.lastSelectedAt = now.addingTimeInterval(-599)

        let result = harness.service.evaluateIdleSuspension()

        XCTAssertEqual(result.memoryMode, .lightweight)
        XCTAssertEqual(result.candidateCount, 2)
        XCTAssertEqual(result.warmTabCount, 0)
        XCTAssertEqual(result.suspendedTabIDs, [old.id])
        XCTAssertTrue(old.isSuspended)
        XCTAssertFalse(recent.isSuspended)
    }

    func testIdleEvaluationPreservesSelectedAndVisibleTabs() {
        let harness = makeHarness(memoryMode: .lightweight)
        let left = makeTab("https://example.com/left", harness: harness)
        let right = makeTab("https://example.com/right", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(left, in: harness.windowState)
        var splitState = harness.browserManager.splitManager.getSplitState(for: harness.windowState.id)
        splitState.isSplit = true
        splitState.leftTabId = left.id
        splitState.rightTabId = right.id
        harness.browserManager.splitManager.setSplitState(splitState, for: harness.windowState.id)

        attachWebView(to: left, harness: harness)
        attachWebView(to: right, harness: harness)
        attachWebView(to: hidden, harness: harness)
        left.lastSelectedAt = now.addingTimeInterval(-7200)
        right.lastSelectedAt = now.addingTimeInterval(-7200)
        hidden.lastSelectedAt = now.addingTimeInterval(-7200)

        let result = harness.service.evaluateIdleSuspension()

        XCTAssertEqual(result.suspendedTabIDs, [hidden.id])
        XCTAssertFalse(left.isSuspended)
        XCTAssertFalse(right.isSuspended)
        XCTAssertTrue(hidden.isSuspended)
    }

    func testIdleEvaluationRespectsPrompt05EligibilityVetoes() {
        let harness = makeHarness(memoryMode: .lightweight)
        let selected = makeTab("https://example.com/current", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)
        var vetoedTabs: [Tab] = []
        var stateOverrides: [UUID: [TabSuspensionWebViewState]] = [:]
        var alreadySuspended: Tab?

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: eligible, harness: harness)
        eligible.lastSelectedAt = now.addingTimeInterval(-7200)

        @discardableResult
        func addVetoedTab(
            _ url: String? = nil,
            attach: Bool = true,
            configure: (Tab) -> Void
        ) -> Tab {
            let tab = makeTab(
                url ?? "https://example.com/veto-\(vetoedTabs.count)",
                harness: harness
            )
            if attach {
                attachWebView(to: tab, harness: harness)
            }
            tab.lastSelectedAt = now.addingTimeInterval(-7200)
            configure(tab)
            vetoedTabs.append(tab)
            return tab
        }

        addVetoedTab { $0.loadingState = .didCommit }
        addVetoedTab { $0.applyAudioState(.unmuted(isPlayingAudio: true)) }
        addVetoedTab { $0.hasPictureInPictureVideo = true }
        addVetoedTab { $0.isDisplayingPDFDocument = true }
        addVetoedTab { $0.pageSuspensionVeto = .pageReportedUnableToSuspend }
        addVetoedTab("file:///tmp/idle-suspension.html") { _ in }
        alreadySuspended = addVetoedTab { $0.isSuspended = true }
        addVetoedTab { $0.isPopupHost = true }
        addVetoedTab(SumiSurface.emptyTabURL.absoluteString) { _ in }
        addVetoedTab { $0.isPinned = true }
        addVetoedTab {
            $0.isShortcutLiveInstance = true
            $0.shortcutPinRole = .essential
        }

        let camera = addVetoedTab { _ in }
        stateOverrides[camera.id] = [.init(isCapturingCamera: true)]
        let microphone = addVetoedTab { _ in }
        stateOverrides[microphone.id] = [.init(isCapturingMicrophone: true)]
        let fullscreen = addVetoedTab { _ in }
        stateOverrides[fullscreen.id] = [.init(isFullscreen: true)]
        let protected = addVetoedTab { _ in }
        stateOverrides[protected.id] = [.init(isProtectedFromCompositorMutation: true)]

        let result = harness.service.evaluateIdleSuspensionForTesting(
            webViewStatesByTabID: stateOverrides
        )

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        for tab in vetoedTabs where tab !== alreadySuspended {
            XCTAssertFalse(tab.isSuspended, "Vetoed tab \(tab.url.absoluteString) should remain live")
        }
        XCTAssertTrue(alreadySuspended?.isSuspended == true)
    }

    func testIdleEvaluationKeepsPinnedAndEssentialsDeferredUntilPrompt07() {
        let harness = makeHarness(memoryMode: .lightweight)
        let selected = makeTab("https://example.com/current", harness: harness)
        let pinned = makeTab("https://example.com/pinned", harness: harness)
        let essential = makeTab("https://example.com/essential", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: pinned, harness: harness)
        attachWebView(to: essential, harness: harness)
        attachWebView(to: eligible, harness: harness)
        pinned.isPinned = true
        essential.isShortcutLiveInstance = true
        essential.shortcutPinRole = .essential
        pinned.lastSelectedAt = now.addingTimeInterval(-7200)
        essential.lastSelectedAt = now.addingTimeInterval(-7200)
        eligible.lastSelectedAt = now.addingTimeInterval(-7200)

        let result = harness.service.evaluateIdleSuspension()

        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(pinned.isSuspended)
        XCTAssertFalse(essential.isSuspended)
        XCTAssertNotNil(harness.browserManager.tabManager.tab(for: pinned.id))
        XCTAssertNotNil(harness.browserManager.tabManager.tab(for: essential.id))
        XCTAssertEqual(
            harness.service.suspensionEligibility(for: pinned),
            .ineligible(reason: .launcherRuntimeSuspensionDeferred)
        )
        XCTAssertEqual(
            harness.service.suspensionEligibility(for: essential),
            .ineligible(reason: .launcherRuntimeSuspensionDeferred)
        )
    }

    func testIdleSchedulerStartAndStopAreIdempotent() {
        let service = TabSuspensionService(
            memoryMonitor: nil,
            startsIdleSchedulerOnAttach: false
        )

        XCTAssertFalse(service.isIdleSuspensionSchedulerRunningForTesting)

        service.startIdleSuspensionScheduler()
        service.startIdleSuspensionScheduler()

        XCTAssertTrue(service.isIdleSuspensionSchedulerRunningForTesting)
        XCTAssertEqual(service.idleSchedulerStartCountForTesting, 1)

        service.stopIdleSuspensionScheduler()
        service.stopIdleSuspensionScheduler()

        XCTAssertFalse(service.isIdleSuspensionSchedulerRunningForTesting)
        XCTAssertEqual(service.idleSchedulerStartCountForTesting, 1)
    }

    func testPrompt065DDGAuditDocumentationRecordsAlignmentAndSumiPolicy() throws {
        let source = try Self.source(named: "docs/sumi-performance-modular-execution-state.md")

        for requiredText in [
            "Prompt 06.5",
            "DDG uses a default minimum inactive interval of about 10 minutes",
            "memory-pressure driven",
            "not a user-facing three-mode idle policy",
            "page-level canBeSuspended veto",
            "Sumi-specific product policy",
            "Lightweight",
            "Balanced",
            "Performance",
            "page-level veto bridge status: implemented",
        ] {
            XCTAssertTrue(
                source.contains(requiredText),
                "Missing Prompt 06.5 audit text: \(requiredText)"
            )
        }
    }

    func testPrompt06WiresMemoryModeIdleSuspensionWithoutEvictionOrOptionalModuleRuntimes() throws {
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
        XCTAssertTrue(suspensionSource.contains("evaluateIdleSuspension"))
        XCTAssertTrue(suspensionSource.contains("startIdleSuspensionScheduler"))
        XCTAssertFalse(suspensionSource.contains("tabUnloadTimeoutChanged"))
        XCTAssertFalse(suspensionSource.contains("canEvictHiddenWebView"))
        XCTAssertFalse(suspensionSource.contains("createWebViewInternal"))
        XCTAssertFalse(coordinatorSource.contains("TabSuspensionPolicy"))
        XCTAssertFalse(coordinatorSource.contains("suspensionEligibility"))

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
    }

    private func makeHarness(memoryMode: SumiMemoryMode = .balanced) -> Harness {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        let windowRegistry = WindowRegistry()
        let defaultsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: defaultsHarness.defaults)
        settings.memoryMode = memoryMode
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

        let service = TabSuspensionService(
            memoryMonitor: nil,
            dateProvider: { [unowned self] in self.now },
            startsIdleSchedulerOnAttach: false
        )
        service.attach(browserManager: browserManager)

        return Harness(
            browserManager: browserManager,
            coordinator: coordinator,
            windowRegistry: windowRegistry,
            windowState: windowState,
            settings: settings,
            service: service
        )
    }

    private func makeTab(_ url: String, harness: Harness) -> Tab {
        harness.browserManager.tabManager.createNewTab(
            url: url,
            in: harness.browserManager.tabManager.currentSpace,
            activate: false
        )
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
