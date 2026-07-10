import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewCreationPlannerTests: XCTestCase {
    func testCreationPlanCreatesPrimaryWhenWarmupRuntimeUnavailable() {
        let planner = WebViewCreationPlanner()
        let tab = makeWarmupTab()

        let plan = planner.creationPlan(
            for: tab,
            in: UUID(),
            initialDocumentWarmupRuntime: nil,
            existingWebView: nil,
            windowWebViews: [:]
        )

        guard case .createPrimary = plan else {
            return XCTFail("Expected primary creation without a warmup runtime")
        }
    }

    func testCreationPlanAdoptsUntrackedWebViewWhenWindowSetIsEmpty() {
        let planner = WebViewCreationPlanner()
        let tab = makeWarmupTab()
        let targetWindowId = UUID()
        let webView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(webView)

        let plan = planner.creationPlan(
            for: tab,
            in: targetWindowId,
            initialDocumentWarmupRuntime: nil,
            existingWebView: nil,
            windowWebViews: [:]
        )

        guard case let .adoptExistingPrimary(adoptedWebView) = plan else {
            return XCTFail("Expected adoption of the untracked WebView")
        }
        XCTAssertIdentical(adoptedWebView, webView)
    }

    func testCreationPlanChoosesDeterministicClonePrimaryFromWindowSet() {
        let planner = WebViewCreationPlanner()
        let tab = makeWarmupTab()
        let targetWindowId = UUID()
        let stableRegistryWindowId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterRegistryWindowId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let plan = planner.creationPlan(
            for: tab,
            in: targetWindowId,
            initialDocumentWarmupRuntime: nil,
            existingWebView: nil,
            windowWebViews: [
                laterRegistryWindowId: WKWebView(frame: .zero),
                stableRegistryWindowId: WKWebView(frame: .zero),
            ]
        )

        guard case let .createClone(primaryWindowId) = plan else {
            return XCTFail("Expected clone creation from registry-owned WebViews")
        }
        XCTAssertEqual(primaryWindowId, stableRegistryWindowId)
    }

    func testCreationPlanStartsWarmupAndWaitsWhileInFlight() {
        let planner = WebViewCreationPlanner()
        let expectedProfileId = UUID()
        let tab = makeWarmupTab(profileId: expectedProfileId)
        let windowId = UUID()
        var requestedProfileIds: [UUID] = []
        let runtime = makeWarmupRuntime(
            needsInitialDocumentExtensionContextLoad: { profileId in
                requestedProfileIds.append(profileId)
                return true
            }
        )

        let firstPlan = planner.creationPlan(
            for: tab,
            in: windowId,
            initialDocumentWarmupRuntime: runtime,
            existingWebView: nil,
            windowWebViews: [:]
        )
        guard case let .deferForInitialDocumentWarmup(.start(profileId, deferredWindowId)) = firstPlan else {
            return XCTFail("Expected first warmup plan to start")
        }

        let secondPlan = planner.creationPlan(
            for: tab,
            in: windowId,
            initialDocumentWarmupRuntime: runtime,
            existingWebView: nil,
            windowWebViews: [:]
        )

        XCTAssertEqual(profileId, expectedProfileId)
        XCTAssertEqual(deferredWindowId, windowId)
        XCTAssertEqual(requestedProfileIds, [expectedProfileId])
        guard case .deferForInitialDocumentWarmup(.waitForInFlight) = secondPlan else {
            return XCTFail("Expected second warmup plan to wait for the in-flight profile")
        }
    }

    func testStartInitialDocumentWarmupUsesRuntimeAndAllowsFuturePrimaryCreation() async {
        let planner = WebViewCreationPlanner()
        let expectedProfileId = UUID()
        let tab = makeWarmupTab(profileId: expectedProfileId)
        let windowId = UUID()
        let ensureExpectation = expectation(description: "ensure initial document runtime")
        let refreshExpectation = expectation(description: "refresh compositor")
        var ensuredProfileIds: [UUID] = []
        var refreshedWindowIds: [UUID] = []

        let runtime = makeWarmupRuntime(
            needsInitialDocumentExtensionContextLoad: { _ in true },
            ensureInitialExtensionContextsLoaded: { profileId in
                ensuredProfileIds.append(profileId)
                ensureExpectation.fulfill()
            },
            refreshCompositorForWindow: { refreshedWindowId in
                refreshedWindowIds.append(refreshedWindowId)
                refreshExpectation.fulfill()
            }
        )

        let plan = planner.creationPlan(
            for: tab,
            in: windowId,
            initialDocumentWarmupRuntime: runtime,
            existingWebView: nil,
            windowWebViews: [:]
        )
        guard case let .deferForInitialDocumentWarmup(deferral) = plan else {
            return XCTFail("Expected warmup deferral")
        }

        planner.startInitialDocumentWarmupIfNeeded(deferral, runtime: runtime)

        await fulfillment(of: [ensureExpectation, refreshExpectation], timeout: 1.0)
        XCTAssertEqual(ensuredProfileIds, [expectedProfileId])
        XCTAssertEqual(refreshedWindowIds, [windowId])

        let nextPlan = planner.creationPlan(
            for: tab,
            in: windowId,
            initialDocumentWarmupRuntime: runtime,
            existingWebView: nil,
            windowWebViews: [:]
        )
        guard case .createPrimary = nextPlan else {
            return XCTFail("Expected primary creation after warmup attempt finishes")
        }
    }

    private func makeWarmupTab(profileId: UUID = UUID()) -> Tab {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profileId
        return tab
    }

    private func makeWarmupRuntime(
        needsInitialDocumentExtensionContextLoad: @escaping @MainActor (UUID) -> Bool = { _ in false },
        ensureInitialExtensionContextsLoaded: @escaping @MainActor (UUID) async -> Void = { _ in /* No-op. */ },
        refreshCompositorForWindow: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ }
    ) -> InitialDocumentWarmupRuntime {
        InitialDocumentWarmupRuntime(
            needsInitialDocumentExtensionContextLoad: needsInitialDocumentExtensionContextLoad,
            ensureInitialExtensionContextsLoaded: ensureInitialExtensionContextsLoaded,
            refreshCompositorForWindow: refreshCompositorForWindow
        )
    }
}
