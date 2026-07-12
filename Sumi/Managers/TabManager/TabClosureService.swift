import Foundation

/// Application-facing tab-closing transaction. Classifies mixed candidates,
/// removes confirmed durable regular tabs, reconciles selection from one
/// coherent post-removal snapshot, captures recently-closed entries, and
/// schedules structural persistence once per successful regular batch.
@MainActor
final class TabClosureService {
    private let transactions: TabStructuralLookupCoordinator
    private let candidateRetirement: TabClosureCandidateRetirement
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let selection: TabSelectionStateOwner
    private let runtimeCleanup: RegularTabClosureRuntimeCleanup
    private let persistence: any TabClosurePersistence
    private let shortcutPresentation: TabShortcutPresentationOwner
    private let runtimePorts: TabRuntimePortConnection

    init(
        transactions: TabStructuralLookupCoordinator,
        candidateRetirement: TabClosureCandidateRetirement,
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner,
        selection: TabSelectionStateOwner,
        runtimeCleanup: RegularTabClosureRuntimeCleanup,
        persistence: any TabClosurePersistence,
        shortcutPresentation: TabShortcutPresentationOwner,
        runtimePorts: TabRuntimePortConnection
    ) {
        self.transactions = transactions
        self.candidateRetirement = candidateRetirement
        self.regularTabs = regularTabs
        self.spaces = spaces
        self.selection = selection
        self.runtimeCleanup = runtimeCleanup
        self.persistence = persistence
        self.shortcutPresentation = shortcutPresentation
        self.runtimePorts = runtimePorts
    }

    func removeTab(_ id: UUID) {
        removeTabs([id])
    }

    /// Removes a mixed candidate batch, but reports split closure only for the
    /// exact durable regular tabs that were actually present and removed.
    func removeTabs(_ ids: [UUID]) {
        transactions.withTransaction {
            let classification = candidateRetirement.retire(ids)
            guard !classification.regularCandidates.isEmpty else { return }

            let currentTabAtStart = selection.currentTab
            let removals = regularTabs.remove(
                classification.regularCandidates,
                in: spaces.spaces,
                currentSpaceId: spaces.currentSpace?.id
            )
            guard !removals.isEmpty else { return }

            let runtime = runtimePorts.requireLease()
            runtimeCleanup.releaseConfirmedRemovals(
                removals,
                runtime: runtime
            )

            if let currentTabAtStart,
               let currentRemoval = removals.first(where: {
                   $0.tab.id == currentTabAtStart.id
               }) {
                let snapshot = makeSelectionSnapshot(
                    forRemovedCurrent: currentRemoval.tab,
                    removedIndexInCurrentSpace:
                        currentRemoval.indexInCurrentSpace,
                    profileId: runtime.currentProfileId
                )
                switch SelectionAfterClosurePolicy.decision(from: snapshot) {
                case .keepCurrent:
                    break
                case .replaceCurrent(let tab):
                    selection.replaceCurrentTab(tab)
                }
            }

            captureRecentlyClosedTabs(
                removals.map { ($0.tab, $0.spaceId) },
                count: removals.count,
                runtime: runtime
            )
            persistence.scheduleStructuralPersistence()
            _ = runtime.validateWindowStates()
        }
    }

    func closeAllTabsBelow(_ tab: Tab) {
        guard tab.spaceId != nil,
              let tabsBelow = regularTabs.tabsBelow(tab),
              !tabsBelow.isEmpty else {
            return
        }
        removeTabs(tabsBelow.map(\.id))
    }

    func clearRegularTabs(for spaceId: UUID) {
        let tabs = regularTabs.tabs(in: spaceId)
        guard !tabs.isEmpty else { return }

        RuntimeDiagnostics.emit(
            "🧹 [TabClosureService] Clearing \(tabs.count) regular tabs for space \(spaceId)"
        )

        let inactiveRegular = tabs.filter {
            $0.id != selection.currentTab?.id
        }
        if !inactiveRegular.isEmpty {
            removeTabs(inactiveRegular.map(\.id))
            return
        }
        if let active = selection.currentTab,
           active.spaceId == spaceId,
           tabs.contains(where: { $0.id == active.id }) {
            removeTabs([active.id])
        }
    }

    private func makeSelectionSnapshot(
        forRemovedCurrent tab: Tab,
        removedIndexInCurrentSpace: Int?,
        profileId: UUID?
    ) -> SelectionAfterClosurePolicy.Snapshot {
        let currentSpace = spaces.currentSpace
        let essentialTabs = shortcutPresentation.activeEssentialTabs(
            for: profileId
        )
        let spacePinnedTabs: [Tab]
        let spaceRegularTabs: [Tab]
        if let currentSpace {
            spacePinnedTabs = shortcutPresentation.liveSpacePinnedTabs(
                for: currentSpace.id
            )
            spaceRegularTabs = regularTabs.tabs(in: currentSpace.id)
        } else {
            spacePinnedTabs = []
            spaceRegularTabs = []
        }
        return SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: tab.spaceId == nil,
            hasCurrentSpace: currentSpace != nil,
            essentialTabs: essentialTabs,
            spacePinnedTabs: spacePinnedTabs,
            regularTabs: spaceRegularTabs,
            removedIndexInCurrentSpace: removedIndexInCurrentSpace
        )
    }

    private func captureRecentlyClosedTabs(
        _ tabs: [(tab: Tab, spaceId: UUID?)],
        count: Int,
        runtime: RuntimePortRegistry
    ) {
        for (tab, spaceId) in tabs {
            runtime.captureClosedTab(tab, sourceSpaceId: spaceId)
        }
        runtime.notifications()?.presentTabClosureNotification(tabCount: count)
    }
}
