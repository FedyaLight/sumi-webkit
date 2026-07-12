import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class DeferredWebViewCommandAuthorityTests: XCTestCase {
    func testRemoveWebViewFromContainersRequiresResolvableWebView() {
        let fixture = Fixture()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let command = DeferredWebViewCommand.removeWebViewFromContainers(
            webViewID: webViewID
        )

        XCTAssertNil(fixture.authority.prepare(command))
        fixture.mediaProtection.note(webView)

        guard case .removeWebViewFromContainers(let preparedWebView)? =
                fixture.authority.prepare(command) else {
            return XCTFail("Expected resolved container-removal command")
        }
        XCTAssertIdentical(preparedWebView, webView)
    }

    func testRemoveTrackedWebViewRequiresExactTrackedOwner() {
        let fixture = Fixture()
        let webView = WKWebView()
        let tabID = UUID()
        let windowID = UUID()
        fixture.track(webView, tabID: tabID, windowID: windowID)

        XCTAssertNil(fixture.authority.prepare(.removeTrackedWebView(
            webViewID: ObjectIdentifier(webView),
            tabID: tabID,
            windowID: UUID()
        )))

        guard case .removeTrackedWebView(
            let preparedWebView,
            let owner,
            let preparedTab
        )? =
                fixture.authority.prepare(.removeTrackedWebView(
                    webViewID: ObjectIdentifier(webView),
                    tabID: tabID,
                    windowID: windowID
                )) else {
            return XCTFail("Expected exact tracked-removal command")
        }
        XCTAssertIdentical(preparedWebView, webView)
        XCTAssertEqual(owner, TrackedWebViewOwner(tabID: tabID, windowID: windowID))
        XCTAssertNil(preparedTab)
    }

    func testCloseWebViewFromWebKitRequiresResolvableWebView() {
        let fixture = Fixture()
        let webView = WKWebView()
        let command = DeferredWebViewCommand.closeWebViewFromWebKit(
            webViewID: ObjectIdentifier(webView)
        )

        XCTAssertNil(fixture.authority.prepare(command))
        fixture.mediaProtection.note(webView)

        guard case .closeWebViewFromWebKit(let preparedWebView)? =
                fixture.authority.prepare(command) else {
            return XCTFail("Expected resolved WebKit-close command")
        }
        XCTAssertIdentical(preparedWebView, webView)
    }

    func testCleanupWindowRequiresTrackedWebViewOrCompositorContainer() {
        let fixture = Fixture()
        let windowID = UUID()
        let command = DeferredWebViewCommand.cleanupWindow(windowID: windowID)
        XCTAssertNil(fixture.authority.prepare(command))

        let compositorView = NSView()
        _ = fixture.visibleRuntime.registerCompositorContainerView(
            compositorView,
            for: windowID
        )
        guard case .cleanupWindow(let preparedWindowID)? =
                fixture.authority.prepare(command) else {
            return XCTFail("Expected compositor-backed window cleanup")
        }
        XCTAssertEqual(preparedWindowID, windowID)

        let trackedWindowID = UUID()
        fixture.track(WKWebView(), tabID: UUID(), windowID: trackedWindowID)
        guard case .cleanupWindow(let trackedPreparedWindowID)? =
                fixture.authority.prepare(.cleanupWindow(windowID: trackedWindowID)) else {
            return XCTFail("Expected tracked-WebView-backed window cleanup")
        }
        XCTAssertEqual(trackedPreparedWindowID, trackedWindowID)
    }

    func testCleanupAllWebViewsRequiresTrackedWebViews() {
        let fixture = Fixture()
        XCTAssertNil(fixture.authority.prepare(.cleanupAllWebViews))

        fixture.track(WKWebView(), tabID: UUID(), windowID: UUID())
        guard case .cleanupAllWebViews? =
                fixture.authority.prepare(.cleanupAllWebViews) else {
            return XCTFail("Expected cleanup-all preparation")
        }
    }

    func testRebuildLiveWebViewsRequiresCurrentRebuildRevision() {
        let fixture = Fixture()
        let targetURL = URL(string: "https://example.com/rebuild")!
        let tab = fixture.makeTab(url: targetURL)
        let revision = tab.webViewRebuildEpoch.advance()
        let intent = DeferredWebViewRebuildIntent(
            revision: revision,
            targetURL: targetURL,
            configuration: .normal,
            kind: .semanticNavigation
        )
        let preferredWindowID = UUID()
        let command = DeferredWebViewCommand.rebuildLiveWebViews(
            tabID: tab.id,
            preferredPrimaryWindowID: preferredWindowID,
            intent: intent
        )

        guard case .rebuildLiveWebViews(
            let preparedTab,
            let preparedWindowID,
            let preparedIntent
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected current rebuild preparation")
        }
        XCTAssertIdentical(preparedTab, tab)
        XCTAssertEqual(preparedWindowID, preferredWindowID)
        XCTAssertEqual(preparedIntent, intent)

        _ = tab.webViewRebuildEpoch.advance()
        XCTAssertNil(fixture.authority.prepare(command))
    }

    func testAssignProfileRequiresCurrentProfileIntent() {
        let fixture = Fixture()
        let tab = fixture.makeTab()
        let desiredProfileID = UUID()
        let intent = tab.profileAssignment.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: desiredProfileID,
            targetURL: tab.url,
            requiresStructuralPersistence: false
        )
        let preferredWindowID = UUID()
        let command = DeferredWebViewCommand.assignProfile(
            tabID: tab.id,
            preferredPrimaryWindowID: preferredWindowID,
            intent: intent
        )

        guard case .assignProfile(
            let preparedTab,
            let preparedWindowID,
            let preparedIntent
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected current profile preparation")
        }
        XCTAssertIdentical(preparedTab, tab)
        XCTAssertEqual(preparedWindowID, preferredWindowID)
        XCTAssertEqual(preparedIntent, intent)

        XCTAssertTrue(tab.profileAssignment.replaceCurrentProfileID(UUID()))
        XCTAssertNil(fixture.authority.prepare(command))
    }

    func testAssignProfileRejectsTabThatRemainsRuntimeBoundAfterCollectionRemoval() {
        let fixture = Fixture()
        let tab = fixture.makeTab()
        let profileID = UUID()
        let intent = tab.profileAssignment.begin(
            desiredProfileID: profileID,
            resolvedProfileID: profileID,
            targetURL: tab.url,
            requiresStructuralPersistence: false
        )
        let command = DeferredWebViewCommand.assignProfile(
            tabID: tab.id,
            preferredPrimaryWindowID: nil,
            intent: intent
        )

        XCTAssertNotNil(fixture.authority.prepare(command))
        fixture.tabs.removeFromCollection(tab.id)

        XCTAssertNotNil(fixture.runtimeTabs.boundTab(tab.id))
        XCTAssertNil(fixture.authority.prepare(command))
    }

    func testAssignSpaceProfileRequiresCurrentSpaceIntent() {
        let fixture = Fixture()
        let intent = DeferredWebViewSpaceProfileAssignmentIntent(
            revision: 1,
            spaceID: UUID(),
            expectedProfileID: nil,
            desiredProfileID: UUID(),
            tabIntents: []
        )
        let command = DeferredWebViewCommand.assignSpaceProfile(intent: intent)

        XCTAssertNil(fixture.authority.prepare(command))
        fixture.spaceProfileIntents.currentIntent = intent

        guard case .assignSpaceProfile(let preparedIntent)? =
                fixture.authority.prepare(command) else {
            return XCTFail("Expected current space-profile preparation")
        }
        XCTAssertEqual(preparedIntent, intent)
    }

    func testSynchronizeTrackedNavigationRequiresExactWebViewOwnerAndSemanticIntent() {
        let fixture = Fixture()
        let initialURL = URL(string: "https://example.com/initial")!
        let targetURL = URL(string: "https://example.com/target")!
        let tab = fixture.makeTab(url: initialURL)
        let webView = WKWebView()
        let windowID = UUID()
        fixture.track(webView, tabID: tab.id, windowID: windowID)
        let navigation = tab.beginMainFrameNavigationIntent(to: targetURL)
        let intent = DeferredWebViewNavigationIntent(
            revision: navigation.revision,
            targetURL: targetURL
        )
        let command = DeferredWebViewCommand.synchronizeTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: windowID,
            intent: intent
        )

        XCTAssertNil(fixture.authority.prepare(.synchronizeTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: UUID(),
            intent: intent
        )))
        guard case .synchronizeTrackedNavigation(
            let preparedWebView,
            let preparedTab,
            let owner,
            let preparedIntent
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected exact navigation preparation")
        }
        XCTAssertIdentical(preparedWebView, webView)
        XCTAssertIdentical(preparedTab, tab)
        XCTAssertEqual(owner, TrackedWebViewOwner(tabID: tab.id, windowID: windowID))
        XCTAssertEqual(preparedIntent, intent)

        _ = tab.beginMainFrameNavigationIntent(to: URL(string: "https://example.com/newer")!)
        XCTAssertNil(fixture.authority.prepare(command))
    }

    func testReloadTrackedNavigationRequiresExactWebViewOwnerAndSemanticIntent() {
        let fixture = Fixture()
        let targetURL = URL(string: "https://example.com/reload")!
        let tab = fixture.makeTab(url: targetURL)
        let webView = WKWebView()
        let windowID = UUID()
        fixture.track(webView, tabID: tab.id, windowID: windowID)
        let navigation = tab.beginMainFrameNavigationIntent(to: targetURL)
        let intent = DeferredWebViewReloadIntent(
            revision: navigation.revision,
            targetURL: targetURL,
            policy: .fromOrigin
        )
        let command = DeferredWebViewCommand.reloadTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: windowID,
            intent: intent
        )

        XCTAssertNil(fixture.authority.prepare(.reloadTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: UUID(),
            intent: intent
        )))
        guard case .reloadTrackedNavigation(
            let preparedWebView,
            let preparedTab,
            let owner,
            let preparedIntent
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected exact reload preparation")
        }
        XCTAssertIdentical(preparedWebView, webView)
        XCTAssertIdentical(preparedTab, tab)
        XCTAssertEqual(owner, TrackedWebViewOwner(tabID: tab.id, windowID: windowID))
        XCTAssertEqual(preparedIntent, intent)

        _ = tab.beginMainFrameNavigationIntent(to: URL(string: "https://example.com/newer")!)
        XCTAssertNil(fixture.authority.prepare(command))
    }

    func testEvictHiddenWebViewsRequiresLiveWindow() {
        let fixture = Fixture()
        let windowID = UUID()
        let command = DeferredWebViewCommand.evictHiddenWebViews(windowID: windowID)
        XCTAssertNil(fixture.authority.prepare(command))

        fixture.windows.windowIDs.insert(windowID)
        guard case .evictHiddenWebViews(let preparedWindowID)? =
                fixture.authority.prepare(command) else {
            return XCTFail("Expected live-window eviction preparation")
        }
        XCTAssertEqual(preparedWindowID, windowID)
    }

    func testCleanupTabWebViewRequiresExactDetachedResidence() {
        let fixture = Fixture()
        let tab = fixture.makeTab()
        let webView = WKWebView()
        fixture.webViewSessions.noteUntrackedWebView(webView, for: tab.id)
        let command = DeferredWebViewCommand.cleanupTabWebView(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id
        )

        XCTAssertNil(fixture.authority.prepare(.cleanupTabWebView(
            webViewID: ObjectIdentifier(webView),
            tabID: UUID()
        )))
        guard case .cleanupTabWebView(
            let preparedWebView,
            let preparedTabID,
            let preparedTab
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected exact detached cleanup preparation")
        }
        XCTAssertIdentical(preparedWebView, webView)
        XCTAssertEqual(preparedTabID, tab.id)
        XCTAssertIdentical(preparedTab, tab)
    }

    func testPerformFallbackWebViewCleanupRequiresExactPendingCleanupLease() {
        let fixture = Fixture()
        let tab = fixture.makeTab()
        let webView = WKWebView()
        guard let lease = fixture.webViewSessions.beginPendingCleanup(
            of: webView,
            for: tab.id
        ) else {
            return XCTFail("Expected pending-cleanup lease")
        }
        let command = DeferredWebViewCommand.performFallbackWebViewCleanup(
            webViewID: ObjectIdentifier(webView),
            lease: lease
        )

        XCTAssertNil(fixture.authority.prepare(.performFallbackWebViewCleanup(
            webViewID: ObjectIdentifier(webView),
            lease: WebViewPendingCleanupLease(id: UUID(), tabID: tab.id)
        )))
        guard case .performFallbackWebViewCleanup(
            let preparedWebView,
            let preparedLease,
            let preparedTab
        )? = fixture.authority.prepare(command) else {
            return XCTFail("Expected exact pending-cleanup preparation")
        }
        XCTAssertIdentical(preparedWebView, webView)
        XCTAssertEqual(preparedLease, lease)
        XCTAssertIdentical(preparedTab, tab)
    }
}

@MainActor
private final class DeferredCommandTestTabResolver: DeferredWebViewCommandTabResolving {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private var tabsByID: [UUID: Tab] = [:]

    init(runtimeTabs: WebViewRuntimeTabRegistry) {
        self.runtimeTabs = runtimeTabs
    }

    func bind(_ tab: Tab) {
        tabsByID[tab.id] = tab
        runtimeTabs.bind(tab)
    }

    func removeFromCollection(_ tabID: UUID) {
        tabsByID.removeValue(forKey: tabID)
    }

    func resolveRuntimeTab(with tabID: UUID) -> Tab? {
        runtimeTabs.resolve(tabID) { [tabsByID] in tabsByID[$0] }
    }

    func resolveCollectionTab(with tabID: UUID) -> Tab? {
        tabsByID[tabID]
    }

    func resolveTabForCleanup(with tabID: UUID) -> Tab? {
        runtimeTabs.tabForCleanup(tabID) { [tabsByID] in tabsByID[$0] }
    }
}

@MainActor
private final class DeferredCommandTestWindowQuery: DeferredWebViewCommandWindowQuerying {
    var windowIDs: Set<UUID> = []

    func containsWindow(with windowID: UUID) -> Bool {
        windowIDs.contains(windowID)
    }
}

@MainActor
private final class DeferredCommandTestSpaceIntentValidator:
    DeferredWebViewSpaceProfileIntentValidating {
    var currentIntent: DeferredWebViewSpaceProfileAssignmentIntent?

    func isCurrent(_ intent: DeferredWebViewSpaceProfileAssignmentIntent) -> Bool {
        intent == currentIntent
    }
}

@MainActor
private final class Fixture {
    let webViewSessions = WebViewSessionRepository()
    let mediaProtection = WebViewMediaProtectionOwner()
    let visibleRuntime = VisibleWebViewRuntimeOwner()
    let windows = DeferredCommandTestWindowQuery()
    let spaceProfileIntents = DeferredCommandTestSpaceIntentValidator()
    let runtimeTabs: WebViewRuntimeTabRegistry
    let tabs: DeferredCommandTestTabResolver
    let webViews: WebViewRuntimeWebViewResolver
    let authority: DeferredWebViewCommandAuthority

    init() {
        let runtimeTabs = WebViewRuntimeTabRegistry(webViewSessions: webViewSessions)
        let tabs = DeferredCommandTestTabResolver(runtimeTabs: runtimeTabs)
        let webViews = WebViewRuntimeWebViewResolver(
            sessions: webViewSessions,
            mediaProtection: mediaProtection
        )
        self.runtimeTabs = runtimeTabs
        self.tabs = tabs
        self.webViews = webViews
        authority = DeferredWebViewCommandAuthority(
            webViews: webViews,
            webViewSessions: webViewSessions,
            tabs: tabs,
            tabScopedCleanupValidation: WebViewTabScopedCleanupValidationOwner(),
            visibleRuntime: visibleRuntime,
            windows: windows,
            spaceProfileIntents: spaceProfileIntents
        )
    }

    func makeTab(url: URL = URL(string: "about:blank")!) -> Tab {
        let tab = Tab(url: url, webViewSessions: webViewSessions)
        tabs.bind(tab)
        return tab
    }

    func track(_ webView: WKWebView, tabID: UUID, windowID: UUID) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: TrackedWebViewOwner(tabID: tabID, windowID: windowID),
            in: webViewSessions,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }
}
