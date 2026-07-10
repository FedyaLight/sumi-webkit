import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiReaderPresentationTests: XCTestCase {
    func testReaderNavigationPolicyAllowsOnlyInitialMainDocument() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        var policy = SumiReaderNavigationPolicy()

        XCTAssertEqual(policy.decide(
            navigationType: .other,
            isMainFrame: false,
            destinationURL: sourceURL
        ), .cancel)
        XCTAssertEqual(policy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: sourceURL
        ), .allowInitialDocument)
        XCTAssertEqual(policy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: sourceURL
        ), .cancel)
        XCTAssertEqual(policy.decide(
            navigationType: .reload,
            isMainFrame: true,
            destinationURL: sourceURL
        ), .cancel)
    }

    func testReaderNavigationPolicyRoutesOnlyUserHTTPLinks() throws {
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/next"))
        let externalURL = try XCTUnwrap(URL(string: "mailto:reader@example.com"))
        var linkPolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .cancel)
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .allowInitialDocument)

        XCTAssertEqual(linkPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .routeToCanonical(destinationURL))
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .cancel)

        var formPolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(formPolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .allowInitialDocument)
        XCTAssertEqual(formPolicy.decide(
            navigationType: .formSubmitted,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .cancel)
        XCTAssertEqual(formPolicy.decide(
            navigationType: .formResubmitted,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .cancel)

        var rejectedSchemePolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(rejectedSchemePolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            destinationURL: destinationURL
        ), .allowInitialDocument)
        XCTAssertEqual(rejectedSchemePolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            destinationURL: externalURL
        ), .cancel)
    }

    func testReaderPresentationLeavesCanonicalHistoryAndTabStateUntouched() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let canonicalWebView = ReaderExtractionWebView()
        let tab = Tab(
            url: sourceURL,
            name: "Canonical title",
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(canonicalWebView)
        let navigationLifetime = bindCommittedDocument(
            on: canonicalWebView,
            tab: tab,
            url: sourceURL
        )
        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)
        let originalURL = tab.url
        let originalName = tab.name
        let originalCurrentItem = canonicalWebView.backForwardList.currentItem
        let originalBackListCount = canonicalWebView.backForwardList.backList.count
        let originalForwardListCount = canonicalWebView.backForwardList.forwardList.count

        let toggle = Task { @MainActor in
            try await SumiReaderModeService.toggleReaderMode(
                on: canonicalWebView,
                tab: tab
            )
        }
        await awaitPendingExtraction(on: canonicalWebView)
        canonicalWebView.completeArticleExtraction()
        try await toggle.value

        XCTAssertEqual(tab.url, originalURL)
        XCTAssertEqual(tab.name, originalName)
        XCTAssertIdentical(canonicalWebView.backForwardList.currentItem, originalCurrentItem)
        XCTAssertEqual(canonicalWebView.backForwardList.backList.count, originalBackListCount)
        XCTAssertEqual(canonicalWebView.backForwardList.forwardList.count, originalForwardListCount)
        XCTAssertTrue(host.hasReaderPresentation())
        let readerWebView = try XCTUnwrap(
            host.activePresentationWebView as? FocusableWKWebView
        )
        XCTAssertFalse(host.activePresentationWebView === canonicalWebView)
        XCTAssertTrue(canonicalWebView.isHidden)

        let pageMenu = NSMenu()
        let nativeReloadItem = NSMenuItem(
            title: "Reload",
            action: nil,
            keyEquivalent: ""
        )
        nativeReloadItem.identifier = NSUserInterfaceItemIdentifier(
            SumiWebKitMenuItemIdentifier.reload.rawValue
        )
        pageMenu.addItem(nativeReloadItem)
        let pageMenuController = SumiWebPageMenuController()
        pageMenuController.prepare(
            pageMenu,
            for: readerWebView,
            targetHint: .page
        )
        let printItem = try XCTUnwrap(pageMenu.items.first {
            SumiWebPageMenuCommand($0.identifier) == .printPage
        })
        XCTAssertIdentical(printItem.target as AnyObject?, pageMenuController)
        withExtendedLifetime(navigationLifetime) { /* Keep exact navigation identity alive. */ }
    }

    func testReaderExtractionRefusesStaleDocumentLease() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let replacementURL = try XCTUnwrap(URL(string: "https://example.com/replacement"))
        let canonicalWebView = ReaderExtractionWebView()
        let tab = Tab(
            url: sourceURL,
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(canonicalWebView)
        let navigationLifetime = bindCommittedDocument(
            on: canonicalWebView,
            tab: tab,
            url: sourceURL
        )
        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)

        let toggle = Task { @MainActor in
            try await SumiReaderModeService.toggleReaderMode(
                on: canonicalWebView,
                tab: tab
            )
        }
        await awaitPendingExtraction(on: canonicalWebView)
        _ = tab.beginMainFrameNavigationIntent(to: replacementURL)
        canonicalWebView.completeArticleExtraction()

        do {
            try await toggle.value
            XCTFail("A stale committed-document lease must not install Reader")
        } catch SumiReaderModeService.ReaderError.unavailable {
            // Expected: extraction belonged to the previous committed document.
        } catch {
            XCTFail("Unexpected Reader error: \(error)")
        }

        XCTAssertFalse(host.hasReaderPresentation())
        XCTAssertIdentical(host.activePresentationWebView, canonicalWebView)
        withExtendedLifetime(navigationLifetime) { /* Keep exact navigation identity alive. */ }
    }

    func testReaderPresentationTransfersToNewHostWithoutStaleOwnerSideEffects() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let canonicalWebView = WKWebView()
        let firstHost = SumiWebViewContainerView(tabID: UUID(), webView: canonicalWebView)
        let lease = documentLease(for: canonicalWebView, url: sourceURL)
        XCTAssertTrue(firstHost.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceURL: sourceURL,
            documentLease: lease,
            navigate: { _ in XCTFail("Reader navigation was not requested") }
        ))
        let readerWebView = firstHost.activePresentationWebView

        let secondHost = SumiWebViewContainerView(
            tabID: firstHost.tabID,
            webView: canonicalWebView
        )

        XCTAssertFalse(firstHost.hasReaderPresentation())
        XCTAssertTrue(secondHost.hasReaderPresentation(matching: lease))
        XCTAssertIdentical(secondHost.activePresentationWebView, readerWebView)
        XCTAssertIdentical(canonicalWebView.superview, secondHost)
        XCTAssertIdentical(readerWebView.superview, secondHost)
        XCTAssertTrue(canonicalWebView.isHidden)

        firstHost.dismissReader()
        firstHost.removeFromSuperview()
        XCTAssertTrue(secondHost.hasReaderPresentation(matching: lease))
        XCTAssertTrue(canonicalWebView.isHidden)

        readerWebView.pageZoom = 1.5
        secondHost.dismissReader()
        XCTAssertIdentical(secondHost.activePresentationWebView, canonicalWebView)
        XCTAssertEqual(canonicalWebView.pageZoom, 1.5, accuracy: 0.001)
        XCTAssertFalse(canonicalWebView.isHidden)
    }

    private func bindCommittedDocument(
        on webView: ReaderExtractionWebView,
        tab: Tab,
        url: URL
    ) -> NSObject {
        webView.reportedCommittedURL = url
        let navigationLifetime = NSObject()
        let navigationID = ObjectIdentifier(navigationLifetime)
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: url,
            allowsUserInitiatedSupersession: true,
            continuationKind: nil
        ), .authority)
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: webView,
            navigationID: navigationID,
            committedURL: url,
            isPDF: false
        ).shouldPublishSharedEffects)
        XCTAssertNotNil(tab.mainFrameDocumentLease(for: webView))
        return navigationLifetime
    }

    private func documentLease(
        for webView: WKWebView,
        url: URL
    ) -> TabMainFrameDocumentLease {
        TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(webView),
            participantID: UUID(),
            committedURL: url,
            presentationURL: url,
            isPDF: false,
            isAuthority: true
        )
    }

    private func awaitPendingExtraction(on webView: ReaderExtractionWebView) async {
        for _ in 0..<20 {
            if webView.hasPendingArticleExtraction {
                return
            }
            await Task.yield()
        }
        XCTFail("Reader extraction did not reach the WebKit callback")
    }
}

@MainActor
private final class ReaderExtractionWebView: WKWebView {
    var reportedCommittedURL: URL?
    private var extractionCompletion:
        (@MainActor @Sendable (Any?, (any Error)?) -> Void)?
    private var isArticleExtractionReady = false

    var hasPendingArticleExtraction: Bool {
        extractionCompletion != nil
    }

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

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
    ) {
        if isArticleExtractionReady {
            isArticleExtractionReady = false
            completionHandler?(articlePayload, nil)
            return
        }
        extractionCompletion = completionHandler
    }

    func completeArticleExtraction() {
        guard let completion = extractionCompletion else {
            isArticleExtractionReady = true
            return
        }
        extractionCompletion = nil
        completion(articlePayload, nil)
    }

    private var articlePayload: [String: Any] {
        [
            "title": "Reader title",
            "contentHTML": "<p>Reader article body</p>",
            "excerpt": "Reader excerpt",
            "siteName": "Example",
            "byline": "Author",
            "publishedTime": "2026-07-10",
            "textLength": NSNumber(value: 1_000),
        ]
    }
}
