import AppKit
import struct SwiftUI.Binding
import class SwiftUI.NSHostingController
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
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .cancel)
        XCTAssertEqual(policy.decide(
            navigationType: .other,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .allowInitialDocument)
        XCTAssertEqual(policy.decide(
            navigationType: .other,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .cancel)
        XCTAssertEqual(policy.decide(
            navigationType: .reload,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .cancel)
    }

    func testReaderNavigationPolicyPreservesFragmentAndExternalLinkKinds() throws {
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/next"))
        let externalURL = try XCTUnwrap(URL(string: "mailto:reader@example.com"))
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let fragmentURL = try XCTUnwrap(URL(string: "https://example.com/article#details"))
        var linkPolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        ), .cancel)
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .allowInitialDocument)

        XCTAssertEqual(linkPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: fragmentURL,
            sourceURL: sourceURL
        ), .allowReaderFragment)
        XCTAssertEqual(linkPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        ), .routeWebLink(destinationURL, .currentTab))

        var formPolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(formPolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .allowInitialDocument)
        XCTAssertEqual(formPolicy.decide(
            navigationType: .formSubmitted,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        ), .cancel)
        XCTAssertEqual(formPolicy.decide(
            navigationType: .formResubmitted,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        ), .cancel)

        var externalSchemePolicy = SumiReaderNavigationPolicy()
        XCTAssertEqual(externalSchemePolicy.decide(
            navigationType: .other,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: sourceURL,
            sourceURL: sourceURL
        ), .allowInitialDocument)
        XCTAssertEqual(externalSchemePolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: externalURL,
            sourceURL: sourceURL
        ), .routeExternalLink(externalURL))
    }

    func testReaderNavigationPolicyPreservesModifierAndTargetBlankDisposition() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/next"))

        func presentedPolicy() -> SumiReaderNavigationPolicy {
            var policy = SumiReaderNavigationPolicy()
            XCTAssertEqual(policy.decide(
                navigationType: .other,
                isMainFrame: true,
                isTargetingNewWindow: false,
                destinationURL: sourceURL,
                sourceURL: sourceURL
            ), .allowInitialDocument)
            return policy
        }

        var commandPolicy = presentedPolicy()
        XCTAssertEqual(commandPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL,
            modifierFlags: [.command]
        ), .routeWebLink(destinationURL, .newTab(selected: false)))

        var selectedCommandPolicy = presentedPolicy()
        XCTAssertEqual(selectedCommandPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL,
            modifierFlags: [.command, .shift]
        ), .routeWebLink(destinationURL, .newTab(selected: true)))

        var targetBlankPolicy = presentedPolicy()
        XCTAssertEqual(targetBlankPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: nil,
            isTargetingNewWindow: true,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        ), .routeWebLink(destinationURL, .newTab(selected: true)))

        var optionTargetBlankPolicy = presentedPolicy()
        XCTAssertEqual(optionTargetBlankPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: nil,
            isTargetingNewWindow: true,
            destinationURL: destinationURL,
            sourceURL: sourceURL,
            modifierFlags: [.option]
        ), .routeWebLink(destinationURL, .newWindow(selected: true)))

        var downloadPolicy = presentedPolicy()
        XCTAssertEqual(downloadPolicy.decide(
            navigationType: .linkActivated,
            isMainFrame: true,
            isTargetingNewWindow: false,
            destinationURL: destinationURL,
            sourceURL: sourceURL,
            shouldDownload: true
        ), .cancel)
    }

    func testReaderContentSecurityPolicyAllowsRemoteMediaOnlyWithoutRuleLists() {
        let allowed = SumiReaderModeService.readerContentSecurityPolicy(
            remoteResourcePolicy: .sourceProfileWithoutRuleLists
        )
        XCTAssertTrue(allowed.contains("img-src http: https: data: blob:"))
        XCTAssertTrue(allowed.contains("media-src http: https: data: blob:"))

        let denied = SumiReaderModeService.readerContentSecurityPolicy(
            remoteResourcePolicy: .denyRemoteResources
        )
        XCTAssertTrue(denied.contains("img-src data: blob:"))
        XCTAssertTrue(denied.contains("media-src data: blob:"))
        XCTAssertFalse(denied.contains("http:"))
        XCTAssertFalse(denied.contains("https:"))
    }

    func testReaderConfigurationPreservesExactPersistentAndIncognitoDataStores()
        throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let stores = [
            WKWebsiteDataStore(forIdentifier: UUID()),
            WKWebsiteDataStore.nonPersistent(),
        ]

        for store in stores {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = store
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: "window.__normalTabAuthorityMustNotReachReader = true;",
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
            let sourceWebView = WKWebView(
                frame: .zero,
                configuration: configuration
            )
            let sourceDocument = presentationSourceDocument(
                for: sourceWebView,
                url: sourceURL
            )
            let session = try XCTUnwrap(
                ReaderPresentationSession(sourceDocument: sourceDocument)
            )

            XCTAssertIdentical(
                session.webView.configuration.websiteDataStore,
                store
            )
            let readerSources = session.webView.configuration
                .userContentController.userScripts.map(\.source)
            XCTAssertEqual(readerSources.count, 1)
            XCTAssertTrue(readerSources[0].contains("__sumiLinkInteractionInstalled"))
            XCTAssertFalse(
                readerSources.joined().contains(
                    "__normalTabAuthorityMustNotReachReader"
                )
            )
            session.invalidate()
        }
    }

    func testReaderCommandRevalidatesExactLeaseAndDismissesStalePresentation()
        throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/next"))
        let canonicalWebView = WKWebView()
        let lease = documentLease(for: canonicalWebView, url: sourceURL)
        var currentLease: TabMainFrameDocumentLease? = lease
        var routedLinks: [(URL, SumiLinkOpenBehavior)] = []
        let sourceDocument = SumiReaderSourceDocument(
            webView: canonicalWebView,
            lease: lease,
            sourceURL: sourceURL,
            remoteResourcePolicy: .denyRemoteResources,
            currentLease: { currentLease },
            routeWebLink: { url, behavior in
                routedLinks.append((url, behavior))
                return true
            },
            routeExternalLink: { _ in }
        )
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            webView: canonicalWebView
        )
        XCTAssertTrue(host.presentReader(
            html: "<article>Reader</article>",
            sourceDocument: sourceDocument
        ))
        let session = try XCTUnwrap(
            host.activePresentationWebView.navigationDelegate
                as? ReaderPresentationSession
        )
        XCTAssertEqual(
            decideReaderPolicy(
                session: session,
                action: readerNavigationAction(
                    sourceURL,
                    in: session.webView,
                    navigationType: .other
                )
            ),
            .allow
        )

        currentLease = TabMainFrameDocumentLease(
            revision: lease.revision + 1,
            documentGeneration: lease.documentGeneration + 1,
            webViewID: lease.webViewID,
            participantID: UUID(),
            committedURL: destinationURL,
            presentationURL: destinationURL,
            isPDF: false,
            isAuthority: true
        )
        XCTAssertEqual(
            decideReaderPolicy(
                session: session,
                action: readerNavigationAction(
                    destinationURL,
                    in: session.webView,
                    navigationType: .linkActivated
                )
            ),
            .cancel
        )

        XCTAssertTrue(routedLinks.isEmpty)
        XCTAssertFalse(host.hasReaderPresentation())
        XCTAssertIdentical(host.activePresentationWebView, canonicalWebView)
    }

    func testReaderTargetBlankCommandKeepsPresentationAndPreservesModifiers()
        throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/next"))
        let canonicalWebView = WKWebView()
        var routedLinks: [(URL, SumiLinkOpenBehavior)] = []
        let sourceDocument = presentationSourceDocument(
            for: canonicalWebView,
            url: sourceURL,
            routeWebLink: { url, behavior in
                routedLinks.append((url, behavior))
                return true
            }
        )
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            webView: canonicalWebView
        )
        XCTAssertTrue(host.presentReader(
            html: "<article>Reader</article>",
            sourceDocument: sourceDocument
        ))
        let session = try XCTUnwrap(
            host.activePresentationWebView.navigationDelegate
                as? ReaderPresentationSession
        )
        _ = decideReaderPolicy(
            session: session,
            action: readerNavigationAction(
                sourceURL,
                in: session.webView,
                navigationType: .other
            )
        )
        let targetBlankAction = readerNavigationAction(
            destinationURL,
            in: session.webView,
            navigationType: .linkActivated,
            targetsNewWindow: true,
            modifierFlags: [.option]
        )

        XCTAssertEqual(
            decideReaderPolicy(session: session, action: targetBlankAction),
            .cancel
        )
        XCTAssertEqual(routedLinks.count, 1)
        XCTAssertEqual(routedLinks[0].0, destinationURL)
        XCTAssertEqual(routedLinks[0].1, .newWindow(selected: true))
        XCTAssertTrue(host.hasReaderPresentation())
        XCTAssertIdentical(host.activePresentationWebView, session.webView)
    }

    func testReaderOptionClickUsesExactGlanceAndConsumesGestureOnlyOnSuccess()
        throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/preview"))
        let fallbackURL = try XCTUnwrap(URL(string: "https://example.com/fallback"))
        let canonicalWebView = WKWebView()
        let lease = documentLease(for: canonicalWebView, url: sourceURL)
        var glanceRequests: [(URL, CGRect?)] = []
        var webLinks: [(URL, SumiLinkOpenBehavior)] = []
        var glanceSucceeds = true
        let sourceDocument = SumiReaderSourceDocument(
            webView: canonicalWebView,
            lease: lease,
            sourceURL: sourceURL,
            remoteResourcePolicy: .denyRemoteResources,
            currentLease: { lease },
            routeWebLink: { url, behavior in
                webLinks.append((url, behavior))
                return true
            },
            routeExternalLink: { _ in },
            isGlanceTrigger: { flags in
                flags.intersection([.command, .option, .control, .shift])
                    == [.option]
            },
            routeGlance: { url, rect in
                glanceRequests.append((url, rect))
                return glanceSucceeds
            }
        )
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            webView: canonicalWebView
        )
        XCTAssertTrue(host.presentReader(
            html: "<article>Reader</article>",
            sourceDocument: sourceDocument
        ))
        let session = try XCTUnwrap(
            host.activePresentationWebView.navigationDelegate
                as? ReaderPresentationSession
        )
        _ = decideReaderPolicy(
            session: session,
            action: readerNavigationAction(
                sourceURL,
                in: session.webView,
                navigationType: .other
            )
        )
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        session.webView.recordUserGesture(event, kind: .primaryMouseDown)
        XCTAssertNotNil(session.webView.gestures.currentReceipt)

        XCTAssertEqual(
            decideReaderPolicy(
                session: session,
                action: readerNavigationAction(
                    destinationURL,
                    in: session.webView,
                    navigationType: .linkActivated,
                    modifierFlags: [.option]
                )
            ),
            .cancel
        )
        XCTAssertEqual(glanceRequests.count, 1)
        XCTAssertEqual(glanceRequests[0].0, destinationURL)
        XCTAssertNotNil(glanceRequests[0].1)
        XCTAssertTrue(webLinks.isEmpty)
        XCTAssertNil(session.webView.gestures.currentReceipt)
        XCTAssertTrue(host.hasReaderPresentation())

        glanceSucceeds = false
        session.webView.recordUserGesture(event, kind: .primaryMouseDown)
        XCTAssertEqual(
            decideReaderPolicy(
                session: session,
                action: readerNavigationAction(
                    fallbackURL,
                    in: session.webView,
                    navigationType: .linkActivated,
                    modifierFlags: [.option]
                )
            ),
            .cancel
        )
        XCTAssertEqual(glanceRequests.count, 2)
        XCTAssertEqual(webLinks.count, 1)
        XCTAssertEqual(webLinks[0].0, fallbackURL)
        XCTAssertEqual(webLinks[0].1, .currentTab)
        XCTAssertFalse(host.hasReaderPresentation())
    }

    func testReaderPresentationLeavesCanonicalHistoryAndTabStateUntouched() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let canonicalWebView = ReaderExtractionWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: sourceURL)
        let tab = Tab(
            url: sourceURL,
            name: "Canonical title",
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        tab.replaceUntrackedWebView(canonicalWebView)
        let navigationLifetime = bindCommittedDocument(
            on: canonicalWebView,
            tab: tab,
            transaction: transaction,
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
        let pageMenuPresenter = SumiWebPageMenuPresenter()
        readerWebView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(kind: .page)
        )
        pageMenuPresenter.menuWillOpen(pageMenu, for: readerWebView)
        let printItem = try XCTUnwrap(pageMenu.items.first {
            SumiWebPageMenuCommand($0.identifier) == .printPage
        })
        XCTAssertIdentical(
            printItem.target as AnyObject?,
            pageMenuPresenter.actionOwner
        )
        withExtendedLifetime(navigationLifetime) { /* Keep exact navigation identity alive. */ }
    }

    func testReaderExtractionRefusesStaleDocumentLease() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let replacementURL = try XCTUnwrap(URL(string: "https://example.com/replacement"))
        let canonicalWebView = ReaderExtractionWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: sourceURL)
        let tab = Tab(
            url: sourceURL,
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        tab.replaceUntrackedWebView(canonicalWebView)
        let navigationLifetime = bindCommittedDocument(
            on: canonicalWebView,
            tab: tab,
            transaction: transaction,
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

    func testNewSemanticIntentDismissesReaderBeforeWebKitSubmission() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let replacementURL = try XCTUnwrap(URL(string: "https://example.com/replacement"))
        let canonicalWebView = ReaderExtractionWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: sourceURL)
        let tab = Tab(
            url: sourceURL,
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        tab.replaceUntrackedWebView(canonicalWebView)
        let navigationLifetime = bindCommittedDocument(
            on: canonicalWebView,
            tab: tab,
            transaction: transaction,
            url: sourceURL
        )
        let host = SumiWebViewContainerView(
            tabID: tab.id,
            webView: canonicalWebView
        )

        let toggle = Task { @MainActor in
            try await SumiReaderModeService.toggleReaderMode(
                on: canonicalWebView,
                tab: tab
            )
        }
        await awaitPendingExtraction(on: canonicalWebView)
        canonicalWebView.completeArticleExtraction()
        try await toggle.value
        XCTAssertTrue(host.hasReaderPresentation())

        _ = tab.beginMainFrameNavigationIntent(to: replacementURL)

        XCTAssertFalse(host.hasReaderPresentation())
        XCTAssertIdentical(host.activePresentationWebView, canonicalWebView)
        withExtendedLifetime(navigationLifetime) { /* Keep navigation evidence alive. */ }
    }

    func testReaderPresentationRebindsPhysicalHoverWithoutCompositorApply() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let canonicalWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let host = SumiWebViewContainerView(tabID: UUID(), webView: canonicalWebView)
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let container = NSView()
        let registration = webViewRuntime.compositorRuntime.registerContainer(
            container,
            for: UUID()
        )
        let mutationGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        mutationGate.activate(registration)
        let hoverSession = WindowWebContentHoverSession(
            mutationGate: mutationGate,
            isDisplayed: { [weak host] webView in
                host?.activePresentationWebView === webView
            }
        )
        var activePresentationIDs: [ObjectIdentifier] = []
        let presentationObservation = host.observeActivePresentationWebView {
            activePresentationIDs.append(ObjectIdentifier($0))
        }
        var deliveredLinks: [String] = []
        var latestLink: String?
        hoverSession.reconcile(
            hosts: [host],
            registration: registration,
            deliver: { link in
                latestLink = link
                if let link {
                    deliveredLinks.append(link)
                }
            }
        )
        deliveredLinks.removeAll()
        latestLink = nil

        canonicalWebView.hoveredLink.update("https://canonical.example/before-reader")
        await drainMainQueue()
        XCTAssertEqual(deliveredLinks, ["https://canonical.example/before-reader"])
        XCTAssertEqual(latestLink, "https://canonical.example/before-reader")

        XCTAssertTrue(host.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceDocument: presentationSourceDocument(
                for: canonicalWebView,
                url: sourceURL
            )
        ))
        let readerWebView = try XCTUnwrap(
            host.activePresentationWebView as? FocusableWKWebView
        )
        await drainMainQueue()

        XCTAssertNil(canonicalWebView.hoveredLink.href)
        XCTAssertNil(latestLink)
        XCTAssertEqual(
            activePresentationIDs,
            [ObjectIdentifier(canonicalWebView), ObjectIdentifier(readerWebView)]
        )

        canonicalWebView.hoveredLink.update("https://canonical.example/hidden-reader")
        await drainMainQueue()
        XCTAssertEqual(deliveredLinks, ["https://canonical.example/before-reader"])
        XCTAssertNil(latestLink)

        readerWebView.hoveredLink.update("https://reader.example/link")
        await drainMainQueue()
        XCTAssertEqual(
            deliveredLinks,
            [
                "https://canonical.example/before-reader",
                "https://reader.example/link",
            ]
        )
        XCTAssertEqual(latestLink, "https://reader.example/link")

        host.dismissReader()
        await drainMainQueue()
        XCTAssertIdentical(host.activePresentationWebView, canonicalWebView)
        XCTAssertNil(latestLink)
        XCTAssertEqual(
            deliveredLinks,
            [
                "https://canonical.example/before-reader",
                "https://reader.example/link",
            ],
            "A hidden canonical hover must not resurface when Reader is dismissed"
        )
        XCTAssertEqual(
            activePresentationIDs,
            [
                ObjectIdentifier(canonicalWebView),
                ObjectIdentifier(readerWebView),
                ObjectIdentifier(canonicalWebView),
            ]
        )

        canonicalWebView.hoveredLink.update("https://canonical.example/after-reader")
        await drainMainQueue()
        XCTAssertEqual(
            deliveredLinks,
            [
                "https://canonical.example/before-reader",
                "https://reader.example/link",
                "https://canonical.example/after-reader",
            ]
        )
        XCTAssertEqual(latestLink, "https://canonical.example/after-reader")

        hoverSession.invalidate()
        presentationObservation.cancel()
        withExtendedLifetime(container) {}
    }

    func testReaderDOMHoverPublishesThroughMinimalPhysicalWebViewScriptAndStopsAfterDismissal()
        async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let firstLinkURL = try XCTUnwrap(URL(string: "https://example.com/reader-first"))
        let canonicalWebView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let host = SumiWebViewContainerView(tabID: UUID(), webView: canonicalWebView)

        XCTAssertTrue(host.presentReader(
            html: """
            <!doctype html>
            <html>
              <body>
                <a id="reader-first" href="/reader-first">First</a>
                <a id="reader-after-dismiss" href="/reader-after-dismiss">Second</a>
              </body>
            </html>
            """,
            sourceDocument: presentationSourceDocument(
                for: canonicalWebView,
                url: sourceURL
            )
        ))
        let readerWebView = try XCTUnwrap(
            host.activePresentationWebView as? FocusableWKWebView
        )
        let readerScripts = readerWebView.configuration.userContentController.userScripts
        XCTAssertEqual(readerScripts.count, 1)
        XCTAssertTrue(readerScripts[0].source.contains("__sumiLinkInteractionInstalled"))
        XCTAssertFalse(readerScripts[0].source.contains("__sumiTabSuspension"))
        let readerLinkInteractionReady = await waitForReaderLinkInteraction(on: readerWebView)
        XCTAssertTrue(readerLinkInteractionReady)

        let hoverDelivered = expectation(description: "Reader DOM hover reached physical WebView state")
        let hoverObservation = readerWebView.hoveredLink.observe { href in
            if href == firstLinkURL.absoluteString {
                hoverDelivered.fulfill()
            }
        }

        try await dispatchMouseOver(elementID: "reader-first", in: readerWebView)
        await fulfillment(of: [hoverDelivered], timeout: 5)
        XCTAssertEqual(readerWebView.hoveredLink.href, firstLinkURL.absoluteString)
        XCTAssertNil(canonicalWebView.hoveredLink.href)

        host.dismissReader()
        XCTAssertNil(readerWebView.hoveredLink.href)

        let detachedHandlerDidNotPublish = expectation(
            description: "Dismissed Reader handler stays detached"
        )
        detachedHandlerDidNotPublish.isInverted = true
        let postDismissObservation = readerWebView.hoveredLink.observe { href in
            if href != nil {
                detachedHandlerDidNotPublish.fulfill()
            }
        }
        do {
            _ = try await dispatchMouseOver(
                elementID: "reader-after-dismiss",
                in: readerWebView
            )
        } catch {
            // A detached Reader may already have stopped its WebContent process.
        }
        await fulfillment(of: [detachedHandlerDidNotPublish], timeout: 0.5)
        XCTAssertNil(readerWebView.hoveredLink.href)
        withExtendedLifetime((hoverObservation, postDismissObservation)) {}
    }

    func testCompositorFocusRestorationTargetsActiveReaderPresentation() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let windowState = BrowserWindowState()
        let browserContext = ReaderFocusBrowserContext()
        let browserManager = BrowserManager()
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let canonicalWebView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let tab = Tab(
            url: sourceURL,
            existingWebView: canonicalWebView,
            webViewSessions: webViewRuntime.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        canonicalWebView.owningTab = tab
        webViewRuntime.trackedWebViewAdmission.attemptAssignment(
            canonicalWebView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        browserContext.tabsByID[tab.id] = tab

        let promotedHost = SumiWebViewContainerView(
            tabID: tab.id,
            webView: canonicalWebView
        )
        XCTAssertTrue(promotedHost.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceDocument: presentationSourceDocument(
                for: canonicalWebView,
                url: sourceURL
            )
        ))
        let readerWebView = promotedHost.activePresentationWebView

        let hostingController = NSHostingController(
            rootView: compositorWrapper(
                browserContext: browserContext,
                browserManager: browserManager,
                webViewRuntime: webViewRuntime,
                windowState: windowState
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }

        let compositorRegistered = await waitUntil {
            webViewRuntime.compositorRuntime.containerView(for: windowState.id) != nil
        }
        XCTAssertTrue(compositorRegistered)
        var promotionAttached = false
        XCTAssertTrue(webViewRuntime.compositorRuntime.registerPromotedHost(
            promotedHost,
            for: tab.id,
            in: windowState.id,
            attachmentCompletion: { outcome in
                promotionAttached = outcome == .attached
            }
        ))

        browserContext.currentTab = tab
        hostingController.rootView = compositorWrapper(
            browserContext: browserContext,
            browserManager: browserManager,
            webViewRuntime: webViewRuntime,
            windowState: windowState
        )

        let promotionCompleted = await waitUntil {
            promotionAttached && promotedHost.window === window
        }
        XCTAssertTrue(promotionCompleted)
        let readerFocused = await waitUntil {
            window.firstResponder === readerWebView
        }
        XCTAssertTrue(readerFocused)
        XCTAssertIdentical(promotedHost.activePresentationWebView, readerWebView)
        XCTAssertTrue(canonicalWebView.isHidden)
        XCTAssertFalse(window.firstResponder === canonicalWebView)
    }

    func testMediaTouchBarRecoveryRestoresFocusToActiveReaderPresentation() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let windowState = BrowserWindowState()
        let browserContext = ReaderFocusBrowserContext()
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let canonicalWebView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration()
        )
        let tab = Tab(
            url: sourceURL,
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false
        )
        browserContext.currentTab = tab
        browserContext.tabsByID[tab.id] = tab

        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)
        XCTAssertTrue(host.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceDocument: presentationSourceDocument(
                for: canonicalWebView,
                url: sourceURL
            )
        ))
        let readerWebView = host.activePresentationWebView
        let hostRegistry = WindowWebContentHostRegistry()
        hostRegistry.setHost(host, for: .single)

        let window = ReaderFocusTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let recoveryReady = await waitUntil {
            host.window === window
                && readerWebView.window === window
        }
        XCTAssertTrue(recoveryReady)

        let registration = webViewRuntime.compositorRuntime.registerContainer(
            host,
            for: windowState.id
        )
        let mutationGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        mutationGate.activate(registration)
        let restoration = WindowMediaTouchBarRestorationService(
            windowID: windowState.id,
            windowState: windowState,
            browserContext: browserContext,
            hostRegistry: hostRegistry,
            mutationGate: mutationGate,
            protectionRuntime: webViewRuntime.protectionRuntime,
            window: { window },
            restoreDisplayedHost: { _, _ in
                XCTFail("The already displayed Reader host should not be restored")
                return false
            }
        )

        window.makeFirstResponder(nil)
        restoration.recover(tabID: tab.id, webView: canonicalWebView)

        XCTAssertIdentical(host.activePresentationWebView, readerWebView)
        XCTAssertTrue(canonicalWebView.isHidden)
        XCTAssertIdentical(window.firstResponder, readerWebView)
        XCTAssertFalse(window.firstResponder === canonicalWebView)
    }

    func testReaderPresentationTransfersToNewHostWithoutStaleOwnerSideEffects() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let canonicalWebView = WKWebView()
        let firstHost = SumiWebViewContainerView(tabID: UUID(), webView: canonicalWebView)
        let lease = documentLease(for: canonicalWebView, url: sourceURL)
        XCTAssertTrue(firstHost.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceDocument: presentationSourceDocument(
                for: canonicalWebView,
                url: sourceURL,
                lease: lease
            )
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
        transaction: TabMainFrameRuntimeTransaction,
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
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            committedURL: url
        ) else {
            XCTFail("Expected the committed reader document to publish")
            return navigationLifetime
        }
        XCTAssertNotNil(tab.committedDocumentRuntime.lease(for: webView))
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

    private func presentationSourceDocument(
        for webView: WKWebView,
        url: URL,
        lease: TabMainFrameDocumentLease? = nil,
        remoteResourcePolicy: SumiReaderRemoteResourcePolicy = .denyRemoteResources,
        routeWebLink: @escaping SumiReaderSourceDocument.RouteWebLink = {
            _, _ in
            XCTFail("Reader web-link routing was not requested")
            return false
        },
        routeExternalLink: @escaping SumiReaderSourceDocument.RouteExternalLink = {
            _ in XCTFail("Reader external-link routing was not requested")
        }
    ) -> SumiReaderSourceDocument {
        let lease = lease ?? documentLease(for: webView, url: url)
        return SumiReaderSourceDocument(
            webView: webView,
            lease: lease,
            sourceURL: url,
            remoteResourcePolicy: remoteResourcePolicy,
            currentLease: { lease },
            routeWebLink: routeWebLink,
            routeExternalLink: routeExternalLink
        )
    }

    private func readerNavigationAction(
        _ destinationURL: URL,
        in webView: WKWebView,
        navigationType: WKNavigationType,
        targetsNewWindow: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> WKNavigationAction {
        let sourceURL = webView.url ?? destinationURL
        let securityOrigin = SumiWKSecurityOriginMock.new(url: sourceURL)
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: true,
            request: URLRequest(url: sourceURL),
            securityOrigin: securityOrigin,
            webView: webView
        ).frameInfo
        let targetFrame = targetsNewWindow ? nil : SumiWKFrameInfoMock(
            isMainFrame: true,
            request: URLRequest(url: destinationURL),
            securityOrigin: securityOrigin,
            webView: webView
        ).frameInfo
        let mock = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            navigationType: navigationType,
            request: URLRequest(url: destinationURL)
        )
        mock.isUserInitiated = navigationType == .linkActivated
        mock.modifierFlags = modifierFlags
        return mock.navigationAction
    }

    private func decideReaderPolicy(
        session: ReaderPresentationSession,
        action: WKNavigationAction
    ) -> WKNavigationActionPolicy {
        var decision: WKNavigationActionPolicy?
        session.webView(
            session.webView,
            decidePolicyFor: action,
            decisionHandler: { decision = $0 }
        )
        return decision ?? .cancel
    }

    private func compositorWrapper(
        browserContext: ReaderFocusBrowserContext,
        browserManager: BrowserManager,
        webViewRuntime: WebViewRuntimeGraph,
        windowState: BrowserWindowState
    ) -> TabCompositorWrapper {
        TabCompositorWrapper(
            browserContext: browserContext,
            resolveDragTab: { _ in nil },
            splitQuery: browserManager.splitWindowContext.query,
            splitPreviews: browserManager.splitWindowContext.previews,
            splitLayout: browserManager.splitWindowContext.layout,
            splitDrops: browserManager.splitWindowContext.drops,
            splitDropTargets: browserManager.splitWindowContext.dropTargets,
            sidebarDragState: browserContext.sidebarDragState,
            webViewOwnershipQuery: webViewRuntime.ownershipQuery,
            trackedWebViewAdmission: webViewRuntime.trackedWebViewAdmission,
            webViewCompositorRuntime: webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: webViewRuntime.protectionRuntime,
            hoveredLink: .constant(nil),
            splitPresentation: nil,
            isSplitDropCaptureActive: false,
            chromeGeometry: BrowserChromeGeometry(),
            windowState: windowState,
            contentBackgroundColor: .white
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            await drainMainQueue()
        }
        return condition()
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

    private func waitForReaderLinkInteraction(
        on webView: WKWebView
    ) async -> Bool {
        if await hasReaderLinkInteraction(on: webView) {
            return true
        }

        guard webView.isLoading else { return false }
        let loadFinished = keyValueObservingExpectation(
            for: webView,
            keyPath: #keyPath(WKWebView.loading)
        ) { object, _ in
            (object as? WKWebView)?.isLoading == false
        }
        await fulfillment(of: [loadFinished], timeout: 5)
        return await hasReaderLinkInteraction(on: webView)
    }

    private func hasReaderLinkInteraction(on webView: WKWebView) async -> Bool {
        do {
            let value = try await webView.evaluateJavaScript(
                "Boolean(window.__sumiLinkInteractionInstalled)",
                in: nil,
                contentWorld: .defaultClient
            )
            return value as? Bool == true
        } catch {
            return false
        }
    }

    private func dispatchMouseOver(
        elementID: String,
        in webView: WKWebView
    ) async throws {
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
                const target = document.getElementById("\(elementID)");
                if (!target) { throw new Error("Missing Reader link target"); }
                target.dispatchEvent(new MouseEvent("mouseover", {
                    bubbles: true,
                    cancelable: true,
                    view: window
                }));
            })();
            """,
            in: nil,
            contentWorld: .defaultClient
        )
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class ReaderFocusBrowserContext: WindowWebContentBrowserContext {
    let sidebarDragState = SidebarDragState()
    var currentTab: Tab?
    var tabsByID: [UUID: Tab] = [:]

    func currentTab(for _: BrowserWindowState) -> Tab? {
        currentTab
    }

    func tab(for tabId: UUID) -> Tab? {
        tabsByID[tabId]
    }

    func schedulePrepareVisibleWebViews(for _: BrowserWindowState) { /* No-op. */ }

    func enqueueWindowMutationDuringHistorySwipe(
        _: HistorySwipeDeferredWindowMutationKind,
        for _: BrowserWindowState
    ) { /* No-op. */ }
}

private final class ReaderFocusTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
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
