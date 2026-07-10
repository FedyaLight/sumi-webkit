import Foundation
import SumiWebRuntime
import WebKit

@MainActor
struct TabManagerWebViewLifecycleService {
    private let materializeVisibleWebViewIfNeeded: (Tab, BrowserWindowState) -> Void
    private let loadTabHandler: (Tab) -> Void
    private let unloadTabHandler: (Tab) -> Void
    private let requireRemoveAllWebViewsHandler: (Tab, Bool) -> Void
    private let windowIDsTrackingWebViewsProvider: (UUID) -> [UUID]
    private let primaryTrackedWindowIdProvider: (UUID) -> UUID?
    private let rebuildLiveWebViewsHandler: (Tab, UUID?, URL?) -> Void
    private let prepareTabHandler: (Tab) -> Void
    private let anyLiveWebViewProvider: (Tab) -> WKWebView?
    private let hasUntrackedOwnedWebViewProvider: (Tab) -> Bool
    private let abortProfileTransitionsHandler: (Set<UUID>) -> Int
    private let profileAssignmentExecutor: (
        Tab,
        Profile,
        DeferredWebViewProfileAssignmentIntent,
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
    private let spaceProfileAssignmentExecutor: (
        Space,
        Profile,
        DeferredWebViewSpaceProfileAssignmentIntent,
        @escaping @MainActor @Sendable () -> Bool,
        @escaping @MainActor @Sendable () -> Bool,
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome

    init(
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void,
        loadTab: @escaping (Tab) -> Void,
        unloadTab: @escaping (Tab) -> Void,
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void,
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID],
        primaryTrackedWindowId: @escaping (UUID) -> UUID?,
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void,
        prepareTab: @escaping (Tab) -> Void,
        anyLiveWebView: @escaping (Tab) -> WKWebView?,
        hasUntrackedOwnedWebView: @escaping (Tab) -> Bool,
        abortProfileTransitions: @escaping (Set<UUID>) -> Int = { _ in 0 },
        executeProfileAssignment: @escaping (
            Tab,
            Profile,
            DeferredWebViewProfileAssignmentIntent
        ) -> TabProfileAssignmentExecutionOutcome = { _, _, _ in .failed },
        executeProfileTransition: ((
            Tab,
            Profile,
            DeferredWebViewProfileAssignmentIntent,
            @escaping ProfileTransitionService.Settlement
        ) -> TabProfileAssignmentExecutionOutcome)? = nil,
        executeSpaceProfileAssignment: @escaping (
            Space,
            Profile,
            DeferredWebViewSpaceProfileAssignmentIntent,
            @escaping @MainActor @Sendable () -> Bool,
            @escaping @MainActor @Sendable () -> Bool,
            @escaping () -> Void
        ) -> TabProfileAssignmentExecutionOutcome = {
            _, _, _, validateModel, modelCommit, _ in
            guard validateModel(), modelCommit() else { return .stale }
            return .committed
        },
        executeSpaceProfileTransition: ((
            Space,
            Profile,
            DeferredWebViewSpaceProfileAssignmentIntent,
            @escaping @MainActor @Sendable () -> Bool,
            @escaping @MainActor @Sendable () -> Bool,
            @escaping () -> Void,
            @escaping () -> Void,
            @escaping ProfileTransitionService.Settlement
        ) -> TabProfileAssignmentExecutionOutcome)? = nil
    ) {
        self.materializeVisibleWebViewIfNeeded = materializeVisibleTabWebViewIfNeeded
        self.loadTabHandler = loadTab
        self.unloadTabHandler = unloadTab
        self.requireRemoveAllWebViewsHandler = requireRemoveAllWebViews
        self.windowIDsTrackingWebViewsProvider = windowIDsTrackingWebViews
        self.primaryTrackedWindowIdProvider = primaryTrackedWindowId
        self.rebuildLiveWebViewsHandler = rebuildLiveWebViews
        self.prepareTabHandler = prepareTab
        self.anyLiveWebViewProvider = anyLiveWebView
        self.hasUntrackedOwnedWebViewProvider = hasUntrackedOwnedWebView
        abortProfileTransitionsHandler = abortProfileTransitions
        profileAssignmentExecutor = executeProfileTransition ?? {
            tab, profile, intent, settlement in
            let outcome = executeProfileAssignment(tab, profile, intent)
            if outcome != .deferred {
                settlement(
                    outcome == .committed ? .committed : .rejected(outcome)
                )
            }
            return outcome
        }
        spaceProfileAssignmentExecutor = executeSpaceProfileTransition ?? {
            space,
            profile,
            intent,
            validate,
            stage,
            finish,
            rollback,
            settlement in
            let outcome = executeSpaceProfileAssignment(
                space,
                profile,
                intent,
                validate,
                stage,
                rollback
            )
            if outcome == .committed { finish() }
            if outcome != .deferred {
                settlement(
                    outcome == .committed ? .committed : .rejected(outcome)
                )
            }
            return outcome
        }
    }

    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState) {
        materializeVisibleWebViewIfNeeded(tab, windowState)
    }

    func loadTab(_ tab: Tab) {
        loadTabHandler(tab)
    }

    func unloadTab(_ tab: Tab) {
        unloadTabHandler(tab)
    }

    func requireRemoveAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        requireRemoveAllWebViewsHandler(tab, closeActiveFullscreenMedia)
    }

    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID] {
        windowIDsTrackingWebViewsProvider(tabId)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        primaryTrackedWindowIdProvider(tabId)
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?) {
        rebuildLiveWebViewsHandler(tab, preferredPrimaryWindowId, url)
    }

    func prepareTab(_ tab: Tab) {
        prepareTabHandler(tab)
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        anyLiveWebViewProvider(tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        hasUntrackedOwnedWebViewProvider(tab)
    }

    @discardableResult
    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int {
        abortProfileTransitionsHandler(profileIDs)
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        profileAssignmentExecutor(tab, targetProfile, intent, settlement)
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        validateModel: @escaping @MainActor @Sendable () -> Bool,
        modelCommit: @escaping @MainActor @Sendable () -> Bool,
        modelFinish: @escaping () -> Void,
        modelRollback: @escaping () -> Void,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        spaceProfileAssignmentExecutor(
            space,
            targetProfile,
            intent,
            validateModel,
            modelCommit,
            modelFinish,
            modelRollback,
            settlement
        )
    }
}
