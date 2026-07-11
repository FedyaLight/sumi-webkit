import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebKitPermissionUIDelegateOwnerTests: XCTestCase {
    func testLegacyMediaUIDelegateFailsClosedWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://top.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView()
        var decisions: [Bool] = []

        tab.webKitUIDelegateOwner.webView(
            webView,
            requestUserMediaAuthorizationForDevices: SumiWebKitLegacyCaptureDevices.camera.rawValue,
            url: URL(string: "https://camera.example/request")!,
            mainFrameURL: URL(string: "https://top.example/page")!
        ) { decision in
            decisions.append(decision)
        }

        XCTAssertEqual(decisions, [false])
    }

    func testFilePickerPermissionContextUsesExactFocusableDocument() async throws {
        let browserManager = BrowserManager()
        let space = browserManager.tabManager.spaceStateOwner.currentSpace
            ?? browserManager.tabManager.spaceServices.catalog.createSpace(
                name: "File Picker Permission Tests"
            )
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://files.example/page",
            in: space,
            activate: true
        )
        let windowRegistry = browserManager.windowRegistry ?? WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = tab.resolveProfile()?.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        let webView = FocusableWKWebView()
        XCTAssertTrue(browserManager.testWebViewRuntime().ownershipService.assign(
            webView,
            to: tab,
            in: windowState.id
        ))
        await loadDocument(on: webView, at: tab.url)
        let committedURL = try XCTUnwrap(webView.committedURL)
        let navigation = await bindCommittedDocument(
            on: webView,
            tab: tab,
            committedURL: committedURL
        )
        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertNotNil(tab.committedDocumentRuntime.lease(for: webView))

        let context = try XCTUnwrap(tab.filePickerPermissionTabContext(for: webView))

        XCTAssertEqual(context.tabId, tab.id.uuidString.lowercased())
        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertEqual(context.visibleURL, webView.url)
        XCTAssertEqual(context.mainFrameURL, committedURL)
        XCTAssertTrue(context.isCurrentPage())
        withExtendedLifetime((windowRegistry, navigation)) {
            /* Keep window and navigation identity alive. */
        }
    }

    func testLegacyMediaUIDelegateRejectsCallbackWebViewWithoutExactDocumentLease() async throws {
        let browserManager = BrowserManager()
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://top.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let authorityWebView = FocusableWKWebView()
        await loadDocument(on: authorityWebView, at: tab.url)
        let committedURL = try XCTUnwrap(authorityWebView.committedURL)
        let navigation = await bindCommittedDocument(
            on: authorityWebView,
            tab: tab,
            committedURL: committedURL
        )
        let unrelatedCallbackWebView = FocusableWKWebView()
        await loadDocument(on: unrelatedCallbackWebView, at: tab.url)
        var decisions: [Bool] = []

        tab.webKitUIDelegateOwner.webView(
            unrelatedCallbackWebView,
            requestUserMediaAuthorizationForDevices: SumiWebKitLegacyCaptureDevices.camera.rawValue,
            url: URL(string: "https://top.example/page")!,
            mainFrameURL: URL(string: "https://top.example/page")!
        ) { decision in
            decisions.append(decision)
        }

        XCTAssertEqual(decisions, [false])
        withExtendedLifetime(navigation) { /* Keep navigation identity alive. */ }
    }

    func testFilePickerActivationCannotCrossFocusableWebViewCloneBoundary() async throws {
        let presenter = PermissionFilePickerPanelPresenter()
        let browserManager = BrowserManager(filePickerPanelPresenter: presenter)
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://files.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let callbackWebView = FocusableWKWebView()
        await loadDocument(on: callbackWebView, at: tab.url)
        let committedURL = try XCTUnwrap(callbackWebView.committedURL)
        let navigation = await bindCommittedDocument(
            on: callbackWebView,
            tab: tab,
            committedURL: committedURL
        )
        let activatedSiblingClone = FocusableWKWebView()
        activatedSiblingClone.popupUserActivation.record(
            event: makeMouseEvent(),
            kind: "leftMouseDown"
        )
        let frame = SumiWKFrameInfoMock(
            isMainFrame: true,
            request: URLRequest(url: committedURL),
            securityOrigin: SumiWKSecurityOriginMock.new(url: committedURL),
            webView: callbackWebView
        ).frameInfo
        let completion = expectation(description: "file picker denied")
        var results: [[URL]?] = []

        tab.webKitPermissionUIDelegateOwner.runOpenPanel(
            callbackWebView,
            parameters: WKOpenPanelParameters(),
            initiatedByFrame: frame
        ) { urls in
            results.append(urls)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0])
        XCTAssertTrue(presenter.requests.isEmpty)
        XCTAssertTrue(
            activatedSiblingClone.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
        XCTAssertFalse(
            callbackWebView.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
        withExtendedLifetime(navigation) { /* Keep navigation identity alive. */ }
    }

    private func loadDocument(on webView: WKWebView, at url: URL) async {
        let didFinish = expectation(description: "permission source document loaded")
        let delegate = PermissionDocumentNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<html><body>permission source</body></html>", baseURL: url)
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
    }

    private func makeMouseEvent() -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event")
        }
        return event
    }

    @discardableResult
    private func bindCommittedDocument(
        on webView: WKWebView,
        tab: Tab,
        committedURL: URL
    ) async -> NSObject {
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
        tab.makeMainFrameLifecycleResponder().navigationDidCommit(context)
        XCTAssertNotNil(tab.committedDocumentRuntime.lease(for: webView))
        return navigation
    }
}

@MainActor
private final class PermissionFilePickerPanelPresenter: SumiFilePickerPanelPresenting {
    private(set) var requests: [SumiFilePickerPanelPresentationRequest] = []

    func presentFilePicker(
        _ request: SumiFilePickerPanelPresentationRequest,
        for _: WKWebView?,
        completion: @escaping @MainActor (SumiFilePickerPanelResult) -> Void
    ) {
        requests.append(request)
        completion(.cancelled)
    }
}

private final class PermissionDocumentNavigationDelegate: NSObject, WKNavigationDelegate {
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
