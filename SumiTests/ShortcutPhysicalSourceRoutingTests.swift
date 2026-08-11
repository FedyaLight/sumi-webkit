import AppKit
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutPhysicalSourceRoutingTests: XCTestCase {
    func testDriftedLiveShortcutRoutesNewTabCommands() async throws {
        let harness = try makeHarness(role: .spacePinned)
        defer { closePublishedShells(in: harness.registry) }

        let driftedURL = URL(string: "https://drifted.example/current")!
        try await establishCommittedDocument(
            on: harness,
            at: driftedURL,
            markStartupLoadFinished: true
        )

        XCTAssertNotNil(
            try commandClickChild(
                on: harness,
                targetURL: URL(string: "https://destination.example/cmd")!
            )
        )
        openLinkFromContextMenu(
            on: harness,
            targetURL: URL(string: "https://destination.example/menu")!
        )
    }

    func testResetDriftedLiveShortcutRoutesNewTabCommands() async throws {
        let harness = try makeHarness(role: .spacePinned)
        defer { closePublishedShells(in: harness.registry) }

        try await establishCommittedDocument(
            on: harness,
            at: URL(string: "https://drifted.example/current")!,
            markStartupLoadFinished: true
        )

        XCTAssertTrue(
            harness.browser.sidebarPinCommands.resetToLaunchURL(
                harness.pin,
                in: harness.sourceWindow,
                preserveCurrentPage: false
            )
        )

        try await establishCommittedDocument(
            on: harness,
            at: harness.pin.launchURL
        )

        XCTAssertNotNil(harness.sourceTab.popupPermissionTabContext(
            for: harness.sourceWebView
        ))
        XCTAssertNotNil(
            try commandClickChild(
                on: harness,
                targetURL: URL(string: "https://destination.example/reset-cmd")!
            )
        )
        openLinkFromContextMenu(
            on: harness,
            targetURL: URL(string: "https://destination.example/reset-menu")!
        )
    }

    func testResolverRejectsMismatchedExecutionDataStore() throws {
        let harness = try makeHarness(
            role: .favorite,
            sourceDataStore: .nonPersistent()
        )
        defer { closePublishedShells(in: harness.registry) }

        XCTAssertNil(harness.resolver.resolve(harness.sourceWebView))
    }

    func testWindowLocalShortcutLeaseRejectsWrongWindowClone() throws {
        let harness = try makeHarness(role: .spacePinned)
        defer { closePublishedShells(in: harness.registry) }
        let secondWindow = BrowserWindowState()
        harness.browser.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        secondWindow.currentProfileId = harness.presentationProfile.id
        secondWindow.currentSpaceId = harness.space.id
        secondWindow.currentTabId = harness.sourceTab.id
        harness.registry.register(secondWindow)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.executionProfile.dataStore
        let wrongWindowClone = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        wrongWindowClone.owningTab = harness.sourceTab
        harness.browser.testWebViewRuntime().trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                wrongWindowClone,
                for: harness.sourceTab,
                in: secondWindow.id
            )

        XCTAssertNil(harness.resolver.resolve(wrongWindowClone))
        let exact = try XCTUnwrap(
            harness.resolver.resolve(harness.sourceWebView)
        )
        XCTAssertEqual(exact.residence, .windowShortcut(.spacePinned))
        XCTAssertIdentical(exact.window, harness.sourceWindow)
    }

    func testFavoriteAndSpacePinnedRoutesPreserveExecutionPartition()
        throws {
        for role in [ShortcutPinRole.favorite, .spacePinned] {
            let harness = try makeHarness(role: role)
            defer { closePublishedShells(in: harness.registry) }
            let receipt = try XCTUnwrap(
                harness.resolver.resolve(harness.sourceWebView)
            )
            XCTAssertEqual(receipt.residence, .windowShortcut(role))
            XCTAssertIdentical(receipt.presentationSpace, harness.space)
            XCTAssertIdentical(
                receipt.presentationProfile,
                harness.presentationProfile
            )
            XCTAssertIdentical(
                receipt.executionProfile,
                harness.executionProfile
            )

            let tabURL = try XCTUnwrap(URL(
                string: "https://\(role.rawValue).example/link-tab"
            ))
            XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
                tabURL,
                from: harness.sourceWebView,
                disposition: .newTab(selected: false)
            ))
            let linkTab = try XCTUnwrap(
                harness.browser.regularTabCollectionOwner
                    .tabs(in: harness.space)
                    .first(where: { $0.url == tabURL })
            )
            XCTAssertEqual(linkTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(linkTab.spaceId, harness.space.id)

            let existingWindowIDs = Set(harness.registry.windows.keys)
            let windowURL = try XCTUnwrap(URL(
                string: "https://\(role.rawValue).example/link-window"
            ))
            XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
                windowURL,
                from: harness.sourceWebView,
                disposition: .newWindow(selected: false)
            ))
            let childWindow = try XCTUnwrap(
                harness.registry.allWindows.first(where: {
                    existingWindowIDs.contains($0.id) == false
                })
            )
            let childTabID = try XCTUnwrap(childWindow.currentTabId)
            let windowTab = try XCTUnwrap(
                harness.browser.tabCollectionMembershipOwner
                    .tab(for: childTabID)
            )
            XCTAssertEqual(childWindow.currentProfileId, harness.presentationProfile.id)
            XCTAssertEqual(childWindow.currentSpaceId, harness.space.id)
            XCTAssertEqual(windowTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(windowTab.spaceId, harness.space.id)

            let popupConfiguration = WKWebViewConfiguration()
            popupConfiguration.websiteDataStore =
                harness.executionProfile.dataStore
            let popup = try XCTUnwrap(
                harness.sourceTab.navigationRuntime.webKitChildTabOpening?
                    .open(
                        configuration: popupConfiguration,
                        requestURL: URL(
                            string: "https://\(role.rawValue).example/popup"
                        ),
                        from: harness.sourceWebView,
                        selected: false,
                        isExtensionOriginated: false
                    ) as? FocusableWKWebView
            )
            let popupTab = try XCTUnwrap(popup.owningTab)
            XCTAssertEqual(popupTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(popupTab.spaceId, harness.space.id)
            XCTAssertIdentical(
                popup.configuration.websiteDataStore,
                harness.executionProfile.dataStore
            )
        }
    }

    func testExtensionWebKitChildWindowRejectsCrossProfileSourceBeforeMutation()
        throws {
        let harness = try makeHarness(role: .favorite)
        defer { closePublishedShells(in: harness.registry) }
        let existingWindowIDs = Set(harness.registry.windows.keys)
        let existingTabIDs = Set(
            harness.browser.tabStateStore.regularTabs
                .allTabsSnapshot().map(\.id)
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.executionProfile.dataStore

        let childWebView = harness.sourceTab.navigationRuntime
            .webKitChildWindowOpening?.open(
                configuration: configuration,
                requestURL: URL(
                    string: "https://extension.example/cross-profile"
                ),
                from: harness.sourceWebView,
                activate: true,
                isExtensionOriginated: true
            )

        XCTAssertNil(childWebView)
        XCTAssertEqual(Set(harness.registry.windows.keys), existingWindowIDs)
        XCTAssertEqual(
            Set(
                harness.browser.tabStateStore.regularTabs
                    .allTabsSnapshot().map(\.id)
            ),
            existingTabIDs
        )
        XCTAssertEqual(
            harness.sourceWindow.currentTabId,
            harness.sourceTab.id
        )
    }

    private func makeHarness(
        role: ShortcutPinRole,
        sourceDataStore: WKWebsiteDataStore? = nil
    ) throws -> Harness {
        let registry = WindowRegistry()
        let browser = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                database: try SumiDatabase.inMemory()
            )
        )
        let settings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let presentationProfile = Profile(name: "Presentation")
        let executionProfile = Profile(name: "Execution")
        let space = Space(
            name: "Presentation Space",
            profileId: presentationProfile.id
        )
        let sourceWindow = BrowserWindowState()

        browser.sumiSettings = settings
        browser.profileManager.profiles = [
            presentationProfile,
            executionProfile,
        ]
        browser.currentProfile = presentationProfile
        browser.windowShellContentViewFactory = { _, _ in NSView() }
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)
        browser.tabResidenceAuthority.establishResidenceSession(on: sourceWindow)
        sourceWindow.currentProfileId = presentationProfile.id
        sourceWindow.currentSpaceId = space.id
        registry.register(sourceWindow)
        registry.setActive(sourceWindow)
        installRegistrationRestoration(from: browser, on: registry)

        let pin = ShortcutPin(
            id: UUID(),
            role: role,
            profileId: role == .favorite ? presentationProfile.id : nil,
            executionProfileId: executionProfile.id,
            spaceId: role == .spacePinned ? space.id : nil,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let canonicalPin = try XCTUnwrap(
            browser.shortcutPinStoreOwner.insert(pin, at: 0)
        )
        let sourceTab = browser.shortcutTabMaterializer.materialize(
            canonicalPin,
            in: sourceWindow.id,
            currentSpaceId: space.id
        )!
        sourceWindow.currentTabId = sourceTab.id

        let sourceWebView: FocusableWKWebView
        if let sourceDataStore {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = sourceDataStore
            sourceWebView = FocusableWKWebView(
                frame: .zero,
                configuration: configuration
            )
            sourceWebView.owningTab = sourceTab
            browser.testWebViewRuntime().trackedWebViewAdmission
                .registerAuxiliaryTrackedWebView(
                    sourceWebView,
                    for: sourceTab,
                    in: sourceWindow.id
                )
        } else {
            sourceWebView = try XCTUnwrap(
                sourceTab.makeNormalTabWebView(
                    reason: "ShortcutPhysicalSourceRoutingTests.makeHarness"
                ) as? FocusableWKWebView
            )
            let assignment = browser.testWebViewRuntime()
                .trackedWebViewAdmission.attemptAssignment(
                    sourceWebView,
                    to: sourceTab,
                    in: sourceWindow.id,
                    replaySemanticOperation: {
                        XCTFail("Unexpected WebView deferral")
                    }
                )
            XCTAssertTrue(assignment.isAccepted)
        }
        let resolver = PhysicalWebViewSourceResolver(
            ownership: browser.testWebViewRuntime().ownershipQuery,
            sourceContexts: BrowserWindowSourceContextResolver(
                spaces: browser.spaceStateOwner,
                regularTabs: browser.regularTabCollectionOwner,
                shortcutTabs: browser.liveShortcutTabs
            ),
            pins: browser.shortcutPinCollectionStateOwner,
            shortcutResolution: browser.shortcutPinRuntimeResolutionOwner,
            profiles: browser.profileManager,
            registry: { [weak registry] in registry }
        )
        XCTAssertTrue(sourceTab.hasBrowserRuntime)
        return Harness(
            browser: browser,
            settings: settings,
            registry: registry,
            sourceWindow: sourceWindow,
            presentationProfile: presentationProfile,
            executionProfile: executionProfile,
            space: space,
            pin: canonicalPin,
            sourceTab: sourceTab,
            sourceWebView: sourceWebView,
            resolver: resolver
        )
    }

    private func installRegistrationRestoration(
        from browser: BrowserManager,
        on registry: WindowRegistry
    ) {
        let restoration = browser.windowSessionBundle.restoration
        installWindowRegistryTestEventSink(
            on: registry,
            prepareWindowRegistration: { [weak restoration] window in
                restoration?.prepareRegistration(window)
            },
            publishWindowRegistration: { [weak restoration] window in
                restoration?.commitRegistration(window)
            }
        )
    }

    private func establishCommittedDocument(
        on harness: Harness,
        at url: URL,
        markStartupLoadFinished: Bool = false
    ) async throws {
        await loadDocument(on: harness.sourceWebView, at: url)
        harness.browser.selectTab(harness.sourceTab, in: harness.sourceWindow)
        if markStartupLoadFinished {
            harness.browser.startupRestoreLifecycle.markLoadFinished()
        }
        harness.sourceTab.installNavigationDelegate(on: harness.sourceWebView)
        bindCommittedDocument(
            on: harness.sourceWebView,
            tab: harness.sourceTab,
            committedURL: try XCTUnwrap(harness.sourceWebView.committedURL)
        )
    }

    private func commandClickChild(
        on harness: Harness,
        targetURL: URL
    ) throws -> WKWebView? {
        harness.sourceWebView.gestures.record(
            mouseEvent(modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        let responder = SumiPopupHandlingNavigationResponder(
            tab: harness.sourceTab,
            permissions: harness.sourceTab.navigationRuntime.popupPermissionEvaluator,
            extensionRequests: harness.sourceTab.navigationRuntime.extensionPopupRequestConsumer,
            extensionTabs: harness.sourceTab.navigationRuntime.extensionExternalTabOpening,
            webPopups: harness.sourceTab.navigationRuntime.physicalWebPopupOpening,
            automaticGlance: harness.sourceTab.navigationRuntime.automaticGlanceOpening,
            childTabs: harness.sourceTab.navigationRuntime.webKitChildTabOpening,
            childWindows: harness.sourceTab.navigationRuntime.webKitChildWindowOpening
        )
        let sourceURL = try XCTUnwrap(
            harness.sourceWebView.committedURL ?? harness.sourceTab.url
        )
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: true,
            request: URLRequest(url: sourceURL),
            securityOrigin: SumiWKSecurityOriginMock.new(url: sourceURL),
            webView: harness.sourceWebView
        ).frameInfo
        let actionMock = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        )
        actionMock.isUserInitiated = true
        actionMock.modifierFlags = [.command]
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.executionProfile.dataStore
        return responder.createWebView(
            from: harness.sourceWebView,
            with: configuration,
            for: actionMock.navigationAction,
            windowFeatures: WKWindowFeatures()
        )
    }

    private func openLinkFromContextMenu(
        on harness: Harness,
        targetURL: URL
    ) {
        let initialTabCount = harness.browser.tabStateStore.regularTabs
            .allTabsSnapshot().count
        let owner = SumiWebPageMenuActionOwner()
        owner.prepare(
            webView: harness.sourceWebView,
            context: SumiWebPageMenuContext(
                menu: NSMenu(),
                snapshot: SumiWebPageContextMenuTargetSnapshot(
                    kind: .link,
                    linkHref: targetURL.absoluteString
                ),
                searchProviderName: "DuckDuckGo",
                isLoading: false,
                isDeveloperInspectionEnabled: false
            )
        )
        owner.openLinkInNewTab(nil)

        let regularTabs = harness.browser.tabStateStore.regularTabs
            .allTabsSnapshot()
        XCTAssertEqual(regularTabs.count, initialTabCount + 1)
        XCTAssertNotNil(regularTabs.first(where: { $0.url == targetURL }))
    }

    private func loadDocument(on webView: WKWebView, at url: URL) async {
        let loaded = expectation(description: "shortcut source document loaded")
        let delegate = ShortcutDocumentNavigationDelegate { loaded.fulfill() }
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<html><body>shortcut source</body></html>", baseURL: url)
        await fulfillment(of: [loaded], timeout: 5)
        webView.navigationDelegate = nil
    }

    private func mouseEvent(
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }

    @discardableResult
    private func bindCommittedDocument(
        on webView: WKWebView,
        tab: Tab,
        committedURL: URL
    ) -> NSObject {
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

    private func closePublishedShells(in registry: WindowRegistry) {
        for window in registry.allWindows {
            let shell = registry.appKitWindow(for: window)
            registry.unregister(window.id)
            shell?.orderOut(nil)
        }
    }
}

@MainActor
private final class ShortcutDocumentNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}

@MainActor
private struct Harness {
    let browser: BrowserManager
    let settings: SumiSettingsService
    let registry: WindowRegistry
    let sourceWindow: BrowserWindowState
    let presentationProfile: Profile
    let executionProfile: Profile
    let space: Space
    let pin: ShortcutPin
    let sourceTab: Tab
    let sourceWebView: FocusableWKWebView
    let resolver: PhysicalWebViewSourceResolver
}
