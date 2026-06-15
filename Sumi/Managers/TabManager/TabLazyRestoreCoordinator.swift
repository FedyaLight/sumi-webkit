import Foundation

struct TabLazyRestorePolicy: Equatable {
    static let `default` = Self(
        maxTotalOpportunisticTabs: 20,
        maxAdjacentTabsPerAnchor: 10,
        maxConcurrentLoads: 3
    )

    let maxTotalOpportunisticTabs: Int
    let maxAdjacentTabsPerAnchor: Int
    let maxConcurrentLoads: Int
}

struct TabLazyRestoreAnchor: Equatable {
    let spaceId: UUID
    let regularTabId: UUID?
}

@MainActor
enum TabLazyRestorePlanner {
    static func plan(
        anchors: [TabLazyRestoreAnchor],
        tabsBySpace: [UUID: [Tab]],
        fallbackAnchorTabIDsBySpace: [UUID: UUID],
        eligibleTabIDs: Set<UUID>,
        selectedTabIDs: Set<UUID>,
        visibleTabIDs: Set<UUID>,
        excludedTabIDs: Set<UUID>,
        maxTotalCount: Int,
        maxAdjacentCountPerAnchor: Int
    ) -> [UUID] {
        guard maxTotalCount > 0, maxAdjacentCountPerAnchor > 0 else { return [] }

        let blockedTabIDs = selectedTabIDs.union(visibleTabIDs).union(excludedTabIDs)
        var plannedTabIDs: [UUID] = []
        var seenTabIDs = excludedTabIDs

        for anchor in anchors {
            guard plannedTabIDs.count < maxTotalCount else { break }
            guard let orderedTabs = tabsBySpace[anchor.spaceId], !orderedTabs.isEmpty else {
                continue
            }

            let orderedTabIDs = orderedTabs.map(\.id)
            let anchorTabID = resolvedAnchorTabID(
                orderedTabIDs: orderedTabIDs,
                preferredTabID: anchor.regularTabId,
                fallbackTabID: fallbackAnchorTabIDsBySpace[anchor.spaceId]
            )
            let adjacentTabIDs = adjacentTabIDs(
                orderedTabIDs: orderedTabIDs,
                anchorTabID: anchorTabID,
                limit: maxAdjacentCountPerAnchor
            )

            for tabID in adjacentTabIDs {
                guard plannedTabIDs.count < maxTotalCount else { break }
                guard seenTabIDs.insert(tabID).inserted else { continue }
                guard !blockedTabIDs.contains(tabID) else { continue }
                guard let tab = orderedTabs.first(where: { $0.id == tabID }) else { continue }
                guard eligibleTabIDs.contains(tabID) else { continue }
                guard tab.requiresPrimaryWebView else { continue }
                guard tab.isSuspended || tab.isUnloaded else { continue }
                plannedTabIDs.append(tabID)
            }
        }

        return plannedTabIDs
    }

    private static func resolvedAnchorTabID(
        orderedTabIDs: [UUID],
        preferredTabID: UUID?,
        fallbackTabID: UUID?
    ) -> UUID? {
        if let preferredTabID, orderedTabIDs.contains(preferredTabID) {
            return preferredTabID
        }
        if let fallbackTabID, orderedTabIDs.contains(fallbackTabID) {
            return fallbackTabID
        }
        return orderedTabIDs.first
    }

    private static func adjacentTabIDs(
        orderedTabIDs: [UUID],
        anchorTabID: UUID?,
        limit: Int
    ) -> [UUID] {
        guard limit > 0 else { return [] }
        guard let anchorTabID,
              let anchorIndex = orderedTabIDs.firstIndex(of: anchorTabID)
        else {
            return Array(orderedTabIDs.prefix(limit))
        }

        var adjacentTabIDs: [UUID] = []
        var distance = 1

        while adjacentTabIDs.count < limit {
            let leftIndex = anchorIndex - distance
            if leftIndex >= 0 {
                adjacentTabIDs.append(orderedTabIDs[leftIndex])
                if adjacentTabIDs.count == limit {
                    break
                }
            }

            let rightIndex = anchorIndex + distance
            if rightIndex < orderedTabIDs.count {
                adjacentTabIDs.append(orderedTabIDs[rightIndex])
                if adjacentTabIDs.count == limit {
                    break
                }
            }

            if leftIndex < 0 && rightIndex >= orderedTabIDs.count {
                break
            }

            distance += 1
        }

        return adjacentTabIDs
    }
}

@MainActor
final class TabLazyRestoreCoordinator {
    let policy: TabLazyRestorePolicy

    private unowned let tabManager: TabManager
    private var eligibleTabIDs: Set<UUID> = []
    private var queuedTabIDs: [UUID] = []
    private var inFlightTabIDs: Set<UUID> = []
    private var startedTabIDs: Set<UUID> = []
    private var loadingObserver: NSObjectProtocol?

    init(
        tabManager: TabManager,
        policy: TabLazyRestorePolicy = .default
    ) {
        self.tabManager = tabManager
        self.policy = policy
        self.loadingObserver = NotificationCenter.default.addObserver(
            forName: .sumiTabLoadingStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let tab = notification.object as? Tab else { return }
            Task { @MainActor [weak self] in
                self?.handleLoadingStateChange(for: tab)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let loadingObserver {
                NotificationCenter.default.removeObserver(loadingObserver)
            }
        }
    }

    func reset(restoredTabIDs: Set<UUID>) {
        eligibleTabIDs = restoredTabIDs
        queuedTabIDs.removeAll()
        inFlightTabIDs.removeAll()
        startedTabIDs.removeAll()
    }

    func clear() {
        reset(restoredTabIDs: [])
    }

    func refresh(
        anchors: [TabLazyRestoreAnchor],
        selectedTabIDs: Set<UUID>,
        visibleTabIDs: Set<UUID>
    ) {
        pruneEligibility()

        guard !eligibleTabIDs.isEmpty else {
            queuedTabIDs.removeAll()
            return
        }

        let remainingBudget = max(0, policy.maxTotalOpportunisticTabs - startedTabIDs.count)
        queuedTabIDs = TabLazyRestorePlanner.plan(
            anchors: anchors,
            tabsBySpace: tabManager.tabsBySpace,
            fallbackAnchorTabIDsBySpace: tabManager.lazyRestoreFallbackAnchorTabIDsBySpace(),
            eligibleTabIDs: eligibleTabIDs,
            selectedTabIDs: selectedTabIDs,
            visibleTabIDs: visibleTabIDs,
            excludedTabIDs: startedTabIDs.union(inFlightTabIDs),
            maxTotalCount: remainingBudget,
            maxAdjacentCountPerAnchor: policy.maxAdjacentTabsPerAnchor
        )
        startQueuedLoadsIfNeeded()
    }

    private func pruneEligibility() {
        eligibleTabIDs = eligibleTabIDs.filter { tabID in
            guard let tab = tabManager.tab(for: tabID) else { return false }
            return tab.requiresPrimaryWebView && (tab.isSuspended || tab.isUnloaded)
        }
        inFlightTabIDs = inFlightTabIDs.filter { tabManager.tab(for: $0) != nil }
        queuedTabIDs.removeAll { tabManager.tab(for: $0) == nil }
    }

    private func startQueuedLoadsIfNeeded() {
        while inFlightTabIDs.count < policy.maxConcurrentLoads,
              let nextTabID = queuedTabIDs.first
        {
            queuedTabIDs.removeFirst()
            guard startedTabIDs.insert(nextTabID).inserted else { continue }
            guard let tab = tabManager.tab(for: nextTabID) else {
                continue
            }

            inFlightTabIDs.insert(nextTabID)
            eligibleTabIDs.remove(nextTabID)

            Task { @MainActor [weak self, weak tab] in
                guard let self else { return }
                guard let tab else {
                    self.finishLoad(for: nextTabID)
                    return
                }

                tab.loadWebViewIfNeeded()
                await Task.yield()

                if !tab.isLoading {
                    self.finishLoad(for: nextTabID)
                }
            }
        }
    }

    private func handleLoadingStateChange(for tab: Tab) {
        guard inFlightTabIDs.contains(tab.id) else { return }
        guard !tab.isLoading else { return }
        finishLoad(for: tab.id)
    }

    private func finishLoad(for tabID: UUID) {
        guard inFlightTabIDs.remove(tabID) != nil else { return }
        startQueuedLoadsIfNeeded()
    }
}

@MainActor
extension TabManager {
    func lazyRestoreFallbackAnchorTabIDsBySpace() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: spaces.compactMap { space in
                guard let fallbackTabID = space.activeTabId ?? tabsBySpace[space.id]?.first?.id else {
                    return nil
                }
                return (space.id, fallbackTabID)
            }
        )
    }

    func opportunisticRestoreAnchor(
        in windowState: BrowserWindowState,
        currentTab: Tab?
    ) -> TabLazyRestoreAnchor? {
        let spaceId = currentTab?.spaceId ?? windowState.currentSpaceId
        guard let spaceId else { return nil }

        let regularTabId: UUID?
        if let currentTab, currentTab.spaceId == spaceId {
            regularTabId = currentTab.id
        } else if let rememberedTabID = windowState.activeTabForSpace[spaceId],
                  tabsBySpace[spaceId]?.contains(where: { $0.id == rememberedTabID }) == true
        {
            regularTabId = rememberedTabID
        } else if let activeTabID = spaces.first(where: { $0.id == spaceId })?.activeTabId,
                  tabsBySpace[spaceId]?.contains(where: { $0.id == activeTabID }) == true
        {
            regularTabId = activeTabID
        } else {
            regularTabId = tabsBySpace[spaceId]?.first?.id
        }

        return TabLazyRestoreAnchor(spaceId: spaceId, regularTabId: regularTabId)
    }
}
