import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserZoomCommandOwnerTests: XCTestCase {
    func testZoomInActiveTabSavesProfileScopedBaseZoomAppliesBoostAndPresentsNotification()
        throws {
        let zoomManager = makeZoomManager()
        let profileID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let boosts = try makeBoostsModule(
            sizeOverride: 2,
            url: url,
            profileID: profileID
        )
        let fixture = makeOwner(
            zoomManager: zoomManager,
            boosts: boosts
        )
        let page = installPage(
            in: fixture,
            url: url,
            profileID: profileID,
            makeActive: true
        )

        fixture.owner.zoomInCurrentTab()

        XCTAssertEqual(
            zoomManager.getZoomLevel(
                for: "example.com",
                profileId: profileID
            ),
            1.15,
            accuracy: 0.001
        )
        XCTAssertEqual(page.webView.pageZoom, 2.3, accuracy: 0.001)
        XCTAssertEqual(
            zoomManager.getZoomLevel(for: page.tab.id),
            2.3,
            accuracy: 0.001
        )
        XCTAssertEqual(fixture.revision.revision, 1)
        XCTAssertEqual(fixture.notifications.presentNotificationCalls.count, 1)
        XCTAssertEqual(
            fixture.notifications.presentNotificationCalls.first?.0.messageKey,
            "zoom"
        )
        XCTAssertEqual(
            fixture.notifications.presentNotificationCalls.first?.0.title,
            "Zoom"
        )
        XCTAssertEqual(
            fixture.notifications.presentNotificationCalls.first?.0.controls?
                .count,
            3
        )
        XCTAssertEqual(
            fixture.notifications.presentNotificationCalls.first?.1?.id,
            page.window.id
        )
    }

    func testLoadZoomForTabUsesContainingWindowBeforeActiveWindowAndDoesNotPresentNotification()
        throws {
        let zoomManager = makeZoomManager()
        let profileID = UUID()
        let fixture = makeOwner(zoomManager: zoomManager)
        let activePage = installPage(
            in: fixture,
            url: try XCTUnwrap(URL(string: "https://active.example/page")),
            profileID: profileID,
            makeActive: true
        )
        let targetPage = installPage(
            in: fixture,
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            profileID: profileID,
            makeActive: false
        )
        zoomManager.saveZoomLevel(
            1.5,
            for: "example.com",
            profileId: profileID
        )

        fixture.owner.loadZoomForTab(targetPage.tab.id)

        XCTAssertEqual(targetPage.webView.pageZoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(activePage.webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(
            zoomManager.getZoomLevel(for: targetPage.tab.id),
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(fixture.revision.revision, 1)
        XCTAssertTrue(fixture.notifications.presentNotificationCalls.isEmpty)
    }

    func testZoomTargetsReaderPresentationWithoutMutatingHiddenCanonicalWebView()
        throws {
        let zoomManager = makeZoomManager()
        let fixture = makeOwner(zoomManager: zoomManager)
        let page = installPage(
            in: fixture,
            url: try XCTUnwrap(URL(string: "https://example.com/article")),
            profileID: nil,
            makeActive: true
        )
        let host = SumiWebViewContainerView(
            tabID: page.tab.id,
            webView: page.webView
        )
        let lease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(page.webView),
            participantID: UUID(),
            committedURL: page.tab.url,
            presentationURL: page.tab.url,
            isPDF: false,
            isAuthority: true
        )
        XCTAssertTrue(
            host.presentReader(
                html: "<html><body><article>Reader</article></body></html>",
                sourceDocument: SumiReaderSourceDocument(
                    webView: page.webView,
                    lease: lease,
                    sourceURL: page.tab.url,
                    remoteResourcePolicy: .denyRemoteResources,
                    currentLease: { lease },
                    routeWebLink: { _, _ in false },
                    routeExternalLink: { _ in }
                )
            )
        )

        fixture.owner.zoomInCurrentTab()

        XCTAssertEqual(
            host.activePresentationWebView.pageZoom,
            1.15,
            accuracy: 0.001
        )
        XCTAssertEqual(page.webView.pageZoom, 1, accuracy: 0.001)
    }

    func testCleanupRemovesTabZoomAndPublishesRevision() {
        let zoomManager = makeZoomManager()
        let fixture = makeOwner(zoomManager: zoomManager)
        let tabID = UUID()
        let webView = WKWebView()
        zoomManager.applyTransientZoom(
            1.5,
            to: webView,
            domain: "example.com",
            tabId: tabID
        )

        fixture.owner.cleanupZoomForTab(tabID)

        XCTAssertEqual(
            zoomManager.getZoomLevel(for: tabID),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(fixture.revision.revision, 1)
    }

    private func makeOwner(
        zoomManager: ZoomManager,
        boosts: SumiBoostsModule? = nil
    ) -> ZoomOwnerFixture {
        let windows = WindowRegistry()
        let browser = BrowserManager(windowRegistry: windows)
        let revision = BrowserZoomRevisionState()
        let notifications = NotificationPresentingSpy()
        let owner = BrowserZoomCommandOwner(
            windows: windows,
            targets: BrowserZoomTargetResolver(
                activePages: browser.shellRuntime.activePageResolver,
                tabs: browser.tabCollectionMembershipOwner,
                windowTabs: browser.shellRuntime.windowTabs,
                webViews: browser.webViewRoutingService
            ),
            policy: BrowserZoomPolicy(
                manager: zoomManager,
                boosts: boosts ?? makeDisabledBoostsModule()
            ),
            publication: BrowserZoomPublication(
                revision: revision,
                notifications: notifications
            )
        )
        return ZoomOwnerFixture(
            browser: browser,
            windows: windows,
            revision: revision,
            notifications: notifications,
            owner: owner
        )
    }

    private func installPage(
        in fixture: ZoomOwnerFixture,
        url: URL,
        profileID: UUID?,
        makeActive: Bool
    ) -> ZoomPageFixture {
        let space = installTestSpace(
            in: fixture.browser.spaceStateOwner,
            name: "Zoom",
            profileID: profileID
        )
        let tab = fixture.browser.regularTabLifecycleOwner.createNewTab(
            url: url.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profileID
        let window = BrowserWindowState()
        fixture.browser.tabResidenceAuthority.establishResidenceSession(
            on: window
        )
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        window.currentTabId = tab.id
        fixture.windows.register(window)
        if makeActive {
            fixture.windows.setActive(window)
        }
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let admission = fixture.browser.webViewRuntime.trackedWebViewAdmission
            .attemptAssignment(
                webView,
                to: tab,
                in: window.id,
                replaySemanticOperation: {
                    XCTFail("Unexpected WebView placement deferral")
                }
            )
        XCTAssertTrue(admission.isAccepted)
        return ZoomPageFixture(
            tab: tab,
            webView: webView,
            window: window
        )
    }

    private func makeBoostsModule(
        sizeOverride: Double,
        url: URL,
        profileID: UUID
    ) throws -> SumiBoostsModule {
        let defaults = TestDefaultsHarness()
        addTeardownBlock { defaults.reset() }
        let modules = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: defaults.defaults
            )
        )
        modules.enable(.boosts)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserZoomCommandOwnerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let store = SumiBoostStore(rootDirectory: root)
        let boost = try store.createDraft(
            for: url,
            profileId: profileID,
            isEphemeral: true
        )
        _ = try store.updateBoost(
            id: boost.id,
            profileId: profileID,
            host: boost.host,
            isEphemeral: true
        ) { data in
            data.sizeOverride = sizeOverride
        }
        return SumiBoostsModule(
            moduleRegistry: modules,
            storeFactory: { store }
        )
    }

    private func makeDisabledBoostsModule() -> SumiBoostsModule {
        SumiBoostsModule(
            moduleRegistry: .unavailable(),
            storeFactory: {
                preconditionFailure("Disabled boosts must remain zero-cost")
            }
        )
    }

    private func makeZoomManager(function: String = #function) -> ZoomManager {
        let suiteName = "BrowserZoomCommandOwnerTests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ZoomManager(userDefaults: defaults)
    }
}

@MainActor
private struct ZoomOwnerFixture {
    let browser: BrowserManager
    let windows: WindowRegistry
    let revision: BrowserZoomRevisionState
    let notifications: NotificationPresentingSpy
    let owner: BrowserZoomCommandOwner
}

@MainActor
private struct ZoomPageFixture {
    let tab: Tab
    let webView: FocusableWKWebView
    let window: BrowserWindowState
}
