import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewRuntimeGraphTrackedWebViewsTests: XCTestCase {
    func testDetachedInstallationRejectsSameIDTabBeforeResidenceMutation()
        throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tabID = UUID()
        let canonical = Tab(
            id: tabID,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let conflicting = Tab(
            id: tabID,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertEqual(graph.runtimeTabs.bind(canonical), .bound)
        let candidate = WKWebView()
        let generation = graph.webViewSessions.residenceGeneration

        XCTAssertEqual(
            graph.untrackedWebViewInstallationService.installUntracked(
                candidate,
                for: conflicting
            ),
            .rejected(
                .runtimeTabIdentityConflict,
                webViewDisposition: .callerMustDestroy
            )
        )
        XCTAssertEqual(graph.webViewSessions.residenceGeneration, generation)
        XCTAssertNil(graph.webViewSessions.residence(of: candidate))
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), canonical)
    }

    func testSameIDConflictPreservesAlreadyCanonicalCandidate() {
        let graph = makeTestWebViewRuntimeGraph()
        let tabID = UUID()
        let canonical = Tab(
            id: tabID,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let conflicting = Tab(
            id: tabID,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertEqual(graph.runtimeTabs.bind(canonical), .bound)
        let candidate = WKWebView()
        conflicting.webViewSession.park(candidate)
        let generation = graph.webViewSessions.residenceGeneration

        XCTAssertEqual(
            graph.untrackedWebViewInstallationService.installUntracked(
                candidate,
                for: conflicting
            ),
            .rejected(
                .runtimeTabIdentityConflict,
                webViewDisposition: .remainsCanonical
            )
        )
        XCTAssertEqual(graph.webViewSessions.residenceGeneration, generation)
        XCTAssertEqual(
            graph.webViewSessions.residence(of: candidate),
            .parked(tabID: tabID)
        )
        XCTAssertIdentical(canonical.webViewSession.parkedWebView, candidate)
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), canonical)
    }

    func testDetachedInstallationCannotRecreateRetiredResidence() {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .bound)
        XCTAssertTrue(graph.runtimeTabs.beginRetirement(tab))
        XCTAssertTrue(graph.runtimeTabs.finishRetirementIfDrained(tab.id))
        let candidate = WKWebView()

        XCTAssertEqual(
            graph.untrackedWebViewInstallationService.installUntracked(
                candidate,
                for: tab
            ),
            .rejected(
                .runtimeTabIdentityConflict,
                webViewDisposition: .callerMustDestroy
            )
        )
        XCTAssertNil(graph.webViewSessions.residence(of: candidate))
        XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
    }

    func testAuxiliaryTrackedPlacementReturnsTypedWrongFamilyRejection() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/rejected")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        let windowID = UUID()

        XCTAssertEqual(
            graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: tab,
                in: windowID
            ),
            .placed(.rejected(.wrongSurfaceFamily))
        )
        XCTAssertNil(graph.ownershipQuery.webView(for: tab.id, in: windowID))
        XCTAssertFalse(tab.webViewSession.owns(webView))
    }

    func testAuxiliaryTrackedPlacementRejectsMismatchedPhysicalTabBeforeMutation()
        throws {
        let graph = makeTestWebViewRuntimeGraph()
        let expectedTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/expected")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let differentTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/different")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView()
        webView.owningTab = differentTab
        let windowID = UUID()
        let generationBeforeAdmission = graph.webViewSessions
            .residenceGeneration

        XCTAssertEqual(
            graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: expectedTab,
                in: windowID
            ),
            .rejected(.physicalTabIdentityMismatch)
        )

        XCTAssertEqual(
            graph.webViewSessions.residenceGeneration,
            generationBeforeAdmission
        )
        XCTAssertNil(graph.runtimeTabs.boundTab(expectedTab.id))
        XCTAssertNil(
            graph.ownershipQuery.webView(
                for: expectedTab.id,
                in: windowID
            )
        )
        XCTAssertFalse(expectedTab.webViewSession.owns(webView))
    }

    func testTrackedAssignmentRejectsPlainWebViewBeforeMutation() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/plain")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        let windowID = UUID()
        let generationBeforeAdmission = graph.webViewSessions
            .residenceGeneration

        XCTAssertEqual(
            graph.trackedWebViewAdmission.attemptAssignment(
                webView,
                to: tab,
                in: windowID,
                replaySemanticOperation: {
                    XCTFail("Unexpected WebView deferral")
                }
            ),
            .rejected(.physicalTabIdentityMismatch)
        )

        XCTAssertEqual(
            graph.webViewSessions.residenceGeneration,
            generationBeforeAdmission
        )
        XCTAssertNil(graph.runtimeTabs.boundTab(tab.id))
        XCTAssertNil(graph.webViewSessions.residence(of: webView))
        XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
    }

    func testUntrackedInstallationReturnsTypedTrackedResidenceRejection()
        throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/tracked")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let tracked = FocusableWKWebView()
        tracked.owningTab = tab
        let windowID = UUID()
        XCTAssertTrue(
            graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                tracked,
                for: tab,
                in: windowID
            ).isAccepted
        )
        let candidate = WKWebView(frame: .zero)

        XCTAssertEqual(
            graph.untrackedWebViewInstallationService.installUntracked(
                candidate,
                for: tab
            ),
            .rejected(
                .trackedResidenceExists,
                webViewDisposition: .callerMustDestroy
            )
        )
        XCTAssertFalse(tab.webViewSession.owns(candidate))
        XCTAssertIdentical(
            graph.ownershipQuery.webView(for: tab.id, in: windowID),
            tracked
        )
    }

    func testTrackedLiveWebViewsExcludesUntrackedTabWebView() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let untrackedWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untrackedWebView)

        XCTAssertTrue(graph.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testSuspensionLiveWebViewsIncludesCurrentAndParkedUntrackedWebViews() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let parkedWebView = WKWebView(frame: .zero)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            existingWebView: parkedWebView,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let currentWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(currentWebView)

        let liveWebViews = graph.ownershipQuery.suspensionLiveWebViews(for: tab)

        XCTAssertEqual(liveWebViews.count, 2)
        XCTAssertTrue(liveWebViews.contains { $0 === currentWebView })
        XCTAssertTrue(liveWebViews.contains { $0 === parkedWebView })
        XCTAssertTrue(graph.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testTrackedLiveWebViewsReturnsOnlyGraphRegisteredWebViews() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView(frame: .zero))
        let windowId = UUID()
        let trackedWebView = FocusableWKWebView()
        trackedWebView.owningTab = tab

        graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            trackedWebView,
            for: tab,
            in: windowId
        )

        XCTAssertEqual(graph.ownershipQuery.trackedLiveWebViews(for: tab).count, 1)
        XCTAssertIdentical(
            graph.ownershipQuery.trackedLiveWebViews(for: tab).first,
            trackedWebView
        )
    }

    func testEnsureUntrackedOwnedWebViewReturnsExistingLiveWebView() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/ensure-untracked-reuse")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let existing = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        existing.owningTab = tab
        tab.replaceUntrackedWebView(existing)

        let first = try XCTUnwrap(graph.untrackedWebViewMaterialization.webView(for: tab))
        let second = try XCTUnwrap(graph.untrackedWebViewMaterialization.webView(for: tab))

        XCTAssertIdentical(first, existing)
        XCTAssertIdentical(first, second)
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertIdentical(graph.ownershipQuery.untrackedOwnedWebView(for: tab), existing)
    }
}
