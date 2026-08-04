import WebKit
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class TabPermissionSurfaceTests: XCTestCase {
    func testPermissionPageIdUsesTabIdAndDocumentGeneration() {
        let tab = makeTab()

        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):0"
        )

        tab.invalidatePermissionPageForReplacement(reason: "test-webview-replacement")

        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):1"
        )
    }

    func testPermissionContextsFailClosedWithoutResolvedProfile() {
        let tab = makeTab(browserManager: nil)
        let webView = WKWebView()

        XCTAssertNil(tab.popupPermissionTabContext(for: webView))
        XCTAssertNil(tab.externalSchemePermissionTabContext(for: webView))
    }

    func testLivePermissionSurfaceUsesInjectedPermissionRuntimeWithoutBrowserManager() {
        let tab = makeTab(browserManager: nil)
        let targetURL = URL(string: "https://target.example/page")!
        let webView = WKWebView()
        var lifecycleEvents: [SumiPermissionLifecycleEvent] = []
        var glanceLookupTabIds: [UUID] = []
        var glanceLookupWebViewIds: [ObjectIdentifier] = []
        tab.navigationRuntime.permissionRuntime = TabPermissionRuntime(
            permissionBridges: { nil },
            handlePermissionLifecycleEvent: { event in
                lifecycleEvents.append(event)
            },
            isActiveGlancePreviewSurface: { tabId, candidateWebView in
                glanceLookupTabIds.append(tabId)
                glanceLookupWebViewIds.append(ObjectIdentifier(candidateWebView))
                return candidateWebView === webView
            },
            surfaceState: { _, _ in .inactive },
            profile: { _, _ in nil }
        )

        let surfaceState = tab.permissionRequestSurfaceState(for: webView)
        tab.handleNormalTabPermissionNavigation(to: targetURL)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertTrue(surfaceState.isActive)
        XCTAssertTrue(surfaceState.isVisible)
        XCTAssertEqual(glanceLookupTabIds, [tab.id])
        XCTAssertEqual(glanceLookupWebViewIds, [ObjectIdentifier(webView)])
        XCTAssertEqual(
            lifecycleEvents,
            [
                .mainFrameNavigation(
                    pageId: tab.currentPermissionPageId(),
                    tabId: tab.id.uuidString.lowercased(),
                    profilePartitionId: nil,
                    targetURL: targetURL,
                    reason: "normal-tab-main-frame-navigation"
                ),
            ]
        )
    }

    func testExternalSchemeCurrentPageClosureInvalidatesAfterWebViewReplacement() async throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, windowState) = registerWindow(
            in: browserManager,
            selecting: tab
        )
        let webView = try makePermissionWebView(for: tab)
        browserManager.testWebViewRuntime().trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        let committedURL = try await loadCommittedDocument(
            on: webView,
            at: tab.url
        )
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let navigation = await bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        let context = try XCTUnwrap(tab.externalSchemePermissionTabContext(for: webView))

        let committedPageId = tab.currentPermissionPageId()
        XCTAssertEqual(context.pageId, committedPageId)
        XCTAssertEqual(
            context.navigationOrPageGeneration,
            committedPageId.split(separator: ":").last.map(String.init)
        )
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertTrue(try XCTUnwrap(context.isCurrentPage)())

        tab.invalidatePermissionPageForReplacement(reason: "test-webview-replacement")

        XCTAssertFalse(try XCTUnwrap(context.isCurrentPage)())
        XCTAssertNotEqual(tab.currentPermissionPageId(), committedPageId)
        withExtendedLifetime((windowRegistry, navigation)) {
            /* Keep the physical residence and navigation identity alive. */
        }
    }

    func testPermissionSurfaceOwnerUsesNarrowContextWithoutTab() throws {
        let tabId = UUID()
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Permission Context"
        )
        let currentURL = URL(string: "https://visible.example/page")!
        let committedURL = URL(string: "https://committed.example/main")!
        let presentationURL = URL(string: "https://visible.example/page#drifted")!
        let targetURL = URL(string: "https://next.example/")!
        var pageGeneration = 0
        var lifecycleEvents: [SumiPermissionLifecycleEvent] = []
        let webView = PermissionCommittedURLWebView()
        webView.reportedCommittedURL = presentationURL
        let documentLease = TabMainFrameDocumentLease(
            revision: 7,
            documentGeneration: 3,
            webViewID: ObjectIdentifier(webView),
            participantID: UUID(),
            committedURL: committedURL,
            presentationURL: presentationURL,
            isPDF: false,
            isAuthority: true
        )

        let owner = TabPermissionSurfaceOwner(
            context: TabPermissionSurfaceOwner.Context(
                tabId: tabId,
                currentURL: { currentURL },
                resolveProfile: { profile },
                profile: { _ in profile },
                surfaceState: { _ in
                    TabPermissionSurfaceState(
                        isActive: true,
                        isVisible: false
                    )
                },
                pageIdentity: {
                    let tabIdString = tabId.uuidString.lowercased()
                    let generation = String(pageGeneration)
                    return TabExtensionPageIdentity(
                        tabId: tabIdString,
                        pageGeneration: generation,
                        pageId: "\(tabIdString):\(generation)"
                    )
                },
                documentLease: { candidate in
                    candidate === webView ? documentLease : nil
                },
                isCurrentPage: { pageId, pageGenerationSnapshot in
                    let tabIdString = tabId.uuidString.lowercased()
                    let generation = String(pageGeneration)
                    return pageId == "\(tabIdString):\(generation)"
                        && pageGenerationSnapshot == generation
                },
                invalidatePageForWebViewReplacement: {
                    pageGeneration += 1
                },
                handlePermissionLifecycleEvent: { event in
                    lifecycleEvents.append(event)
                },
                isActiveGlancePreviewSurface: { _ in false },
                isAuxiliaryMiniWindow: { false }
            )
        )

        let permissionContext = try XCTUnwrap(owner.externalSchemeContext(for: webView))
        let popupContext = try XCTUnwrap(owner.popupContext(for: webView))

        XCTAssertEqual(permissionContext.tabId, tabId.uuidString.lowercased())
        XCTAssertEqual(permissionContext.pageId, "\(tabId.uuidString.lowercased()):0")
        XCTAssertEqual(permissionContext.profilePartitionId, profile.id.uuidString.lowercased())
        XCTAssertEqual(permissionContext.committedURL, committedURL)
        XCTAssertEqual(permissionContext.visibleURL, currentURL)
        XCTAssertEqual(permissionContext.mainFrameURL, committedURL)
        XCTAssertTrue(permissionContext.isActiveTab)
        XCTAssertFalse(permissionContext.isVisibleTab)
        XCTAssertTrue(try XCTUnwrap(permissionContext.isCurrentPage)())
        XCTAssertEqual(popupContext.committedURL, committedURL)
        XCTAssertEqual(popupContext.visibleURL, currentURL)
        XCTAssertTrue(try XCTUnwrap(popupContext.isCurrentPage)())

        owner.handleNormalTabPermissionNavigation(to: targetURL)
        owner.invalidatePageForWebViewReplacement(reason: "test-replacement")

        XCTAssertFalse(try XCTUnwrap(permissionContext.isCurrentPage)())
        XCTAssertEqual(owner.currentPageId(), "\(tabId.uuidString.lowercased()):1")
        XCTAssertEqual(
            lifecycleEvents,
            [
                .mainFrameNavigation(
                    pageId: "\(tabId.uuidString.lowercased()):0",
                    tabId: tabId.uuidString.lowercased(),
                    profilePartitionId: profile.id.uuidString,
                    targetURL: targetURL,
                    reason: "normal-tab-main-frame-navigation"
                ),
                .webViewReplaced(
                    pageId: "\(tabId.uuidString.lowercased()):0",
                    tabId: tabId.uuidString.lowercased(),
                    profilePartitionId: profile.id.uuidString,
                    reason: "test-replacement"
                ),
            ]
        )
    }

    func testPermissionSurfaceStateAndPopupContextUseActiveVisibleWindowSurface() async throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, windowState) = registerWindow(in: browserManager, selecting: tab)
        let webView = try makePermissionWebView(for: tab)
        let committedURL = try await loadCommittedDocument(
            on: webView,
            at: tab.url
        )
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let navigation = await bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )

        XCTAssertFalse(tab.permissionRequestSurfaceState(for: webView).isActive)
        XCTAssertFalse(tab.permissionRequestSurfaceState(for: webView).isVisible)

        let webViewRuntime = browserManager.testWebViewRuntime()
        webViewRuntime.trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        let context = try XCTUnwrap(tab.popupPermissionTabContext(for: webView))
        XCTAssertTrue(tab.permissionRequestIsActiveSurface(for: webView))
        XCTAssertTrue(tab.permissionRequestIsVisibleSurface(for: webView))
        XCTAssertTrue(context.isActiveTab)
        XCTAssertTrue(context.isVisibleTab)
        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.visibleURL, tab.url)
        XCTAssertEqual(context.mainFrameURL, tab.url)
        withExtendedLifetime((windowRegistry, navigation)) { /* no-op */ }
    }

    func testPermissionSurfaceStateFollowsExactCloneWindow() async throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, firstWindow) = registerWindow(
            in: browserManager,
            selecting: tab
        )
        let secondWindow = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        secondWindow.currentSpaceId = firstWindow.currentSpaceId
        secondWindow.currentProfileId = firstWindow.currentProfileId
        secondWindow.currentTabId = tab.id
        windowRegistry.register(secondWindow)

        let firstWebView = try makePermissionWebView(for: tab)
        let secondWebView = try makePermissionWebView(for: tab)
        let runtime = browserManager.testWebViewRuntime()
        XCTAssertTrue(runtime.trackedWebViewAdmission.attemptAssignment(
            firstWebView,
            to: tab,
            in: firstWindow.id,
            replaySemanticOperation: {
                XCTFail("Unexpected WebView deferral")
            }
        ).isAccepted)
        XCTAssertTrue(runtime.trackedWebViewAdmission.attemptAssignment(
            secondWebView,
            to: tab,
            in: secondWindow.id,
            replaySemanticOperation: {
                XCTFail("Unexpected WebView deferral")
            }
        ).isAccepted)
        let firstCommittedURL = try await loadCommittedDocument(
            on: firstWebView,
            at: tab.url
        )
        let secondCommittedURL = try await loadCommittedDocument(
            on: secondWebView,
            at: tab.url
        )
        XCTAssertEqual(firstCommittedURL, secondCommittedURL)
        let intent = tab.beginMainFrameNavigationIntent(
            to: firstCommittedURL
        )
        let firstNavigation = await bindCommittedDocument(
            on: firstWebView,
            tab: tab,
            intent: intent,
            committedURL: firstCommittedURL
        )
        let secondNavigation = await bindCommittedDocument(
            on: secondWebView,
            tab: tab,
            intent: intent,
            committedURL: secondCommittedURL
        )

        var firstState = tab.permissionRequestSurfaceState(for: firstWebView)
        var secondState = tab.permissionRequestSurfaceState(for: secondWebView)
        XCTAssertTrue(firstState.isActive)
        XCTAssertTrue(firstState.isVisible)
        XCTAssertFalse(secondState.isActive)
        XCTAssertTrue(secondState.isVisible)

        windowRegistry.setActive(secondWindow)

        firstState = tab.permissionRequestSurfaceState(for: firstWebView)
        secondState = tab.permissionRequestSurfaceState(for: secondWebView)
        XCTAssertFalse(firstState.isActive)
        XCTAssertTrue(firstState.isVisible)
        XCTAssertTrue(secondState.isActive)
        XCTAssertTrue(secondState.isVisible)
        withExtendedLifetime((firstNavigation, secondNavigation)) { /* no-op */ }
    }

    func testPermissionContextAcceptsAuthorityAndCompatibleCommittedClone() async throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, firstWindow) = registerWindow(
            in: browserManager,
            selecting: tab
        )
        let secondWindow = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        secondWindow.currentSpaceId = firstWindow.currentSpaceId
        secondWindow.currentProfileId = firstWindow.currentProfileId
        secondWindow.currentTabId = tab.id
        windowRegistry.register(secondWindow)
        let committedURL = URL(string: "https://committed.example/document")!
        let authorityWebView = try makePermissionWebView(for: tab)
        let cloneWebView = try makePermissionWebView(for: tab)
        let trackedAdmission = browserManager.testWebViewRuntime().trackedWebViewAdmission
        trackedAdmission.attemptAssignment(
            authorityWebView,
            to: tab,
            in: firstWindow.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        trackedAdmission.attemptAssignment(
            cloneWebView,
            to: tab,
            in: secondWindow.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        let authorityCommittedURL = try await loadCommittedDocument(
            on: authorityWebView,
            at: committedURL
        )
        let cloneCommittedURL = try await loadCommittedDocument(
            on: cloneWebView,
            at: committedURL
        )
        XCTAssertEqual(cloneCommittedURL, authorityCommittedURL)
        let intent = tab.beginMainFrameNavigationIntent(to: authorityCommittedURL)
        let authorityNavigation = await bindCommittedDocument(
            on: authorityWebView,
            tab: tab,
            intent: intent,
            committedURL: authorityCommittedURL
        )
        let cloneNavigation = await bindCommittedDocument(
            on: cloneWebView,
            tab: tab,
            intent: intent,
            committedURL: cloneCommittedURL
        )

        let authorityLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: authorityWebView)
        )
        let cloneLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: cloneWebView)
        )
        XCTAssertTrue(authorityLease.isAuthority)
        XCTAssertFalse(cloneLease.isAuthority)
        XCTAssertEqual(cloneLease.revision, authorityLease.revision)
        XCTAssertEqual(
            cloneLease.documentGeneration,
            authorityLease.documentGeneration
        )
        XCTAssertNotEqual(cloneLease.participantID, authorityLease.participantID)
        XCTAssertEqual(cloneLease.committedURL, authorityCommittedURL)
        XCTAssertEqual(cloneLease.presentationURL, authorityCommittedURL)
        XCTAssertEqual(
            tab.externalSchemePermissionTabContext(for: authorityWebView)?.committedURL,
            authorityCommittedURL
        )
        XCTAssertEqual(
            tab.externalSchemePermissionTabContext(for: cloneWebView)?.committedURL,
            cloneCommittedURL
        )
        withExtendedLifetime(
            (windowRegistry, authorityNavigation, cloneNavigation)
        ) { /* no-op */ }
    }

    func testPermissionContextRejectsDivergedAndStaleCloneWithoutBorrowingTabOrigin() async {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let committedURL = URL(string: "https://committed.example/document")!
        let divergedURL = URL(string: "https://stale-clone.example/document")!
        let authorityWebView = PermissionCommittedURLWebView()
        let divergedWebView = PermissionCommittedURLWebView()
        let pdfMismatchWebView = PermissionCommittedURLWebView()
        let compatibleClone = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let authorityNavigation = await bindCommittedDocument(
            on: authorityWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        let divergedNavigation = await bindCommittedDocument(
            on: divergedWebView,
            tab: tab,
            intent: intent,
            committedURL: divergedURL
        )
        let pdfMismatchNavigation = await bindCommittedDocument(
            on: pdfMismatchWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL,
            isPDF: true
        )
        let compatibleNavigation = await bindCommittedDocument(
            on: compatibleClone,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        tab.extensionPageRuntimeOwner.committedMainDocumentURL = committedURL

        XCTAssertNil(tab.committedDocumentRuntime.lease(for: divergedWebView))
        XCTAssertNil(tab.popupPermissionTabContext(for: divergedWebView))
        XCTAssertNil(tab.externalSchemePermissionTabContext(for: divergedWebView))
        XCTAssertNil(tab.webNotificationTabContext(for: divergedWebView))
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: pdfMismatchWebView))
        XCTAssertNil(tab.popupPermissionTabContext(for: pdfMismatchWebView))

        _ = tab.beginMainFrameNavigationIntent(
            to: URL(string: "https://newer.example/document")!
        )

        XCTAssertNil(tab.committedDocumentRuntime.lease(for: compatibleClone))
        XCTAssertNil(tab.externalSchemePermissionTabContext(for: compatibleClone))
        withExtendedLifetime(
            (
                authorityNavigation,
                divergedNavigation,
                pdfMismatchNavigation,
                compatibleNavigation
            )
        ) { /* no-op */ }
    }

    func testPendingPermissionContextInvalidatesOnSameDocumentPresentationChange() async throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, windowState) = registerWindow(
            in: browserManager,
            selecting: tab
        )
        let committedURL = URL(string: "https://example.com/document")!
        let presentationURL = URL(string: "https://example.com/document#updated")!
        let webView = try makePermissionWebView(for: tab)
        browserManager.testWebViewRuntime().trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        let actualCommittedURL = try await loadCommittedDocument(
            on: webView,
            at: committedURL
        )
        let intent = tab.beginMainFrameNavigationIntent(to: actualCommittedURL)
        let navigation = await bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: actualCommittedURL
        )
        let context = try XCTUnwrap(
            tab.externalSchemePermissionTabContext(for: webView)
        )
        XCTAssertTrue(try XCTUnwrap(context.isCurrentPage)())

        let sameDocumentNavigation = NSObject()
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: ObjectIdentifier(sameDocumentNavigation),
                navigationLifetime: sameDocumentNavigation,
                targetURL: presentationURL,
                allowsUserInitiatedSupersession: false,
                continuationKind: .sameDocument
            ),
            .authority
        )

        XCTAssertFalse(try XCTUnwrap(context.isCurrentPage)())
        let updatedLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: webView)
        )
        XCTAssertEqual(updatedLease.committedURL, actualCommittedURL)
        XCTAssertEqual(updatedLease.presentationURL, presentationURL)
        XCTAssertNotNil(tab.externalSchemePermissionTabContext(for: webView))
        withExtendedLifetime(
            (windowRegistry, navigation, sameDocumentNavigation)
        ) { /* no-op */ }
    }

    private func makeTab(browserManager: BrowserManager? = nil) -> Tab {
        if let browserManager {
            let tab = browserManager.tabFactory.makeTab(
                url: URL(string: "https://example.com/page")!,
                name: "Example",
                loadsCachedFaviconOnInit: false
            )
            tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
            return tab
        }
        return Tab(
            url: URL(string: "https://example.com/page")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeManagedTab(in browserManager: BrowserManager) -> Tab {
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Permission Surface Tests"
            )
        return browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/page",
            in: space,
            activate: true
        )
    }

    private func makePermissionWebView(for tab: Tab) throws -> FocusableWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = try XCTUnwrap(tab.resolveProfile()).dataStore
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        return webView
    }

    @discardableResult
    private func bindCommittedDocument(
        on webView: WKWebView,
        tab: Tab,
        intent: TabMainFrameNavigationIntent,
        committedURL: URL,
        isPDF: Bool = false
    ) async -> NSObject {
        (webView as? PermissionCommittedURLWebView)?.reportedCommittedURL = committedURL
        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: intent.revision,
                targetURL: intent.targetURL
            ),
            .claimed
        )
        let navigation = NSObject()
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            matching: nil
        ))
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
        let responder = tab.makeMainFrameLifecycleResponder()
        if isPDF {
            _ = await responder.decidePolicy(
                for: SumiNavigationResponse(
                    url: committedURL,
                    isForMainFrame: true,
                    canShowMIMEType: true,
                    shouldDownload: false,
                    httpResponse: nil,
                    mimeType: "application/pdf",
                    mainFrameNavigation: nil
                ),
                context: context
            )
        }
        responder.navigationDidCommit(context)
        return navigation
    }

    private func loadCommittedDocument(
        on webView: WKWebView,
        at url: URL
    ) async throws -> URL {
        let didFinish = expectation(description: "permission document loaded")
        let previousDelegate = webView.navigationDelegate
        let delegate = PermissionDocumentNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            "<html><body>permission source</body></html>",
            baseURL: url
        )
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = previousDelegate
        return try XCTUnwrap(webView.committedURL)
    }

    @discardableResult
    private func registerWindow(
        in browserManager: BrowserManager,
        selecting tab: Tab
    ) -> (WindowRegistry, BrowserWindowState) {
        let windowRegistry = browserManager.windowRegistry

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = tab.spaceId
        windowState.currentProfileId = tab.resolveProfile()?.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (windowRegistry, windowState)
    }
}

@MainActor
private final class PermissionDocumentNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}

@MainActor
final class PermissionCommittedURLWebView: WKWebView {
    var reportedCommittedURL: URL?

    override func responds(to aSelector: Selector!) -> Bool {
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
