import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ActivePageResolverTests: XCTestCase {
    func testGlanceSnapshotWinsAsOneCoherentResolution() throws {
        let window = BrowserWindowState()
        let selectedTab = makeTab("https://selected.example")
        let previewTab = makeTab("https://preview.example/original")
        let previewURL = try XCTUnwrap(URL(string: "https://preview.example/current"))
        let previewWebView = WKWebView()
        let selectedWebView = WKWebView()
        let resolver = ActivePageResolver(
            activeWindow: { window },
            selectedTab: { _ in selectedTab },
            glanceSnapshot: { _ in
                .init(tab: previewTab, url: previewURL, webView: previewWebView)
            },
            windowOwnedWebView: { _, _ in selectedWebView }
        )

        let page = try XCTUnwrap(resolver.resolveActiveWindow())

        XCTAssertEqual(page.source, .glancePreview)
        XCTAssertIdentical(page.windowState, window)
        XCTAssertIdentical(page.tab, previewTab)
        XCTAssertEqual(page.url, previewURL)
        XCTAssertIdentical(page.canonicalWebView, previewWebView)
    }

    func testSelectedPageUsesOnlyExactWindowWebView() throws {
        let requestedWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        let tab = makeTab("https://selected.example")
        let untrackedWebView = WKWebView()
        let exactWebView = WKWebView()
        tab.replaceUntrackedWebView(untrackedWebView)
        let resolver = ActivePageResolver(
            activeWindow: { requestedWindow },
            selectedTab: { _ in tab },
            glanceSnapshot: { _ in nil },
            windowOwnedWebView: { _, windowID in
                windowID == requestedWindow.id ? exactWebView : nil
            }
        )

        let requestedPage = try XCTUnwrap(resolver.resolve(in: requestedWindow))
        let otherPage = try XCTUnwrap(resolver.resolve(in: otherWindow))

        XCTAssertEqual(requestedPage.source, .selectedTab)
        XCTAssertIdentical(requestedPage.canonicalWebView, exactWebView)
        XCTAssertNil(otherPage.canonicalWebView)
        XCTAssertFalse(requestedPage.canonicalWebView === untrackedWebView)
    }

    func testReaderChangesPresentationWebViewWithoutChangingCanonicalPage() throws {
        let window = BrowserWindowState()
        let tab = makeTab("https://article.example")
        let canonicalWebView = WKWebView()
        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)
        let sourceURL = tab.url
        let lease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(canonicalWebView),
            participantID: UUID(),
            committedURL: sourceURL,
            presentationURL: sourceURL,
            isPDF: false,
            isAuthority: true
        )
        XCTAssertTrue(host.presentReader(
            html: "<article>Reader</article>",
            sourceDocument: SumiReaderSourceDocument(
                webView: canonicalWebView,
                lease: lease,
                sourceURL: sourceURL,
                remoteResourcePolicy: .denyRemoteResources,
                currentLease: { lease },
                routeWebLink: { _, _ in false },
                routeExternalLink: { _ in }
            )
        ))
        let resolver = ActivePageResolver(
            activeWindow: { window },
            selectedTab: { _ in tab },
            glanceSnapshot: { _ in nil },
            windowOwnedWebView: { _, _ in canonicalWebView }
        )

        let page = try XCTUnwrap(resolver.resolveActiveWindow())

        XCTAssertIdentical(page.canonicalWebView, canonicalWebView)
        XCTAssertIdentical(page.presentationWebView, host.activePresentationWebView)
        XCTAssertFalse(page.presentationWebView === canonicalWebView)
    }

    func testNoActiveWindowReturnsNil() {
        let resolver = ActivePageResolver(
            activeWindow: { nil },
            selectedTab: { _ in XCTFail("Selection must not be queried"); return nil },
            glanceSnapshot: { _ in XCTFail("Glance must not be queried"); return nil },
            windowOwnedWebView: { _, _ in XCTFail("WebView must not be queried"); return nil }
        )

        XCTAssertNil(resolver.resolveActiveWindow())
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}
