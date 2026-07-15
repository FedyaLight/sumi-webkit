import Foundation
import WebKit

@MainActor
private final class BrowserTabWebViewAvailabilityParticipant:
    TabWebViewAvailabilityParticipant {
    private let compositor: TabCompositorManager
    private let ownership: WebViewOwnershipQuery
    private let trackedAdmission: TrackedWebViewAdmissionService
    private let tabBrowserRuntime: TabBrowserRuntime

    init(
        compositor: TabCompositorManager,
        ownership: WebViewOwnershipQuery,
        trackedAdmission: TrackedWebViewAdmissionService,
        tabBrowserRuntime: TabBrowserRuntime
    ) {
        self.compositor = compositor
        self.ownership = ownership
        self.trackedAdmission = trackedAdmission
        self.tabBrowserRuntime = tabBrowserRuntime
    }

    func materializeVisibleWebViewIfNeeded(
        for tab: Tab,
        in windowState: BrowserWindowState
    ) {
        compositor.markTabAccessed(tab.id)
        guard ownership.webView(for: tab.id, in: windowState.id) == nil else {
            return
        }
        _ = trackedAdmission.webView(for: tab, in: windowState.id)
    }

    func load(_ tab: Tab) {
        compositor.loadTab(tab)
    }

    func unload(_ tab: Tab) {
        compositor.unloadTab(tab)
    }

    func prepare(_ tab: Tab) {
        tab.attachBrowserRuntime(tabBrowserRuntime)
        guard tab.hasCurrentWebView == false else { return }
        _ = tab.navigationCommandOwner
            .prepareMainFrameConfigurationPolicyIfNeeded(
                tab.url,
                for: tab,
                reason: "BrowserTabManagerWebViewLifecycleFactory.prepareTab"
            )
    }
}

@MainActor
private final class BrowserTabWebViewOwnershipParticipant:
    TabWebViewOwnershipParticipant {
    private let lifecycle: WebViewLifecycleService
    private let ownership: WebViewOwnershipQuery
    private let rebuild: WebViewRebuildService
    private let routing: BrowserWebViewRoutingService

    init(
        lifecycle: WebViewLifecycleService,
        ownership: WebViewOwnershipQuery,
        rebuild: WebViewRebuildService,
        routing: BrowserWebViewRoutingService
    ) {
        self.lifecycle = lifecycle
        self.ownership = ownership
        self.rebuild = rebuild
        self.routing = routing
    }

    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool
    ) {
        lifecycle.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: closeActiveFullscreenMedia,
            intent: .retirement
        )
    }

    func trackingWindowIDs(for tabID: UUID) -> [UUID] {
        ownership.windowIDs(for: tabID)
    }

    func primaryTrackedWindowID(for tabID: UUID) -> UUID? {
        routing.primaryTrackedWindowId(for: tabID)
    }

    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowID: UUID?,
        load url: URL?
    ) {
        if #available(macOS 15.5, *) {
            rebuild.rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                load: url
            )
        }
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        routing.anyLiveWebView(for: tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        routing.hasUntrackedOwnedWebView(for: tab)
    }
}

@MainActor
private final class BrowserTabWebViewRetirementParticipant:
    TabWebViewRetirementParticipant {
    private let protection: WebViewProtectionRuntime
    private let committed: WebViewCommittedTabRetirementService

    init(
        protection: WebViewProtectionRuntime,
        committed: WebViewCommittedTabRetirementService
    ) {
        self.protection = protection
        self.committed = committed
    }

    func canRetire(_ tabs: [Tab]) -> Bool {
        tabs.flatMap(\.webViewSession.allKnownWebViews)
            .allSatisfy { protection.isProtected($0) == false }
            && committed.canAdmit(tabs)
    }

    func beginCommittedRetirement(_ tabs: [Tab]) -> Bool {
        committed.beginCommitted(tabs)
    }

    func destroyRetiredGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        completing tabs: [Tab]
    ) {
        committed.destroy(generations, completing: tabs)
    }

    func destroyTerminallyDrainedGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    ) {
        committed.destroyAfterRuntimeTermination(
            generations,
            belongingTo: tabs
        )
    }
}

@MainActor
enum BrowserTabManagerWebViewLifecycleFactory {
    static func service(
        webViewLifecycle: WebViewLifecycleService,
        webViewProtection: WebViewProtectionRuntime,
        committedRetirement: WebViewCommittedTabRetirementService,
        ownershipQuery: WebViewOwnershipQuery,
        trackedAdmission: TrackedWebViewAdmissionService,
        rebuild: WebViewRebuildService,
        profileAssignment: WebViewProfileAssignmentService,
        compositor: TabCompositorManager,
        webViewRouting: BrowserWebViewRoutingService,
        tabBrowserRuntime: TabBrowserRuntime
    ) -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            availability: BrowserTabWebViewAvailabilityParticipant(
                compositor: compositor,
                ownership: ownershipQuery,
                trackedAdmission: trackedAdmission,
                tabBrowserRuntime: tabBrowserRuntime
            ),
            ownership: BrowserTabWebViewOwnershipParticipant(
                lifecycle: webViewLifecycle,
                ownership: ownershipQuery,
                rebuild: rebuild,
                routing: webViewRouting
            ),
            retirement: BrowserTabWebViewRetirementParticipant(
                protection: webViewProtection,
                committed: committedRetirement
            ),
            profileTransitions: profileAssignment
        )
    }
}
