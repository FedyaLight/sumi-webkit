import Foundation
import SumiWebRuntime
import WebKit

/// Creates and prepares the WebView generation that a Tab can present.
@MainActor
protocol TabWebViewAvailabilityParticipant: AnyObject {
    func materializeVisibleWebViewIfNeeded(
        for tab: Tab,
        in windowState: BrowserWindowState
    )
    func load(_ tab: Tab)
    func unload(_ tab: Tab)
    func prepare(_ tab: Tab)
}

/// Owns queries and mutations for an already-created WebView generation.
@MainActor
protocol TabWebViewOwnershipParticipant: AnyObject {
    func removeAllWebViews(
        for tab: Tab
    )
    func trackingWindowIDs(for tabID: UUID) -> [UUID]
    func primaryTrackedWindowID(for tabID: UUID) -> UUID?
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowID: UUID?,
        load url: URL?
    )
    func anyLiveWebView(for tab: Tab) -> WKWebView?
    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool
}

/// Exact identity and physical-generation participant for committed Tab
/// retirement. The four operations share one retirement authority.
@MainActor
protocol TabWebViewRetirementParticipant: AnyObject {
    func canRetire(_ tabs: [Tab]) -> Bool
    func prepareRetirementOwners(_ tabs: [Tab])
    func beginCommittedRetirement(_ tabs: [Tab]) -> Bool
    func committedRetirementIsExact(_ tabs: [Tab]) -> Bool
    func destroyRetiredGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        completing tabs: [Tab]
    )
    func destroyTerminallyDrainedGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    )
}

/// Typed profile transition boundary. Model staging and WebView replacement
/// are one transaction behind this participant, not independently ordered
/// independently ordered callback slots on a manager facade.
@MainActor
protocol TabWebViewProfileTransitionParticipant: AnyObject {
    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int
    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
    func executePreparedProfileAssignments(
        _ assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome
    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
}

/// Space/profile replacement boundary that carries its physical Tab witnesses
/// with the model transaction. This prevents the WebView runtime from joining
/// a later same-ID Tab through a structural lookup.
@MainActor
protocol SpaceProfileWebViewReplacementTransaction:
    WebViewReplacementModelTransaction {
    func exactTabsForRuntime() -> [Tab]?
}

/// Stable tab-session facade over four cohesive WebView runtime roles.
/// It deliberately contains no independently injectable effect callbacks.
@MainActor
struct TabManagerWebViewLifecycleService {
    private let availability: any TabWebViewAvailabilityParticipant
    private let ownership: any TabWebViewOwnershipParticipant
    private let retirement: any TabWebViewRetirementParticipant
    private let profileTransitions: any TabWebViewProfileTransitionParticipant

    init(
        availability: any TabWebViewAvailabilityParticipant,
        ownership: any TabWebViewOwnershipParticipant,
        retirement: any TabWebViewRetirementParticipant,
        profileTransitions: any TabWebViewProfileTransitionParticipant
    ) {
        self.availability = availability
        self.ownership = ownership
        self.retirement = retirement
        self.profileTransitions = profileTransitions
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        availability.materializeVisibleWebViewIfNeeded(
            for: tab,
            in: windowState
        )
    }

    func loadTab(_ tab: Tab) {
        availability.load(tab)
    }

    func unloadTab(_ tab: Tab) {
        availability.unload(tab)
    }

    func requireRemoveAllWebViews(for tab: Tab) {
        ownership.removeAllWebViews(for: tab)
    }

    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID] {
        ownership.trackingWindowIDs(for: tabId)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        ownership.primaryTrackedWindowID(for: tabId)
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID?,
        load url: URL?
    ) {
        ownership.rebuildLiveWebViews(
            for: tab,
            preferredPrimaryWindowID: preferredPrimaryWindowId,
            load: url
        )
    }

    func prepareTab(_ tab: Tab) {
        availability.prepare(tab)
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        ownership.anyLiveWebView(for: tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        ownership.hasUntrackedOwnedWebView(for: tab)
    }

    func canRetireTabWebViews(_ tabs: [Tab]) -> Bool {
        retirement.canRetire(tabs)
    }

    func prepareTabWebViewRetirementOwners(_ tabs: [Tab]) {
        retirement.prepareRetirementOwners(tabs)
    }

    func beginCommittedTabRetirement(_ tabs: [Tab]) -> Bool {
        retirement.beginCommittedRetirement(tabs)
    }

    func committedTabRetirementIsExact(_ tabs: [Tab]) -> Bool {
        retirement.committedRetirementIsExact(tabs)
    }

    func destroyRetiredWebViews(
        _ generations: [RetiredTabWebViewGeneration],
        completingRetirementOf tabs: [Tab]
    ) {
        retirement.destroyRetiredGenerations(generations, completing: tabs)
    }

    func destroyTerminallyDrainedRetiredWebViews(
        _ generations: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    ) {
        retirement.destroyTerminallyDrainedGenerations(
            generations,
            belongingTo: tabs
        )
    }

    @discardableResult
    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int {
        profileTransitions.abortProfileTransitions(profileIDs: profileIDs)
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        profileTransitions.executeProfileAssignment(
            for: tab,
            targetProfile: targetProfile,
            intent: intent,
            settlement: settlement
        )
    }

    func executePreparedProfileAssignments(
        _ assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        profileTransitions.executePreparedProfileAssignments(
            assignments,
            bindingModel: bindingModel,
            settlement: settlement
        )
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        profileTransitions.executeSpaceProfileAssignment(
            space: space,
            targetProfile: targetProfile,
            intent: intent,
            model: model,
            settlement: settlement
        )
    }
}
