import AppKit
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class PagePresentationStateTests: XCTestCase {
    func testColdDestinationAndFailureKindParticipateInDisplayState() throws {
        let pageID = UUID()
        let destinationA = try XCTUnwrap(URL(string: "https://example.com/a"))
        let destinationB = try XCTUnwrap(URL(string: "https://example.com/b"))
        let loadingA = WebsiteDisplayState(
            splitPresentation: nil,
            currentId: pageID,
            compositorVersion: 1,
            currentPagePresentation: .loading(
                pageID: pageID,
                destination: destinationA
            ),
            isSplitDropCaptureActive: false
        )
        let loadingB = WebsiteDisplayState(
            splitPresentation: nil,
            currentId: pageID,
            compositorVersion: 1,
            currentPagePresentation: .loading(
                pageID: pageID,
                destination: destinationB
            ),
            isSplitDropCaptureActive: false
        )
        let failure = WebsiteDisplayState(
            splitPresentation: nil,
            currentId: pageID,
            compositorVersion: 1,
            currentPagePresentation: .preparationFailure(
                pageID: pageID,
                destination: destinationA
            ),
            isSplitDropCaptureActive: false
        )

        XCTAssertNotEqual(loadingA, loadingB)
        XCTAssertNotEqual(loadingA, failure)
        XCTAssertFalse(loadingA.currentPagePresentation.hasLiveWebContentResidence)
        XCTAssertTrue(
            WebsiteDisplayState(
                splitPresentation: nil,
                currentId: pageID,
                compositorVersion: 1,
                currentPagePresentation: .live(pageID: pageID),
                isSplitDropCaptureActive: false
            ).currentPagePresentation.hasLiveWebContentResidence
        )
    }

    func testResolverPublishesDestinationLoadingThenTypedTerminalFailure()
        throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/cold")
        )
        let tab = Tab(url: destination, loadsCachedFaviconOnInit: false)
        let window = BrowserWindowState()
        let admission = window.pageMaterializationRequests.begin(
            pageID: tab.id,
            windowID: window.id,
            residenceGeneration: tab.webViewSession.generation,
            destination: destination
        )

        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: window,
                webView: nil
            ),
            .loading(pageID: tab.id, destination: destination)
        )

        _ = window.pageMaterializationRequests.settle(
            admission.request,
            as: .failed(.residenceUnavailable)
        )
        tab.loadingState = .didFinish

        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: window,
                webView: nil
            ),
            .preparationFailure(pageID: tab.id, destination: destination)
        )
    }

    func testResolverKeepsCommittedDocumentLiveDuringNextProvisionalNavigation()
        throws {
        let committedURL = try XCTUnwrap(
            URL(string: "https://example.com/document")
        )
        let provisionalURL = try XCTUnwrap(
            URL(string: "https://example.com/download")
        )
        let tab = Tab(url: committedURL, loadsCachedFaviconOnInit: false)
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = committedURL
        webView.reportedCommittedURL = committedURL
        let responder = tab.makeMainFrameLifecycleResponder()

        let committedNavigation = NSObject()
        let committedContext = SumiNavigationContext(
            navigationID: ObjectIdentifier(committedNavigation),
            navigationLifetime: committedNavigation,
            action: nil,
            url: committedURL,
            isCurrent: true,
            isCommitted: true,
            isMainFrame: true,
            webView: webView
        )
        responder.navigationWillStart(committedContext)
        responder.navigationDidStart(committedContext)
        responder.navigationDidCommit(committedContext)
        responder.navigationDidFinish(committedContext)

        let provisionalNavigation = NSObject()
        let provisionalContext = SumiNavigationContext(
            navigationID: ObjectIdentifier(provisionalNavigation),
            navigationLifetime: provisionalNavigation,
            action: nil,
            url: provisionalURL,
            isCurrent: true,
            isCommitted: false,
            isMainFrame: true,
            webView: webView
        )
        responder.navigationWillStart(provisionalContext)
        responder.navigationDidStart(provisionalContext)

        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: BrowserWindowState(),
                webView: webView
            ),
            .live(pageID: tab.id)
        )
    }

    func testResolverPublishesTypedRestoreFailureInsteadOfEmptyPage() throws {
        let destination = try XCTUnwrap(URL(string: "https://example.com/lost"))
        let tab = Tab(
            url: SumiSurface.restoreFailureURL,
            loadsCachedFaviconOnInit: false
        )
        tab.isRestoreFailure = true
        tab.restoreFailureDestination = destination

        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: BrowserWindowState(),
                webView: nil
            ),
            .restoreFailure(pageID: tab.id, destination: destination)
        )
        XCTAssertFalse(tab.representsSumiEmptySurface)
        XCTAssertFalse(tab.requiresPrimaryWebView)
    }

    func testPassivePresentationSurfacesDoNotRenderBrowserStatusText()
        throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/loading")
        )
        let pageID = UUID()
        let presentations: [PagePresentation] = [
            .empty,
            .browserSurface(pageID: pageID),
            .dataClearing(pageID: pageID, destination: destination),
            .loading(pageID: pageID, destination: destination),
            .live(pageID: pageID),
            .preparationFailure(pageID: pageID, destination: destination),
            .restoreFailure(pageID: pageID, destination: destination),
            .integrityFailure(pageID: pageID),
        ]

        for presentation in presentations {
            let surface = PagePresentationSurfaceView(
                presentation: presentation
            )
            XCTAssertEqual(surface.presentation, presentation)
            XCTAssertFalse(allSubviews(of: surface).contains {
                $0 is NSTextField || $0 is NSProgressIndicator || $0 is NSButton
            })
        }
    }

    func testResolverPublishesStableNonloadingRecoveryFailure() throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/recovery-failure")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: destination)
        let tab = Tab(
            url: destination,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        _ = transaction.beginRecovery(on: webView)
        transaction.failRecoveryDelivery(on: webView)
        tab.loadingState = .idle

        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: BrowserWindowState(),
                webView: webView
            ),
            .recoveryFailure(
                pageID: tab.id,
                destination: destination,
                nativeSnapshotAvailable: false
            )
        )
        XCTAssertFalse(tab.isLoading)
    }

    func testRecoveryFailureActionsDistinguishNativeRestoreFromOpenAddress()
        throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/recovery-actions")
        )
        var actions: [Bool] = []
        let surface = PagePresentationSurfaceView(
            presentation: .recoveryFailure(
                pageID: UUID(),
                destination: destination,
                nativeSnapshotAvailable: true
            ),
            repairAction: { actions.append($0) }
        )
        let buttons = allSubviews(of: surface).compactMap { $0 as? NSButton }
        XCTAssertEqual(
            Set(buttons.map(\.title)),
            Set(["Repair and Restore", "Open Address"])
        )

        buttons.first { $0.title == "Repair and Restore" }?.performClick(nil)
        buttons.first { $0.title == "Open Address" }?.performClick(nil)

        XCTAssertEqual(actions, [true, false])
    }

    func testEveryNonLivePresentationHasAStaticTypedSurface() throws {
        let pageID = UUID()
        let destination = try XCTUnwrap(URL(string: "https://example.com/page"))
        let presentations: [PagePresentation] = [
            .empty,
            .browserSurface(pageID: pageID),
            .dataClearing(pageID: pageID, destination: destination),
            .loading(pageID: pageID, destination: destination),
            .preparationFailure(pageID: pageID, destination: destination),
            .restoreFailure(pageID: pageID, destination: destination),
            .recoveryFailure(
                pageID: pageID,
                destination: destination,
                nativeSnapshotAvailable: false
            ),
            .integrityFailure(pageID: pageID),
        ]

        for presentation in presentations {
            let surface = PagePresentationSurfaceView(
                presentation: presentation
            )
            XCTAssertEqual(surface.presentation, presentation)
            XCTAssertFalse(allSubviews(of: surface).contains {
                $0 is WKWebView || $0 is NSProgressIndicator
            })
        }
    }

    func testCleanupCoverWinsOverCommittedWebContentUntilSessionEnds() throws {
        let destination = try XCTUnwrap(URL(string: "https://example.com/private"))
        let tab = Tab(url: destination, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let sessionID = UUID()

        tab.beginWebsiteDataMutationPresentation(
            sessionID: sessionID,
            destination: destination
        )
        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: tab,
                windowState: BrowserWindowState(),
                webView: webView
            ),
            .dataClearing(pageID: tab.id, destination: destination)
        )

        tab.endWebsiteDataMutationPresentation(sessionID: sessionID)
        XCTAssertNil(tab.websiteDataMutationPresentation)
    }

    func testValidatedSplitKeepsIndependentMissingPaneFailure() throws {
        let liveTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/live")),
            loadsCachedFaviconOnInit: false
        )
        let missingID = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(liveTab.id), .regularTab(missingID)],
            layoutKind: .vertical
        ))
        let window = BrowserWindowState()
        let presentation = try XCTUnwrap(WindowSplitPresentation(
            windowID: window.id,
            group: group,
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(liveTab.id)
            ),
            liveTabIDByMemberID: [
                .regularTab(liveTab.id): liveTab.id,
                .regularTab(missingID): missingID,
            ]
        ))
        let context = PagePresentationBrowserContextStub(
            tabsByID: [liveTab.id: liveTab]
        )
        let browser = BrowserManager()
        let graph = makeTestWebViewRuntimeGraph()
        let container = makeContainer(
            browser: browser,
            context: context,
            window: window
        )
        let planner = WindowWebContentPresentationPlanner(
            browserContext: context,
            splitQuery: browser.splitWindowContext.query,
            webViewOwnershipQuery: graph.ownershipQuery,
            windowState: window,
            containerView: container,
            hostRegistry: WindowWebContentHostRegistry(),
            protectionRuntime: graph.protectionRuntime
        )
        let state = WebsiteDisplayState(
            splitPresentation: presentation,
            currentId: liveTab.id,
            compositorVersion: 1,
            currentPagePresentation: .live(pageID: liveTab.id),
            pagePresentationsByID: [
                liveTab.id: .live(pageID: liveTab.id),
                missingID: .integrityFailure(pageID: missingID),
            ],
            isSplitDropCaptureActive: false
        )

        guard case .split(_, let panes) = planner.presentationDecision(
            for: state,
            currentTab: liveTab
        ) else {
            return XCTFail("A validated split must not collapse to a single pane")
        }
        XCTAssertEqual(panes.count, 2)
        XCTAssertIdentical(panes[0].tab, liveTab)
        XCTAssertNil(panes[1].tab)
        XCTAssertEqual(
            panes[1].presentation,
            .integrityFailure(pageID: missingID)
        )
    }

    func testHostResolutionIsLookupOnlyAndPresenterInstallsTypedSurface()
        throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/lookup-only")
        )
        let tab = Tab(url: destination, loadsCachedFaviconOnInit: false)
        let window = BrowserWindowState()
        let browser = BrowserManager()
        let context = PagePresentationBrowserContextStub(
            tabsByID: [tab.id: tab]
        )
        let graph = makeTestWebViewRuntimeGraph()
        let container = makeContainer(
            browser: browser,
            context: context,
            window: window
        )
        let registration = graph.compositorRuntime.registerContainer(
            container,
            for: window.id,
            immediateVisualHandoffHandler: { false }
        )
        defer {
            _ = graph.compositorRuntime.tearDownContainer(registration) {}
        }
        let registry = WindowWebContentHostRegistry()
        let attachments = WindowWebContentHostAttachmentService(
            containerView: container,
            hostRegistry: registry,
            compositorRuntime: graph.compositorRuntime,
            protectionRuntime: graph.protectionRuntime,
            windowID: window.id,
            surfaceStyle: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(),
                backgroundColor: .windowBackgroundColor
            )
        )
        let resolver = WindowWebContentHostResolver(
            ownershipQuery: graph.ownershipQuery,
            compositorRuntime: graph.compositorRuntime,
            protectionRuntime: graph.protectionRuntime,
            hostRegistry: registry,
            hostAttachments: attachments,
            windowID: window.id
        )

        XCTAssertNil(resolver.resolveHost(
            for: tab,
            slot: .single,
            containerRegistration: registration
        ))
        XCTAssertTrue(tab.isUnloaded)

        let presenter = WindowWebContentPanePresenter(
            windowState: window,
            containerView: container,
            compositorRuntime: graph.compositorRuntime,
            hostRegistry: registry,
            hostResolver: resolver,
            hostAttachments: attachments,
            browserContext: context
        )
        XCTAssertTrue(presenter.presentSinglePane(
            pane: WindowWebContentPaneDecision(
                pageID: tab.id,
                tab: tab,
                presentation: .loading(
                    pageID: tab.id,
                    destination: destination
                )
            ),
            containerRegistration: registration
        ))

        let surface = try XCTUnwrap(
            container.singlePaneView.subviews
                .compactMap { $0 as? PagePresentationSurfaceView }
                .first
        )
        XCTAssertEqual(
            surface.presentation,
            .loading(pageID: tab.id, destination: destination)
        )
        XCTAssertTrue(tab.isUnloaded)
    }

    func testSplitPresenterKeepsLivePaneWhenSiblingIsTerminalFailure()
        throws {
        let webViewSessions = WebViewSessionRepository()
        let liveTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/live")),
            webViewSessions: webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let failedTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/failed")),
            webViewSessions: webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(liveTab.id), .regularTab(failedTab.id)],
            layoutKind: .vertical
        ))
        let window = BrowserWindowState()
        let presentation = try XCTUnwrap(WindowSplitPresentation(
            windowID: window.id,
            group: group,
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(liveTab.id)
            ),
            liveTabIDByMemberID: [
                .regularTab(liveTab.id): liveTab.id,
                .regularTab(failedTab.id): failedTab.id,
            ]
        ))
        let browser = BrowserManager()
        let context = PagePresentationBrowserContextStub(
            tabsByID: [liveTab.id: liveTab, failedTab.id: failedTab]
        )
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: webViewSessions,
            resolveRuntimeTab: { tabID in
                if tabID == liveTab.id { return liveTab }
                if tabID == failedTab.id { return failedTab }
                return nil
            }
        )
        let liveWebView = FocusableWKWebView()
        liveWebView.owningTab = liveTab
        XCTAssertTrue(graph.canonicalWebViewPlacement.placeAuxiliaryTracked(
            liveWebView,
            for: liveTab,
            in: window.id,
            promoteToPrimary: true
        ).isAccepted)
        XCTAssertIdentical(
            graph.ownershipQuery.webView(for: liveTab.id, in: window.id),
            liveWebView
        )
        let container = makeContainer(
            browser: browser,
            context: context,
            window: window
        )
        let registration = graph.compositorRuntime.registerContainer(
            container,
            for: window.id
        )
        defer {
            _ = graph.compositorRuntime.tearDownContainer(registration) {}
        }
        let registry = WindowWebContentHostRegistry()
        let attachments = makeAttachments(
            container: container,
            registry: registry,
            graph: graph,
            window: window
        )
        let resolver = WindowWebContentHostResolver(
            ownershipQuery: graph.ownershipQuery,
            compositorRuntime: graph.compositorRuntime,
            protectionRuntime: graph.protectionRuntime,
            hostRegistry: registry,
            hostAttachments: attachments,
            windowID: window.id
        )
        let presenter = WindowWebContentPanePresenter(
            windowState: window,
            containerView: container,
            compositorRuntime: graph.compositorRuntime,
            hostRegistry: registry,
            hostResolver: resolver,
            hostAttachments: attachments,
            browserContext: context
        )

        XCTAssertTrue(presenter.presentSplitGroup(
            presentation,
            panes: [
                WindowWebContentPaneDecision(
                    pageID: liveTab.id,
                    tab: liveTab,
                    presentation: .live(pageID: liveTab.id)
                ),
                WindowWebContentPaneDecision(
                    pageID: failedTab.id,
                    tab: failedTab,
                    presentation: .preparationFailure(
                        pageID: failedTab.id,
                        destination: failedTab.url
                    )
                ),
            ],
            containerRegistration: registration
        ))

        XCTAssertIdentical(
            registry.host(for: .split(liveTab.id))?.webView,
            liveWebView
        )
        let failedSurface = try XCTUnwrap(
            container.paneView(for: failedTab.id)?.subviews
                .compactMap { $0 as? PagePresentationSurfaceView }
                .first
        )
        XCTAssertEqual(
            failedSurface.presentation,
            .preparationFailure(
                pageID: failedTab.id,
                destination: failedTab.url
            )
        )
    }

    func testAttachParkAndReattachPreserveWebViewWithoutNavigation() {
        let browser = BrowserManager()
        let context = PagePresentationBrowserContextStub(tabsByID: [:])
        let window = BrowserWindowState()
        let graph = makeTestWebViewRuntimeGraph()
        let container = makeContainer(
            browser: browser,
            context: context,
            window: window
        )
        let registration = graph.compositorRuntime.registerContainer(
            container,
            for: window.id
        )
        defer {
            _ = graph.compositorRuntime.tearDownContainer(registration) {}
        }
        let registry = WindowWebContentHostRegistry()
        let attachments = makeAttachments(
            container: container,
            registry: registry,
            graph: graph,
            window: window
        )
        let webView = PresentationNavigationCountingWebView()
        let host = SumiWebViewContainerView(tabID: UUID(), webView: webView)

        attachments.replaceHost(host, in: .single)
        attachments.attach(
            host,
            to: container.singlePaneView,
            containerRegistration: registration
        )
        attachments.clearSinglePane()
        XCTAssertIdentical(
            registry.parkedHost(for: host.tabID, webView: webView),
            host
        )
        attachments.replaceHost(host, in: .single)
        attachments.attach(
            host,
            to: container.singlePaneView,
            containerRegistration: registration
        )

        XCTAssertIdentical(host.activePresentationWebView, webView)
        XCTAssertEqual(webView.loadCount, 0)
        XCTAssertEqual(webView.reloadCount, 0)
    }

    func testApplyTimeResolutionRejectsQueuedLoadingSurfaceAfterCommit()
        async throws {
        let destination = try XCTUnwrap(
            URL(string: "https://example.com/committed")
        )
        let sessions = WebViewSessionRepository()
        let tab = Tab(
            url: destination,
            webViewSessions: sessions,
            loadsCachedFaviconOnInit: false
        )
        let window = BrowserWindowState()
        let context = PagePresentationBrowserContextStub(
            tabsByID: [tab.id: tab],
            currentTab: tab
        )
        let browser = BrowserManager()
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: sessions,
            resolveRuntimeTab: { tabID in tabID == tab.id ? tab : nil }
        )
        let webView = PresentationNavigationCountingWebView()
        webView.reportedURL = destination
        webView.reportedCommittedURL = destination
        XCTAssertTrue(graph.canonicalWebViewPlacement.placeAuxiliaryTracked(
            webView,
            for: tab,
            in: window.id,
            promoteToPrimary: true
        ).isAccepted)

        let container = makeContainer(
            browser: browser,
            context: context,
            window: window
        )
        let controller = WindowWebContentController(
            browserContext: context,
            splitQuery: browser.splitWindowContext.query,
            webViewOwnershipQuery: graph.ownershipQuery,
            webViewCompositorRuntime: graph.compositorRuntime,
            webViewProtectionRuntime: graph.protectionRuntime,
            surfaceStyle: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(),
                backgroundColor: .windowBackgroundColor
            ),
            windowState: window,
            containerView: container
        )
        controller.loadView()
        defer { controller.tearDownController() }

        let navigation = NSObject()
        let navigationContext = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: destination,
            isCurrent: true,
            isCommitted: false,
            isMainFrame: true,
            webView: webView
        )
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: navigationContext.navigationID,
                navigationLifetime: navigation,
                targetURL: destination,
                allowsUserInitiatedSupersession: false,
                continuationKind: nil
            ),
            .authority
        )
        XCTAssertFalse(
            graph.compositorRuntime.performImmediateVisualHandoffIfPossible(
                in: window.id
            )
        )

        tab.makeMainFrameLifecycleResponder().navigationDidCommit(
            navigationContext
        )
        XCTAssertNotNil(tab.committedDocumentRuntime.lease(for: webView))
        controller.update(
            displayState: WebsiteDisplayState(
                splitPresentation: nil,
                currentId: tab.id,
                compositorVersion: 1,
                currentPagePresentation: .loading(
                    pageID: tab.id,
                    destination: destination
                ),
                isSplitDropCaptureActive: false
            ),
            hoveredLinkHandler: { _ in },
            surfaceStyle: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(),
                backgroundColor: .windowBackgroundColor
            ),
            isSurfaceVisible: true
        )

        await drainMainQueue()

        XCTAssertTrue(container.singlePaneView.subviews.contains {
            ($0 as? SumiWebViewContainerView)?.webView === webView
        })
        XCTAssertFalse(container.singlePaneView.subviews.contains {
            $0 is PagePresentationSurfaceView
        })
        XCTAssertEqual(webView.loadCount, 0)
        XCTAssertEqual(webView.reloadCount, 0)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func makeContainer(
        browser: BrowserManager,
        context: PagePresentationBrowserContextStub,
        window: BrowserWindowState
    ) -> WindowWebContentSplitHostLayoutView {
        WindowWebContentSplitHostLayoutView(
            splitLayout: browser.splitWindowContext.layout,
            splitDrops: browser.splitWindowContext.drops,
            splitDropTargets: browser.splitWindowContext.dropTargets,
            splitPreviews: browser.splitWindowContext.previews,
            sidebarDragState: context.sidebarDragState,
            windowState: window,
            resolveDragTab: { _ in nil },
            surfaceStyle: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(),
                backgroundColor: .windowBackgroundColor
            )
        )
    }

    private func makeAttachments(
        container: WindowWebContentSplitHostLayoutView,
        registry: WindowWebContentHostRegistry,
        graph: WebViewRuntimeGraph,
        window: BrowserWindowState
    ) -> WindowWebContentHostAttachmentService {
        WindowWebContentHostAttachmentService(
            containerView: container,
            hostRegistry: registry,
            compositorRuntime: graph.compositorRuntime,
            protectionRuntime: graph.protectionRuntime,
            windowID: window.id,
            surfaceStyle: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(),
                backgroundColor: .windowBackgroundColor
            )
        )
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }
}

@MainActor
private final class PresentationNavigationCountingWebView: WKWebView {
    var reportedURL: URL?
    var reportedCommittedURL: URL?
    private(set) var loadCount = 0
    private(set) var reloadCount = 0

    override var url: URL? { reportedURL }

    override func responds(to selector: ObjectiveC.Selector?) -> Bool {
        guard let selector else { return false }
        let name = NSStringFromSelector(selector)
        if name == "committedURL" || name == "_committedURL" {
            return true
        }
        return super.responds(to: selector)
    }

    override func value(forKey key: String) -> Any? {
        if key == "committedURL" {
            return MainActor.assumeIsolated { reportedCommittedURL }
        }
        return super.value(forKey: key)
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadCount += 1
        return nil
    }

    override func reload() -> WKNavigation? {
        reloadCount += 1
        return nil
    }

    override func reloadFromOrigin() -> WKNavigation? {
        reloadCount += 1
        return nil
    }
}

@MainActor
private final class PagePresentationBrowserContextStub:
    WindowWebContentBrowserContext {
    let sidebarDragState = SidebarDragState()
    let tabsByID: [UUID: Tab]
    let currentTabValue: Tab?

    init(tabsByID: [UUID: Tab], currentTab: Tab? = nil) {
        self.tabsByID = tabsByID
        self.currentTabValue = currentTab
    }

    func currentTab(for _: BrowserWindowState) -> Tab? { currentTabValue }
    func tab(for tabID: UUID) -> Tab? { tabsByID[tabID] }
    func enqueueWindowMutationDuringHistorySwipe(
        _: HistorySwipeDeferredWindowMutationKind,
        for _: BrowserWindowState
    ) {}
}
