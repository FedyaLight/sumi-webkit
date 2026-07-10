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
            }
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

    func testExternalSchemeCurrentPageClosureInvalidatesAfterWebViewReplacement() throws {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let webView = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: tab.url)
        let navigation = bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: tab.url
        )
        let context = try XCTUnwrap(tab.externalSchemePermissionTabContext(for: webView))

        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.navigationOrPageGeneration, "0")
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertTrue(try XCTUnwrap(context.isCurrentPage)())

        tab.invalidatePermissionPageForReplacement(reason: "test-webview-replacement")

        XCTAssertFalse(try XCTUnwrap(context.isCurrentPage)())
        XCTAssertEqual(tab.currentPermissionPageId(), "\(tab.id.uuidString.lowercased()):1")
        withExtendedLifetime(navigation) { /* Keep navigation identity alive. */ }
    }

    func testPermissionSurfaceOwnerUsesNarrowContextWithoutTab() throws {
        let tabId = UUID()
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Permission Context",
            icon: "person"
        )
        let currentURL = URL(string: "https://visible.example/page")!
        let committedURL = URL(string: "https://committed.example/main")!
        let targetURL = URL(string: "https://next.example/")!
        var pageGeneration = 0
        var lifecycleEvents: [SumiPermissionLifecycleEvent] = []
        let webView = PermissionCommittedURLWebView()
        webView.reportedCommittedURL = committedURL
        let documentLease = TabMainFrameDocumentLease(
            revision: 7,
            documentGeneration: 3,
            webViewID: ObjectIdentifier(webView),
            participantID: UUID(),
            committedURL: committedURL,
            presentationURL: committedURL,
            isPDF: false,
            isAuthority: true
        )

        let owner = TabPermissionSurfaceOwner(
            context: TabPermissionSurfaceOwner.Context(
                tabId: tabId,
                currentURL: { currentURL },
                resolveProfile: { profile },
                isActiveTab: { true },
                isVisibleTab: { false },
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

        XCTAssertEqual(permissionContext.tabId, tabId.uuidString.lowercased())
        XCTAssertEqual(permissionContext.pageId, "\(tabId.uuidString.lowercased()):0")
        XCTAssertEqual(permissionContext.profilePartitionId, profile.id.uuidString.lowercased())
        XCTAssertEqual(permissionContext.committedURL, committedURL)
        XCTAssertEqual(permissionContext.visibleURL, currentURL)
        XCTAssertEqual(permissionContext.mainFrameURL, committedURL)
        XCTAssertTrue(permissionContext.isActiveTab)
        XCTAssertFalse(permissionContext.isVisibleTab)
        XCTAssertTrue(try XCTUnwrap(permissionContext.isCurrentPage)())

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

    func testPermissionSurfaceStateAndPopupContextUseActiveVisibleWindowSurface() throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, windowState) = registerWindow(in: browserManager, selecting: tab)
        let webView = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: tab.url)
        let navigation = bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: tab.url
        )

        XCTAssertTrue(tab.permissionRequestSurfaceState(for: webView).isActive)
        XCTAssertFalse(tab.permissionRequestSurfaceState(for: webView).isVisible)

        let coordinator = WebViewCoordinator(webViewSessions: browserManager.webViewSessions)
        browserManager.bindTestWebViewCoordinator(coordinator)
        coordinator.ownershipService.registerTrackedWebView(
            webView,
            for: tab,
            in: windowState.id
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

    func testPermissionContextAcceptsAuthorityAndCompatibleCommittedClone() throws {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let committedURL = URL(string: "https://committed.example/document")!
        let authorityWebView = PermissionCommittedURLWebView()
        let cloneWebView = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let authorityNavigation = bindCommittedDocument(
            on: authorityWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        let cloneNavigation = bindCommittedDocument(
            on: cloneWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )

        let authorityLease = try XCTUnwrap(
            tab.mainFrameDocumentLease(for: authorityWebView)
        )
        let cloneLease = try XCTUnwrap(
            tab.mainFrameDocumentLease(for: cloneWebView)
        )
        XCTAssertTrue(authorityLease.isAuthority)
        XCTAssertFalse(cloneLease.isAuthority)
        XCTAssertEqual(cloneLease.revision, authorityLease.revision)
        XCTAssertEqual(
            cloneLease.documentGeneration,
            authorityLease.documentGeneration
        )
        XCTAssertNotEqual(cloneLease.participantID, authorityLease.participantID)
        XCTAssertEqual(cloneLease.committedURL, committedURL)
        XCTAssertEqual(cloneLease.presentationURL, committedURL)
        XCTAssertEqual(
            tab.externalSchemePermissionTabContext(for: authorityWebView)?.committedURL,
            committedURL
        )
        XCTAssertEqual(
            tab.externalSchemePermissionTabContext(for: cloneWebView)?.committedURL,
            committedURL
        )
        withExtendedLifetime((authorityNavigation, cloneNavigation)) { /* no-op */ }
    }

    func testPermissionContextRejectsDivergedAndStaleCloneWithoutBorrowingTabOrigin() {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let committedURL = URL(string: "https://committed.example/document")!
        let divergedURL = URL(string: "https://stale-clone.example/document")!
        let authorityWebView = PermissionCommittedURLWebView()
        let divergedWebView = PermissionCommittedURLWebView()
        let pdfMismatchWebView = PermissionCommittedURLWebView()
        let compatibleClone = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let authorityNavigation = bindCommittedDocument(
            on: authorityWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        let divergedNavigation = bindCommittedDocument(
            on: divergedWebView,
            tab: tab,
            intent: intent,
            committedURL: divergedURL
        )
        let pdfMismatchNavigation = bindCommittedDocument(
            on: pdfMismatchWebView,
            tab: tab,
            intent: intent,
            committedURL: committedURL,
            isPDF: true
        )
        let compatibleNavigation = bindCommittedDocument(
            on: compatibleClone,
            tab: tab,
            intent: intent,
            committedURL: committedURL
        )
        tab.extensionPageRuntimeOwner.committedMainDocumentURL = committedURL

        XCTAssertNil(tab.mainFrameDocumentLease(for: divergedWebView))
        XCTAssertNil(tab.popupPermissionTabContext(for: divergedWebView))
        XCTAssertNil(tab.externalSchemePermissionTabContext(for: divergedWebView))
        XCTAssertNil(tab.webNotificationTabContext(for: divergedWebView))
        XCTAssertNil(tab.mainFrameDocumentLease(for: pdfMismatchWebView))
        XCTAssertNil(tab.popupPermissionTabContext(for: pdfMismatchWebView))

        _ = tab.beginMainFrameNavigationIntent(
            to: URL(string: "https://newer.example/document")!
        )

        XCTAssertNil(tab.mainFrameDocumentLease(for: compatibleClone))
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

    func testPendingPermissionContextInvalidatesOnSameDocumentPresentationChange() throws {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let committedURL = URL(string: "https://example.com/document")!
        let presentationURL = URL(string: "https://example.com/document#updated")!
        let webView = PermissionCommittedURLWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        let navigation = bindCommittedDocument(
            on: webView,
            tab: tab,
            intent: intent,
            committedURL: committedURL
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
        let updatedLease = try XCTUnwrap(tab.mainFrameDocumentLease(for: webView))
        XCTAssertEqual(updatedLease.committedURL, committedURL)
        XCTAssertEqual(updatedLease.presentationURL, presentationURL)
        XCTAssertNotNil(tab.externalSchemePermissionTabContext(for: webView))
        withExtendedLifetime((navigation, sameDocumentNavigation)) { /* no-op */ }
    }

    private func makeTab(browserManager: BrowserManager? = nil) -> Tab {
        if let browserManager {
            let tab = browserManager.tabManager.tabFactory.makeTab(
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
        let space = browserManager.tabManager.spaceStateOwner.currentSpace
            ?? browserManager.tabManager.spaceLifecycleOwner.createSpace(name: "Permission Surface Tests")
        return browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/page",
            in: space,
            activate: true
        )
    }

    @discardableResult
    private func bindCommittedDocument(
        on webView: PermissionCommittedURLWebView,
        tab: Tab,
        intent: TabMainFrameNavigationIntent,
        committedURL: URL,
        isPDF: Bool = false
    ) -> NSObject {
        webView.reportedCommittedURL = committedURL
        XCTAssertTrue(tab.markDeferredMainFrameLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.claimDeferredMainFrameLoad(
                on: webView,
                revision: intent.revision,
                targetURL: intent.targetURL
            ),
            .claimed
        )
        let navigation = NSObject()
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation
        ))
        let claim = tab.recordMainFrameCommitSnapshot(
            from: webView,
            navigationID: ObjectIdentifier(navigation),
            committedURL: committedURL,
            isPDF: isPDF
        )
        XCTAssertNotEqual(claim.role, .stale)
        return navigation
    }

    @discardableResult
    private func registerWindow(
        in browserManager: BrowserManager,
        selecting tab: Tab
    ) -> (WindowRegistry, BrowserWindowState) {
        let windowRegistry = browserManager.windowRegistry ?? WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (windowRegistry, windowState)
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
