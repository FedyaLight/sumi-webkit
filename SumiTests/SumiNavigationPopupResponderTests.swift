import AppKit
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi
import SumiDomain

@MainActor
final class SumiNavigationPopupResponderTests: SumiNavigationResponderTestCase {
    func testGlanceTriggerRequiresCleanOptionModifier() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://source.example")!)
        tab.sumiSettings = settings

        XCTAssertTrue(tab.isGlanceTriggerActive([.option]))
        XCTAssertFalse(tab.isGlanceTriggerActive([]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.command]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.option, .command]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.control]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.shift]))

        settings.glanceEnabled = false
        XCTAssertFalse(tab.isGlanceTriggerActive([.option]))
    }

    func testDynamicGlanceRequiresPinnedExternalCleanClick() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.sumiSettings = settings
        let externalURL = URL(string: "https://destination.example/page")!
        let sameHostURL = URL(string: "https://source.example/other")!

        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))

        tab.isSpacePinned = true
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        tab.isSpacePinned = false

        tab.isPinned = true
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        tab.isPinned = false

        tab.shortcutPinRole = .spacePinned
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))

        tab.shortcutPinRole = .favorite
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        XCTAssertTrue(
            tab.shouldOpenDynamicallyInGlance(
                url: URL(string: "https://sub.source.example/page")!,
                modifierFlags: []
            )
        )
        XCTAssertFalse(
            tab.shouldOpenDynamicallyInGlance(
                url: URL(string: "https://source.example:8443/page")!,
                modifierFlags: []
            )
        )
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: sameHostURL, modifierFlags: []))

        tab.url = URL(string: "about:blank")!
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        tab.url = URL(string: "https://source.example/page")!

        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.command]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option, .command]))

        settings.glanceEnabled = false
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
    }

    func testGlanceTriggerUsesExactSourceWebViewGestureInsteadOfAnotherViewState() throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(
            url: URL(string: "https://source.example/page")!
        )
        tab.sumiSettings = settings
        let staleWebView = FocusableWKWebView()
        let sourceWebView = FocusableWKWebView()

        staleWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )

        XCTAssertFalse(tab.isGlanceTriggerActive(
            staleWebView.gestures.resolvedModifierFlags(actionFlags: [])
        ))
        XCTAssertTrue(tab.isGlanceTriggerActive(
            sourceWebView.gestures.resolvedModifierFlags(actionFlags: [])
        ))
    }

    func testFreshNativeMouseDownWinsOverStaleWebKitModifierFlags() {
        let sourceWebView = FocusableWKWebView()
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )

        XCTAssertEqual(
            sourceWebView.gestures.resolvedModifierFlags(actionFlags: [.command, .option]),
            [.option]
        )
    }

    /// Mirrors post-`createWebView` / `decidePolicy` cleanup so Cmd+click does not leave stale `lastWebViewInteractionEvent`.
    func testClearingModifierSnapshotAfterCmdGestureAllowsFreshGlanceResolution() {
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        let sourceWebView = FocusableWKWebView()
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )

        XCTAssertEqual(
            sourceWebView.gestures.resolvedModifierFlags(actionFlags: []),
            [.command]
        )

        sourceWebView.gestures.clear()

        XCTAssertEqual(sourceWebView.gestures.resolvedModifierFlags(actionFlags: []), [])

        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )
        let resolved = sourceWebView.gestures.resolvedModifierFlags(actionFlags: [])
        XCTAssertEqual(resolved, [.option])
        XCTAssertTrue(tab.isGlanceTriggerActive(resolved))
    }

    func testPopupUserActivationCannotCrossCloneBoundary() {
        let activatedSource = FocusableWKWebView()
        let siblingClone = FocusableWKWebView()
        activatedSource.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "leftMouseDown"
        )

        XCTAssertTrue(
            activatedSource.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
        XCTAssertFalse(
            siblingClone.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
    }

    func testPopupActivationConsumptionDoesNotConsumeSiblingClone() {
        let sourceWebView = FocusableWKWebView()
        let siblingClone = FocusableWKWebView()
        let event = makeMouseEvent(type: .leftMouseDown, modifierFlags: [])
        sourceWebView.popupUserActivation.record(event: event, kind: "leftMouseDown")
        siblingClone.popupUserActivation.record(event: event, kind: "leftMouseDown")

        let sourceActivation = sourceWebView.popupUserActivation.evaluate(
            webKitUserInitiated: false
        )
        sourceWebView.popupUserActivation.consume(sourceActivation)

        XCTAssertFalse(
            sourceWebView.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
        XCTAssertTrue(
            siblingClone.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
    }

    func testConsumingPopupActivationEvaluationAfterNewRecordPreservesNewActivation() {
        let sourceWebView = FocusableWKWebView()
        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "firstGesture"
        )
        let firstEvaluation = sourceWebView.popupUserActivation.evaluate(
            webKitUserInitiated: false
        )
        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "secondGesture"
        )

        sourceWebView.popupUserActivation.consume(firstEvaluation)

        let remainingState = sourceWebView.popupUserActivation.activationState(
            webKitUserInitiated: false
        )
        guard case .recentBrowserEvent(let kind, _, _) = remainingState else {
            return XCTFail("Expected the newer browser activation to remain")
        }
        XCTAssertEqual(kind, "secondGesture")
    }

    func testDirectWebKitEvaluationConsumesOnlyItsSnapshottedBrowserActivation() {
        let sourceWebView = FocusableWKWebView()
        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "firstGesture"
        )
        let directWebKitEvaluation = sourceWebView.popupUserActivation.evaluate(
            webKitUserInitiated: true
        )
        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "secondGesture"
        )

        sourceWebView.popupUserActivation.consume(directWebKitEvaluation)

        let secondState = sourceWebView.popupUserActivation.activationState(
            webKitUserInitiated: false
        )
        guard case .recentBrowserEvent(let kind, _, _) = secondState else {
            return XCTFail("Direct WebKit evaluation must preserve a newer browser gesture")
        }
        XCTAssertEqual(kind, "secondGesture")

        let currentDirectEvaluation = sourceWebView.popupUserActivation.evaluate(
            webKitUserInitiated: true
        )
        sourceWebView.popupUserActivation.consume(currentDirectEvaluation)
        XCTAssertFalse(
            sourceWebView.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
    }

    func testModifierResolutionAndClearDoNotCrossCloneBoundary() {
        let sourceWebView = FocusableWKWebView()
        let siblingClone = FocusableWKWebView()
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        siblingClone.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )

        sourceWebView.gestures.clear()

        XCTAssertEqual(sourceWebView.gestures.resolvedModifierFlags(actionFlags: []), [])
        XCTAssertEqual(
            siblingClone.gestures.resolvedModifierFlags(actionFlags: []),
            [.option]
        )
    }

    func testStaleGestureClearReceiptPreservesNewerGesture() {
        let sourceWebView = FocusableWKWebView()
        let firstReceipt = sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        _ = sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )

        sourceWebView.gestures.clear(ifCurrent: firstReceipt)

        XCTAssertEqual(
            sourceWebView.gestures.resolvedModifierFlags(actionFlags: []),
            [.option]
        )
    }

    func testPopupActivationClaimCannotBeSpentTwiceByConcurrentRequests() {
        let sourceWebView = FocusableWKWebView()
        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "mouseDown"
        )

        let firstClaim = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: false
        )
        let secondClaim = sourceWebView.popupUserActivation.claim(
            webKitUserInitiated: true
        )

        XCTAssertTrue(firstClaim.isUserActivated)
        XCTAssertEqual(secondClaim, .none)

        sourceWebView.popupUserActivation.record(
            event: makeMouseEvent(type: .leftMouseDown, modifierFlags: []),
            kind: "mouseDown"
        )
        XCTAssertTrue(
            sourceWebView.popupUserActivation
                .claim(webKitUserInitiated: true)
                .isUserActivated
        )
    }

    func testPopupResponderOptionClickRoutesToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true,
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(
            harness.browserManager.glanceManager.currentSession?.currentURL,
            targetURL
        )
    }

    func testPopupResponderFavoriteExternalCleanClickRoutesToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceTab.shortcutPinRole = .favorite
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(
            harness.browserManager.glanceManager.currentSession?.currentURL,
            targetURL
        )
    }

    func testPopupResponderSpacePinnedExternalCleanClickRoutesToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceTab.shortcutPinRole = .spacePinned
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(
            harness.browserManager.glanceManager.currentSession?.currentURL,
            targetURL
        )
    }

    func testPopupResponderSpacePinnedSameHostCleanClickStaysInCurrentTab() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceTab.shortcutPinRole = .spacePinned
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://source.example/internal")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
    }

    func testPopupResponderSpacePinnedExternalClickOpensSelectedTabWhenGlanceDisabled()
        async throws {
        let harness = try await makePopupFocusHarness()
        let settings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        harness.browserManager.sumiSettings = settings
        harness.sourceTab.sumiSettings = settings
        settings.glanceEnabled = false
        harness.sourceTab.shortcutPinRole = .spacePinned
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
        let regularTabs = harness.browserManager.tabStateStore.regularTabs
            .allTabsSnapshot()
        XCTAssertEqual(regularTabs.count, initialRegularTabCount + 1)
        let openedTab = try XCTUnwrap(
            regularTabs.first(where: { $0.url == targetURL })
        )
        XCTAssertEqual(harness.windowState.currentTabId, openedTab.id)
    }

    func testPopupResponderRegularExternalCleanClickDoesNotRouteToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
    }

    func testPopupResponderCommandClickDoesNotRouteToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
        let regularTabs = harness.browserManager.tabStateStore.regularTabs
            .allTabsSnapshot()
        XCTAssertEqual(regularTabs.count, initialRegularTabCount + 1)
        let openedTab = try XCTUnwrap(regularTabs.first(where: { $0.url == targetURL }))
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertNotEqual(harness.windowState.currentTabId, openedTab.id)
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [.command],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: true
            ),
            .newTab(selected: false)
        )
    }

    func testPopupResponderCommandClickDoesNotCancelWhenPhysicalOpenFails()
        async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        // Make the physical source unresolvable after the document lease has
        // been established. The browser must not turn that failed browser
        // command into a swallowed page navigation.
        harness.windowState.currentSpaceId = nil
        let responder = popupResponder(for: harness.sourceTab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: harness.sourceWebView,
                sourceURL: harness.sourceTab.url
            ),
            preferences: &preferences
        )

        XCTAssertFalse(policy?.isCancel == true)
    }

    func testPopupResponderRejectsNonFocusableSourceEvenWithCommittedDocumentLease() async {
        let profile = Profile(name: "Popup Runtime")
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profileId in
                profileId == profile.id ? profile : nil
            },
            spaceProfile: { _ in nil },
            currentProfile: { nil },
            firstProfile: { nil }
        )
        let permissions = PopupPermissionEvaluatorSpy()
        var runtime = TabBrowserRuntime.inactive
        runtime.popupPermissionEvaluator = permissions
        tab.attachBrowserRuntime(runtime)
        let responder = popupResponder(for: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = PopupCommittedURLWebView(frame: .zero)
        let targetURL = URL(string: "https://destination.example/page")!
        let sourceNavigation = bindCommittedPopupDocument(
            on: webView,
            tab: tab,
            committedURL: tab.url
        )
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: tab.url,
                modifierFlags: [.command]
            ),
            preferences: &preferences
        )

        XCTAssertTrue(tab.hasBrowserRuntime)
        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertTrue(permissions.contexts.isEmpty)
        withExtendedLifetime(sourceNavigation) { /* Keep the exact document participant alive. */ }
    }

    func testPopupCreateWebViewFocusesCleanClickNewTab() async throws {
        let harness = try await makePopupFocusHarness()
        let responder = popupResponder(for: harness.sourceTab)
        let configuration = popupConfiguration(for: harness)
        let markerScript = WKUserScript(
            source: "window.__sumiPopupConfigurationMarker = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(markerScript)
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: URL(string: "https://destination.example/page")!,
            webView: harness.sourceWebView
        )

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: configuration,
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(
            childWebView?.configuration.userContentController.userScripts
                .contains(where: { $0.source == markerScript.source }),
            true
        )
        XCTAssertNotEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(
            harness.windowState.currentTabId,
            harness.browserManager.tabStateStore.regularTabs.allTabsSnapshot().last?.id
        )
        let childTab = harness.browserManager.tabStateStore.regularTabs.allTabsSnapshot().last
        XCTAssertIdentical(childTab?.resolvedCurrentWebView(), childWebView)
        XCTAssertNil(childTab?.webViewConfigurationOverride)
    }

    func testGlanceCleanPopupLinkNavigatesInsidePreview() async throws {
        let harness = try await makePopupFocusHarness()
        let glance = try await makeGlancePopupSource(from: harness)
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let targetURL = URL(string: "https://destination.example/inside-glance")!

        let childWebView = popupResponder(for: glance.tab).createWebView(
            from: glance.webView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: glance.webView.committedURL,
                targetURL: targetURL,
                webView: glance.webView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().count,
            initialRegularTabCount
        )
        for _ in 0..<100 where glance.session.currentURL != targetURL {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(glance.session.currentURL, targetURL)
        XCTAssertIdentical(
            harness.browserManager.glanceManager.currentSession,
            glance.session
        )
    }

    func testGlanceCommandPopupLinkStillOpensBackgroundTab() async throws {
        let harness = try await makePopupFocusHarness()
        let glance = try await makeGlancePopupSource(from: harness)
        glance.webView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let targetURL = URL(string: "https://destination.example/new-tab")!
        XCTAssertTrue(
            glance.tab.linkPresentationCommands.activateSource(
                of: glance.webView
            )
        )

        let childWebView = popupResponder(for: glance.tab).createWebView(
            from: glance.webView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: glance.webView.committedURL,
                targetURL: targetURL,
                webView: glance.webView,
                modifierFlags: [.command]
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().count,
            initialRegularTabCount + 1
        )
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertIdentical(
            harness.browserManager.glanceManager.currentSession,
            glance.session
        )
    }

    func testPopupCreateWebViewSpacePinnedExternalCleanClickRoutesToGlance() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceTab.shortcutPinRole = .spacePinned
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let responder = popupResponder(for: harness.sourceTab)
        let targetURL = URL(string: "https://destination.example/page")!

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: harness.sourceTab.url,
                targetURL: targetURL,
                webView: harness.sourceWebView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().count,
            initialRegularTabCount
        )
        XCTAssertEqual(
            harness.browserManager.glanceManager.currentSession?.currentURL,
            targetURL
        )
    }

    func testPopupCreateWebViewSpacePinnedMiddleClickOpensBackgroundTab() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceTab.shortcutPinRole = .spacePinned
        harness.sourceWebView.gestures.record(
            makeMouseEvent(type: .otherMouseDown, modifierFlags: []),
            kind: .auxiliaryMouseDown
        )
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count
        let responder = popupResponder(for: harness.sourceTab)
        let targetURL = URL(string: "https://destination.example/page")!

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: harness.sourceTab.url,
                targetURL: targetURL,
                webView: harness.sourceWebView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNotNil(childWebView)
        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
        let regularTabs = harness.browserManager.tabStateStore.regularTabs
            .allTabsSnapshot()
        XCTAssertEqual(regularTabs.count, initialRegularTabCount + 1)
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
    }

    func testPopupChildReclassifiesCopiedNormalConfigurationAsAuxiliarySurface()
        async throws {
        let harness = try await makePopupFocusHarness()
        let normalConfiguration = harness.browserManager
            .browserConfiguration.normalTabWebViewConfiguration(
                for: harness.sourceProfile,
                url: harness.sourceTab.url
            )
        let childConfiguration = try XCTUnwrap(
            normalConfiguration.copy() as? WKWebViewConfiguration
        )
        XCTAssertTrue(childConfiguration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertIdentical(
            childConfiguration.userContentController,
            normalConfiguration.userContentController
        )
        let responder = popupResponder(for: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: URL(string: "https://destination.example/copied-config")!,
            webView: harness.sourceWebView
        )

        let childWebView = try XCTUnwrap(
            responder.createWebView(
                from: harness.sourceWebView,
                with: childConfiguration,
                for: action,
                windowFeatures: WKWindowFeatures()
            )
        )

        XCTAssertFalse(
            childConfiguration.sumiIsNormalTabWebViewConfiguration,
            "The WebKit child configuration belongs to the auxiliary generation after materialization"
        )
        XCTAssertFalse(
            childWebView.configuration.sumiIsNormalTabWebViewConfiguration,
            "The materialized child is an auxiliary surface despite its inherited controller"
        )
        XCTAssertIdentical(
            childWebView.configuration.userContentController,
            childConfiguration.userContentController
        )
        XCTAssertEqual(
            harness.browserManager.testWebViewRuntime().ownershipQuery
                .trackedOwner(containing: childWebView)?.tabID,
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().last?.id
        )
    }

    func testPopupCreateWebViewRejectsDocumentChangedDuringSynchronousPermission()
        async throws {
        let harness = try await makePopupFocusHarness()
        let permissions = PopupPermissionEvaluatorSpy()
        let childTabs = WebKitChildTabOpeningSpy()
        permissions.onSynchronousEvaluation = {
            _ = harness.sourceTab.beginMainFrameNavigationIntent(
                to: URL(string: "https://source.example/replaced")!
            )
        }
        let responder = popupResponder(
            for: harness.sourceTab,
            permissions: permissions,
            childTabs: childTabs
        )

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: harness.sourceTab.url,
                targetURL: URL(string: "https://destination.example/page")!,
                webView: harness.sourceWebView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(permissions.requests.count, 1)
        XCTAssertEqual(childTabs.openCount, 0)
    }

    func testPopupCreateWebViewRejectsDocumentChangedDuringAsyncPermission()
        async throws {
        let harness = try await makePopupFocusHarness()
        let permissions = PopupPermissionEvaluatorSpy()
        let childTabs = WebKitChildTabOpeningSpy()
        permissions.onAsyncEvaluation = {
            _ = harness.sourceTab.beginMainFrameNavigationIntent(
                to: URL(string: "https://source.example/replaced")!
            )
        }
        let responder = popupResponder(
            for: harness.sourceTab,
            permissions: permissions,
            childTabs: childTabs
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: popupNavigationAction(
                sourceURL: harness.sourceTab.url,
                targetURL: URL(string: "https://destination.example/page")!,
                webView: harness.sourceWebView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(permissions.requests.count, 1)
        XCTAssertEqual(childTabs.openCount, 0)
    }

    func testPopupCreateWebViewRejectsMismatchedDataStoreBeforePermission()
        async throws {
        let harness = try await makePopupFocusHarness()
        let permissions = PopupPermissionEvaluatorSpy()
        let childTabs = WebKitChildTabOpeningSpy()
        let responder = popupResponder(
            for: harness.sourceTab,
            permissions: permissions,
            childTabs: childTabs
        )
        let mismatchedConfiguration = WKWebViewConfiguration()
        mismatchedConfiguration.websiteDataStore = Profile(
            name: "Other Popup Partition"
        ).dataStore

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: mismatchedConfiguration,
            for: popupNavigationAction(
                sourceURL: harness.sourceTab.url,
                targetURL: URL(string: "https://destination.example/page")!,
                webView: harness.sourceWebView
            ),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertEqual(childTabs.openCount, 0)
    }

    func testChildSurfaceRouterReturnsExactWindowChildAndWebKitConfiguration() {
        let sourceWebView = FocusableWKWebView()
        let configuration = WKWebViewConfiguration()
        let expectedChild = WKWebView()
        let childWindows = WebKitChildWindowOpeningSpy(
            returning: expectedChild
        )
        let targetURL = URL(string: "https://destination.example/window")!
        let router = WebKitChildSurfaceRouter(
            extensionTabs: nil,
            webPopups: nil,
            childTabs: nil,
            childWindows: childWindows
        )

        let returnedChild = router.open(
            WebKitChildSurfaceRouter.Request(
                configuration: configuration,
                navigationRequest: URLRequest(url: targetURL),
                windowFeatures: WKWindowFeatures(),
                sourceWebView: sourceWebView,
                sourceURL: URL(string: "https://source.example/page"),
                policy: .window(active: false),
                isExtensionOriginated: false,
                gestureReceipt: nil
            )
        )

        XCTAssertIdentical(returnedChild, expectedChild)
        XCTAssertIdentical(childWindows.receivedConfiguration, configuration)
        XCTAssertIdentical(childWindows.receivedSourceWebView, sourceWebView)
        XCTAssertEqual(childWindows.receivedRequestURL, targetURL)
        XCTAssertEqual(childWindows.receivedActivate, false)
    }

    func testExtensionPopupExternalCreateWebViewOpensNormalBrowserTab() async throws {
        let harness = try await makePopupFocusHarness()
        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL
        let initialRegularTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
            harness.browserManager.spaceStateOwner.currentSpace!.id
        ]?.count ?? 0

        let responder = popupResponder(for: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: extensionPopupURL,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertTrue(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
                harness.browserManager.spaceStateOwner.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        let openedTab = try XCTUnwrap(harness.browserManager.tabStateStore.regularTabs.allTabsSnapshot().last)
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertFalse(openedTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertNil(openedTab.webViewConfigurationOverride)
        XCTAssertEqual(harness.windowState.currentTabId, openedTab.id)
        XCTAssertNotNil(openedTab.resolvedAssignedWebView() ?? openedTab.resolvedCurrentWebView())
    }

    func testExtensionPopupExternalCreateWebViewRejectsMissingSourceResidence()
        async throws {
        let harness = try await makePopupFocusHarness()
        let secondarySpace = Space(
            name: "Secondary",
            profileId: harness.sourceSpace.profileId
        )
        harness.browserManager.spaceStateOwner.append(secondarySpace)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)
        harness.sourceTab.spaceId = nil

        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL
        let initialWindowSpaceTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
            harness.sourceSpace.id
        ]?.count ?? 0
        let initialGlobalSpaceTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
            secondarySpace.id
        ]?.count ?? 0

        let responder = popupResponder(for: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: extensionPopupURL,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[harness.sourceSpace.id]?.count,
            initialWindowSpaceTabCount
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[secondarySpace.id]?.count ?? 0,
            initialGlobalSpaceTabCount
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().filter { $0.url == targetURL }.count,
            0
        )
        XCTAssertEqual(
            harness.windowState.currentTabId,
            harness.sourceTab.id
        )
    }

    func testPopupOriginDoesNotBorrowLogicalTabURLWhenSourceFrameIsMissing()
        async throws {
        let harness = try await makePopupFocusHarness()
        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL
        let initialRegularTabCount = harness.browserManager.tabStateStore
            .regularTabs.allTabsSnapshot().count

        let responder = popupResponder(for: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: nil,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().count,
            initialRegularTabCount
        )
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(harness.sourceTab.url, extensionPopupURL)
        XCTAssertNotEqual(harness.sourceTab.url, targetURL)
    }

    func testPopupCreateWebViewLeavesCommandClickNewTabInBackground() async throws {
        let harness = try await makePopupFocusHarness()
        harness.sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        let responder = popupResponder(for: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: URL(string: "https://destination.example/page")!,
            webView: harness.sourceWebView,
            modifierFlags: [.command]
        )

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: popupConfiguration(for: harness),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(
            harness.sourceWebView.gestures.resolvedModifierFlags(actionFlags: []),
            []
        )
    }

    func testPolicyGeneratedCleanNewTabSelectsButCommandNewTabStaysBackground() {
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            ),
            .newTab(selected: true)
        )
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [.command],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            ),
            .newTab(selected: false)
        )
    }

    private func makePopupBrowserManager(
        windowRegistry: WindowRegistry
    ) throws -> BrowserManager {
        let moduleRegistry = makePopupModuleRegistry()
        moduleRegistry.setEnabled(false, for: .extensions)
        return BrowserManager(
            windowRegistry: windowRegistry,
            moduleRegistry: moduleRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try Self.makeInMemoryStartupContainer()
            ),
            automaticallyStartPersistedStateLoad: false
        )
    }

    private func popupResponder(
        for tab: Tab
    ) -> SumiPopupHandlingNavigationResponder {
        SumiPopupHandlingNavigationResponder(
            tab: tab,
            permissions: tab.navigationRuntime.popupPermissionEvaluator,
            extensionRequests:
                tab.navigationRuntime.extensionPopupRequestConsumer,
            extensionTabs: tab.navigationRuntime.extensionExternalTabOpening,
            webPopups: tab.navigationRuntime.physicalWebPopupOpening,
            childTabs: tab.navigationRuntime.webKitChildTabOpening,
            childWindows: tab.navigationRuntime.webKitChildWindowOpening
        )
    }

    private func popupResponder(
        for tab: Tab,
        permissions: any PopupPermissionEvaluating,
        childTabs: any WebKitChildTabOpening
    ) -> SumiPopupHandlingNavigationResponder {
        SumiPopupHandlingNavigationResponder(
            tab: tab,
            permissions: permissions,
            extensionRequests: nil,
            extensionTabs: nil,
            webPopups: nil,
            childTabs: childTabs,
            childWindows: nil
        )
    }

    private func makePopupModuleRegistry() -> SumiModuleRegistry {
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: userDefaults)
        )
    }

    private static func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    private struct PopupFocusHarness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let sourceSpace: Space
        let sourceProfile: Profile
        let sourceTab: Tab
        let sourceWebView: FocusableWKWebView
        let sourceNavigation: NSObject
    }

    private func makePopupFocusHarness() async throws -> PopupFocusHarness {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let windowRegistry = WindowRegistry()
        let browserManager = try makePopupBrowserManager(
            windowRegistry: windowRegistry
        )
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.sumiSettings = settings
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: false
        )
        _ = WindowTabSelectionStateApplicator.apply(
            sourceTab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        let sourceWebView = try XCTUnwrap(
            sourceTab.makeNormalTabWebView(
                reason: "SumiNavigationPopupResponderTests.makePopupFocusHarness"
            ) as? FocusableWKWebView
        )
        let assignment = browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.attemptAssignment(
            sourceWebView,
            to: sourceTab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        XCTAssertTrue(assignment.isAccepted)
        await loadPopupDocument(on: sourceWebView, at: sourceTab.url)
        let committedURL = try XCTUnwrap(sourceWebView.committedURL)
        let sourceNavigation = bindCommittedPopupDocument(
            on: sourceWebView,
            tab: sourceTab,
            committedURL: committedURL
        )
        browserManager.selectTab(sourceTab, in: windowState)
        browserManager.startupRestoreLifecycle.markLoadFinished()
        XCTAssertNotNil(
            sourceTab.committedDocumentRuntime.lease(for: sourceWebView)
        )
        XCTAssertNotNil(sourceTab.popupPermissionTabContext(for: sourceWebView))

        return PopupFocusHarness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            sourceSpace: space,
            sourceProfile: profile,
            sourceTab: sourceTab,
            sourceWebView: sourceWebView,
            sourceNavigation: sourceNavigation
        )
    }

    private func popupConfiguration(
        for harness: PopupFocusHarness
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.sourceProfile.dataStore
        return configuration
    }

    private func makeGlancePopupSource(
        from harness: PopupFocusHarness
    ) async throws -> (
        session: GlanceSession,
        tab: Tab,
        webView: FocusableWKWebView
    ) {
        let didPresent = harness.browserManager.glanceManager.presentExternalURL(
            URL(string: "about:blank")!,
            from: harness.sourceTab,
            in: harness.windowState
        )
        XCTAssertTrue(didPresent)
        let session = try XCTUnwrap(
            harness.browserManager.glanceManager.currentSession
        )

        for _ in 0..<300 {
            if let webView = session.previewTab.resolvedCurrentWebView()
                as? FocusableWKWebView,
               session.previewTab.committedDocumentRuntime.lease(
                   for: webView
               ) != nil {
                let documentURL = URL(string: "https://glance.example/page")!
                webView.loadHTMLString(
                    "<html><body>glance source</body></html>",
                    baseURL: documentURL
                )
                for _ in 0..<300 {
                    if session.previewTab.committedDocumentRuntime.lease(
                        for: webView
                    )?.committedURL == documentURL {
                        return (session, session.previewTab, webView)
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Glance preview did not publish a committed WebView")
        throw CocoaError(.coderReadCorrupt)
    }

    private func loadPopupDocument(
        on webView: WKWebView,
        at url: URL
    ) async {
        let didFinish = expectation(description: "popup source document loaded")
        let delegate = PopupDocumentNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<html><body>popup source</body></html>", baseURL: url)
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
    }

    @discardableResult
    private func bindCommittedPopupDocument(
        on webView: WKWebView,
        tab: Tab,
        committedURL: URL
    ) -> NSObject {
        (webView as? PopupCommittedURLWebView)?.reportedCommittedURL = committedURL
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: intent.revision,
                targetURL: committedURL
            ),
            .claimed
        )
        let navigation = NSObject()
        XCTAssertTrue(
            tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                matching: nil
            )
        )
        let context = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: committedURL,
            isCurrent: nil,
            isCommitted: true,
            isMainFrame: true,
            webView: webView
        )
        tab.makeMainFrameLifecycleResponder().navigationDidCommit(context)
        return navigation
    }

    private func popupNavigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            SumiWKFrameInfoMock(
                isMainFrame: true,
                request: URLRequest(url: $0),
                securityOrigin: SumiWKSecurityOriginMock.new(url: $0),
                webView: webView
            ).frameInfo
        }
        let mock = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        )
        mock.isUserInitiated = true
        mock.modifierFlags = modifierFlags
        return mock.navigationAction
    }

    func testInternalSurfaceResponderCancelsRemoteWebNavigationToSumiSurface() async {
        let responder = SumiInternalSurfaceNavigationResponder()
        var preferences = sumiNavigationPreferences()
        let action = SumiNavigationAction(navigationAction(
            url: URL(string: "sumi://history?range=all")!,
            navigationType: .other,
            sourceURL: URL(string: "https://evil.example/page")!,
            isUserInitiated: false,
            isMainFrame: true,
            targetFrameIsMainFrame: true
        ))

        let policy = await responder.decidePolicy(for: action, preferences: &preferences)

        XCTAssertEqual(policy, .cancel)
    }

    func testInternalSurfaceResponderAllowsUserEnteredSumiSurface() async {
        let responder = SumiInternalSurfaceNavigationResponder()
        var preferences = sumiNavigationPreferences()
        let action = SumiNavigationAction(navigationAction(
            url: URL(string: "sumi://history?range=all")!,
            navigationType: .custom(.sumiUserEnteredURL),
            sourceURL: URL(string: "about:blank")!,
            isUserInitiated: true,
            isMainFrame: true,
            targetFrameIsMainFrame: true
        ))

        let policy = await responder.decidePolicy(for: action, preferences: &preferences)

        XCTAssertNil(policy)
    }
}

@MainActor
private final class PopupCommittedURLWebView: WKWebView {
    var reportedCommittedURL: URL?

    override func responds(to aSelector: ObjectiveC.Selector?) -> Bool {
        guard let aSelector else { return false }
        let selectorName = NSStringFromSelector(aSelector)
        if selectorName == "committedURL" || selectorName == "_committedURL" {
            return true
        }
        return super.responds(to: aSelector)
    }

    override func value(forKey key: String) -> Any? {
        if key == "committedURL" {
            return MainActor.assumeIsolated { reportedCommittedURL }
        }
        return super.value(forKey: key)
    }
}

private final class PopupDocumentNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _: WKWebView,
        didFinish _: WKNavigation! // swiftlint:disable:this implicitly_unwrapped_optional
    ) {
        onFinish()
    }
}

@MainActor
private final class PopupPermissionEvaluatorSpy: PopupPermissionEvaluating {
    private(set) var requests: [SumiPopupPermissionRequest] = []
    private(set) var contexts: [SumiPopupPermissionTabContext] = []
    var onAsyncEvaluation: (@MainActor () -> Void)?
    var onSynchronousEvaluation: (@MainActor () -> Void)?

    func evaluate(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) async -> SumiPopupPermissionResult {
        requests.append(request)
        contexts.append(tabContext)
        onAsyncEvaluation?()
        return SumiPopupPermissionResult(action: .allow)
    }

    func evaluateSynchronouslyForWebKitFallback(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult {
        requests.append(request)
        contexts.append(tabContext)
        onSynchronousEvaluation?()
        return SumiPopupPermissionResult(action: .allow)
    }
}

@MainActor
private final class WebKitChildTabOpeningSpy: WebKitChildTabOpening {
    private(set) var openCount = 0

    func open(
        configuration _: WKWebViewConfiguration,
        requestURL _: URL?,
        from _: FocusableWKWebView,
        selected _: Bool,
        isExtensionOriginated _: Bool
    ) -> WKWebView? {
        openCount += 1
        return WKWebView()
    }
}

@MainActor
private final class WebKitChildWindowOpeningSpy: WebKitChildWindowOpening {
    private let childWebView: WKWebView
    private(set) var receivedConfiguration: WKWebViewConfiguration?
    private(set) var receivedRequestURL: URL?
    private(set) weak var receivedSourceWebView: FocusableWKWebView?
    private(set) var receivedActivate: Bool?

    init(returning childWebView: WKWebView) {
        self.childWebView = childWebView
    }

    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        activate: Bool,
        isExtensionOriginated _: Bool
    ) -> WKWebView? {
        receivedConfiguration = configuration
        receivedRequestURL = requestURL
        receivedSourceWebView = sourceWebView
        receivedActivate = activate
        return childWebView
    }
}
