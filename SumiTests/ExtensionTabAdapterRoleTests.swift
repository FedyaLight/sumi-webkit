import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionRequestedTabServicesTests {
    func testRetainedTabAdapterFailsClosedAfterExactStoreRetirement()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let adapter = try XCTUnwrap(
            harness.manager.adapterStore.existingTabAdapter(
                for: harness.sourceTab.id
            )
        )
        let originalURL = harness.sourceTab.url

        XCTAssertEqual(
            adapter.url(for: harness.extensionContext),
            originalURL
        )
        XCTAssertTrue(
            adapter.shouldGrantPermissionsOnUserGesture(
                for: harness.extensionContext
            )
        )
        XCTAssertTrue(
            harness.manager.adapterStore.removeTabAdapter(
                for: harness.sourceTab.id,
                ifIdenticalTo: adapter
            )
        )

        XCTAssertNil(adapter.url(for: harness.extensionContext))
        XCTAssertFalse(
            adapter.shouldGrantPermissionsOnUserGesture(
                for: harness.extensionContext
            )
        )

        let completion = expectation(description: "stale adapter rejected")
        var callbackError: NSError?
        adapter.loadURL(
            URL(string: "https://stale.example/rejected")!,
            for: harness.extensionContext
        ) { error in
            callbackError = error as NSError?
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertNotNil(callbackError)
        XCTAssertEqual(harness.sourceTab.url, originalURL)
    }

    func testPromotionInvalidationPreventsSelectionMutation() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let underlyingMutation = try XCTUnwrap(
            harness.manager.extensionTabMutation
        )
        let mutation = ReentrantExtensionTabMutation(
            underlying: underlyingMutation,
            afterPromotion: { [weak manager = harness.manager] tab in
                manager?.adapterStore.removeTabAdapter(for: tab.id)
            }
        )
        let adapter = try replacePublishedAdapter(
            in: harness,
            tabMutation: mutation,
            webViews: harness.manager.tabWebViewResolver
        )

        let completion = expectation(description: "reentrant activation rejected")
        var callbackError: NSError?
        adapter.activate(for: harness.extensionContext) { error in
            callbackError = error as NSError?
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(mutation.selectionCount, 0)
        XCTAssertNotNil(callbackError)
    }

    func testWebViewResolutionInvalidationPreventsStaleZoomMutation()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let underlyingMutation = try XCTUnwrap(
            harness.manager.extensionTabMutation
        )
        let webView = try XCTUnwrap(
            harness.browserManager.webViewRuntime.ownershipQuery.webView(
                for: harness.sourceTab.id,
                in: harness.window.id
            )
        )
        let originalZoom = webView.pageZoom
        let webViews = ReentrantExtensionTabWebViewQuery(
            webView: webView,
            duringResolution: { [weak manager = harness.manager] tab in
                manager?.adapterStore.removeTabAdapter(for: tab.id)
            }
        )
        let adapter = try replacePublishedAdapter(
            in: harness,
            tabMutation: underlyingMutation,
            webViews: webViews
        )

        let completion = expectation(description: "stale WebView rejected")
        var callbackError: NSError?
        adapter.setZoomFactor(
            originalZoom + 0.75,
            for: harness.extensionContext
        ) { error in
            callbackError = error as NSError?
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertNotNil(callbackError)
        XCTAssertEqual(webView.pageZoom, originalZoom)
    }

    func testStoreRetirementReleasesTabAdapterRoles() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let space = try XCTUnwrap(
            harness.browserManager.tabManager.spaceStateOwner.currentSpace
        )
        let unpublishedTab = harness.browserManager.tabManager
            .regularTabLifecycleOwner.createNewTab(
                url: "https://unpublished.example",
                in: space,
                activate: false
            )
        var adapter: ExtensionTabAdapter? = try XCTUnwrap(
            harness.manager.adapterCatalog.stableAdapter(
                for: unpublishedTab
            )
        )
        weak var releasedAdapter = adapter
        weak var releasedEvidence = adapter?.evidence
        weak var releasedProjection = adapter?.projection
        weak var releasedCommands = adapter?.commands

        XCTAssertTrue(
            harness.manager.adapterStore.removeTabAdapter(
                for: unpublishedTab.id,
                ifIdenticalTo: try XCTUnwrap(adapter)
            )
        )
        adapter = nil

        XCTAssertNil(releasedAdapter)
        XCTAssertNil(releasedEvidence)
        XCTAssertNil(releasedProjection)
        XCTAssertNil(releasedCommands)
    }

    private func replacePublishedAdapter(
        in harness: RequestedPublicationHarness,
        tabMutation: any ExtensionTabCommandRouting,
        webViews: any ExtensionTabWebViewProjectionQuery
    ) throws -> ExtensionTabAdapter {
        let manager = harness.manager
        let previous = try XCTUnwrap(
            manager.adapterStore.existingTabAdapter(
                for: harness.sourceTab.id
            )
        )
        XCTAssertTrue(
            manager.adapterStore.removeTabAdapter(
                for: harness.sourceTab.id,
                ifIdenticalTo: previous
            )
        )
        let windowQuery = try XCTUnwrap(manager.extensionWindowQuery)
        let tabQuery = try XCTUnwrap(manager.extensionTabQuery)
        let webViewHosting = try XCTUnwrap(manager.extensionWebViewHosting)
        let auxiliaryWindows = try XCTUnwrap(
            manager.extensionAuxiliaryWindows
        )
        let evidence = ExtensionTabCurrentPublicationEvidence(
            tab: harness.sourceTab,
            tabQuery: tabQuery,
            runtimeSession: manager.runtimeSession,
            profileID: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            adapterPublications: manager.adapterStore,
            windowPublications: manager.windowPublications,
            contextPublications: manager.contextPublications
        )
        let projection = ExtensionTabReadProjection(
            evidence: evidence,
            windowQuery: windowQuery,
            tabQuery: tabQuery,
            webViews: webViews,
            auxiliaryWindows: auxiliaryWindows,
            windowPublications: manager.windowPublications
        )
        let commands = ExtensionTabCommandMutation(
            evidence: evidence,
            projection: projection,
            windowQuery: windowQuery,
            tabMutation: tabMutation,
            webViewHosting: webViewHosting,
            auxiliaryWindows: auxiliaryWindows
        )
        let adapter = ExtensionTabAdapter(
            evidence: evidence,
            projection: projection,
            commands: commands
        )
        let stored = manager.adapterStore.tabAdapter(
            for: harness.sourceTab,
            create: { adapter }
        )
        XCTAssertIdentical(stored, adapter)
        return adapter
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ReentrantExtensionTabWebViewQuery:
    ExtensionTabWebViewProjectionQuery {
    private let webView: WKWebView
    private let duringResolution: @MainActor (Tab) -> Void

    init(
        webView: WKWebView,
        duringResolution: @escaping @MainActor (Tab) -> Void
    ) {
        self.webView = webView
        self.duringResolution = duringResolution
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext _: WKWebExtensionContext
    ) -> WKWebView? {
        duringResolution(tab)
        return webView
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ReentrantExtensionTabMutation:
    ExtensionTabCommandRouting {
    private let underlying: any ExtensionTabCommandRouting
    private let afterPromotion: @MainActor (Tab) -> Void
    private(set) var selectionCount = 0

    init(
        underlying: any ExtensionTabCommandRouting,
        afterPromotion: @escaping @MainActor (Tab) -> Void
    ) {
        self.underlying = underlying
        self.afterPromotion = afterPromotion
    }

    func selectExtensionTab(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        selectionCount += 1
        underlying.selectExtensionTab(tab, in: windowState)
    }

    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        let result = underlying.promoteTransientExtensionTab(tab)
        afterPromotion(tab)
        return result
    }
}
