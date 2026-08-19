import AppKit
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi
import SumiDomain

@MainActor
final class SumiNavigationDownloadResponderTests: SumiNavigationResponderTestCase {

    func testSumiNavigationDownloadAdapterMapsActionAndResponseCallbacks() throws {
        let target = SumiNavigationDownloadProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let actionDownload = SumiWebKitDownloadMock(
            originalRequest: URLRequest(url: URL(string: "https://example.com/action-original.zip")!)
        )
        let responseDownload = SumiWebKitDownloadMock(
            originalRequest: URLRequest(url: URL(string: "https://example.com/response-original.zip")!)
        )
        let action = navigationAction(
            url: URL(string: "https://example.com/action.zip")!,
            navigationType: .linkActivated(isMiddleClick: false),
            shouldDownload: true
        )
        let httpResponse = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com/response.zip")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Disposition": "attachment; filename=response.zip"]
        ))
        let response = NavigationResponse(
            response: httpResponse,
            isForMainFrame: true,
            canShowMIMEType: false,
            mainFrameNavigation: mainFrameNavigation(receiving: action)
        )

        adapter.navigationAction(action, didBecome: actionDownload)
        adapter.navigationResponse(response, didBecome: responseDownload)

        XCTAssertEqual(target.actionDownloads.map(\.action.url), [URL(string: "https://example.com/action.zip")!])
        XCTAssertEqual(target.actionDownloads.first?.action.shouldDownload, true)
        XCTAssertNil(target.actionDownloads.first?.download.response)
        XCTAssertEqual(target.actionDownloads.first?.download.originalRequest?.url, URL(string: "https://example.com/action-original.zip")!)
        XCTAssertEqual(target.responseDownloads.map(\.response.url), [URL(string: "https://example.com/response.zip")!])
        XCTAssertEqual(target.responseDownloads.first?.response.shouldDownload, true)
        XCTAssertEqual(target.responseDownloads.first?.response.httpResponse?.statusCode, 200)
        XCTAssertEqual(target.responseDownloads.first?.download.response?.url, URL(string: "https://example.com/response.zip")!)
        XCTAssertEqual(target.responseDownloads.first?.download.originalRequest?.url, URL(string: "https://example.com/response-original.zip")!)
    }

    func testSumiNavigationAdapterTerminatesActionAndResponseDownloadConversion() {
        let webView = WKWebView(frame: .zero)
        let target = SumiNavigationTerminalProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/download")!,
            navigationType: .other,
            webView: webView
        ))
        let response = NavigationResponse(
            response: URLResponse(
                url: URL(string: "https://example.com/download")!,
                mimeType: "application/octet-stream",
                expectedContentLength: 1,
                textEncodingName: nil
            ),
            isForMainFrame: true,
            canShowMIMEType: false,
            mainFrameNavigation: navigation
        )

        adapter.navigationAction(
            navigation.navigationAction,
            willBecomeDownloadIn: webView
        )
        adapter.navigationResponse(response, willBecomeDownloadIn: webView)

        XCTAssertEqual(
            target.terminations.map(\.reason),
            [.actionBecameDownload, .responseBecameDownload]
        )
        XCTAssertTrue(target.terminations.allSatisfy {
            $0.navigationID == ObjectIdentifier(navigation) && $0.webView === webView
        })
    }

    func testDownloadResponderRequestsDownloadForDownloadNavigationAction() async {
        let managerHarness = DownloadTestHarness()
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        managerHarness.manager.settings = settings
        let tab = Tab(url: URL(string: "https://example.com")!)
        let sourceWebView = FocusableWKWebView()
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: managerHarness.manager,
            transportFactory: SumiWebKitDownloadTransportFactory()
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/file.zip")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true,
                webView: sourceWebView
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isDownload, true)
    }

    func testDownloadFlyOriginUsesPrimaryMouseDownLocation() throws {
        let window = makeDownloadOriginWindow()
        let webView = FocusableWKWebView(
            frame: NSRect(x: 100, y: 80, width: 600, height: 400)
        )
        window.contentView?.addSubview(webView)
        let clickLocation = NSPoint(x: 215, y: 165)
        webView.gestures.record(
            try makeDownloadOriginMouseEvent(at: clickLocation),
            kind: .primaryMouseDown
        )
        let responder = makeDownloadOriginResponder()

        let origin = try XCTUnwrap(
            responder.fileIconFlyAnimationOrigin(in: webView)
        )

        XCTAssertEqual(
            origin.sourceRectInWindow.midX,
            clickLocation.x,
            accuracy: 0.5
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midY,
            clickLocation.y,
            accuracy: 0.5
        )
    }

    func testDownloadFlyOriginSurvivesMouseUpGestureCleanup() throws {
        let window = makeDownloadOriginWindow()
        let webView = FocusableWKWebView(
            frame: NSRect(x: 100, y: 80, width: 600, height: 400)
        )
        window.contentView?.addSubview(webView)
        let clickLocation = NSPoint(x: 260, y: 190)
        let receipt = webView.gestures.record(
            try makeDownloadOriginMouseEvent(at: clickLocation),
            kind: .primaryMouseDown
        )

        webView.gestures.clear(ifCurrent: receipt)

        let origin = try XCTUnwrap(
            makeDownloadOriginResponder()
                .fileIconFlyAnimationOrigin(in: webView)
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midX,
            clickLocation.x,
            accuracy: 0.5
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midY,
            clickLocation.y,
            accuracy: 0.5
        )
    }

    func testDownloadFlyOriginSurvivesNavigationInteractionReset() throws {
        let window = makeDownloadOriginWindow()
        let webView = FocusableWKWebView(
            frame: NSRect(x: 100, y: 80, width: 600, height: 400)
        )
        window.contentView?.addSubview(webView)
        let clickLocation = NSPoint(x: 300, y: 210)
        webView.gestures.record(
            try makeDownloadOriginMouseEvent(at: clickLocation),
            kind: .primaryMouseDown
        )

        webView.resetPageInteractionStateForNavigation()

        let origin = try XCTUnwrap(
            makeDownloadOriginResponder()
                .fileIconFlyAnimationOrigin(in: webView)
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midX,
            clickLocation.x,
            accuracy: 0.5
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midY,
            clickLocation.y,
            accuracy: 0.5
        )
    }

    func testDownloadFlyOriginFallsBackToOriginatingWebView() throws {
        let window = makeDownloadOriginWindow()
        let originatingWebView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300)
        )
        let targetWebView = FocusableWKWebView(
            frame: NSRect(x: 400, y: 0, width: 400, height: 300)
        )
        window.contentView?.addSubview(originatingWebView)
        window.contentView?.addSubview(targetWebView)
        let clickLocation = NSPoint(x: 120, y: 90)
        originatingWebView.gestures.record(
            try makeDownloadOriginMouseEvent(at: clickLocation),
            kind: .primaryMouseDown
        )

        let origin = try XCTUnwrap(
            makeDownloadOriginResponder().fileIconFlyAnimationOrigin(
                originatingWebView: originatingWebView,
                targetWebView: targetWebView
            )
        )

        XCTAssertEqual(
            origin.sourceRectInWindow.midX,
            clickLocation.x,
            accuracy: 0.5
        )
        XCTAssertEqual(
            origin.sourceRectInWindow.midY,
            clickLocation.y,
            accuracy: 0.5
        )
    }

    func testDownloadFlyOriginIsNilWithoutRecentMouseDown() {
        let window = makeDownloadOriginWindow()
        let webView = FocusableWKWebView(
            frame: NSRect(x: 100, y: 80, width: 600, height: 400)
        )
        window.contentView?.addSubview(webView)

        XCTAssertNil(
            makeDownloadOriginResponder()
                .fileIconFlyAnimationOrigin(in: webView)
        )
    }

    func testDownloadResponderDoesNotTreatOptionGlanceClickAsDownload() async {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings
        let sourceWebView = FocusableWKWebView()
        sourceWebView.owningTab = tab
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: nil,
            transportFactory: nil
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/page")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true,
                webView: sourceWebView
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
    }

    func testDownloadResponderReadsModifiersFromCrossWebViewSource() async {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings
        let sourceWebView = FocusableWKWebView()
        let targetWebView = FocusableWKWebView()
        sourceWebView.owningTab = tab
        sourceWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option]),
            kind: .primaryMouseDown
        )
        targetWebView.gestures.record(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command]),
            kind: .primaryMouseDown
        )
        let adapter = SumiNavigationResponderAdapter(
            target: SumiDownloadsNavigationResponder(
                tab: tab,
                downloadManager: nil,
                transportFactory: nil
            )
        )
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/page")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true,
                sourceWebView: sourceWebView,
                targetWebView: targetWebView
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
    }

    func testDownloadResponderContinuesForRegularNavigationAction() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let sourceWebView = FocusableWKWebView()
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: nil,
            transportFactory: nil
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/page")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: sourceWebView
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
    }

    func testDownloadResponderRequestsDownloadForUnshowableResponse() async {
        let managerHarness = DownloadTestHarness()
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        managerHarness.manager.settings = settings
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: managerHarness.manager,
            transportFactory: SumiWebKitDownloadTransportFactory()
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let response = URLResponse(
            url: URL(string: "https://example.com/file.bin")!,
            mimeType: "application/octet-stream",
            expectedContentLength: 128,
            textEncodingName: nil
        )

        let policy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: response,
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: nil
            )
        )

        XCTAssertEqual(policy, .download)
    }

    func testDownloadResponderRequestsDownloadForAttachmentAtDirectoryURL() async throws {
        let managerHarness = DownloadTestHarness()
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        managerHarness.manager.settings = settings
        let responder = SumiDownloadsNavigationResponder(
            tab: Tab(url: URL(string: "https://mail.google.com")!),
            downloadManager: managerHarness.manager,
            transportFactory: SumiWebKitDownloadTransportFactory()
        )
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://mail.google.com/mail/u/0/?ui=2&view=att&disp=attd&realattid=fake")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Disposition": "attachment; filename=report.pdf"]
        ))

        let policy = await SumiNavigationResponderAdapter(target: responder)
            .decidePolicy(for: NavigationResponse(
                response: response,
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: nil
            ))

        XCTAssertEqual(policy, .download)
    }

    func testDownloadResponderFailsClosedWhenCompositionIsUnavailable() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: DownloadManager.unavailable(),
            transportFactory: nil
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/file.zip")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
    }

    func testDownloadResponderCancelsSessionRestorationCacheDownloadResponse() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: nil,
            transportFactory: nil
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default
        let sourceWebView = FocusableWKWebView()
        let action = navigationAction(
            url: URL(string: "https://example.com/restored-file.bin")!,
            navigationType: .sessionRestoration,
            requestCachePolicy: .returnCacheDataElseLoad,
            webView: sourceWebView,
            isUserInitiated: false
        )

        _ = await adapter.decidePolicy(for: action, preferences: &preferences)
        let navigation = mainFrameNavigation(receiving: action)

        let policy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://example.com/restored-file.bin")!,
                    mimeType: "application/octet-stream",
                    expectedContentLength: 128,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: navigation
            )
        )

        XCTAssertEqual(policy, .cancel)
    }

    private func makeDownloadOriginWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    private func makeDownloadOriginMouseEvent(
        at location: NSPoint
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func makeDownloadOriginResponder()
        -> SumiDownloadsNavigationResponder {
        SumiDownloadsNavigationResponder(
            tab: Tab(url: URL(string: "https://example.com")!),
            downloadManager: nil,
            transportFactory: nil
        )
    }
}
