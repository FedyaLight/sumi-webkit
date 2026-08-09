import Foundation

struct TabLazyRestorePolicy: Equatable {
    static let `default` = Self(
        maxTotalOpportunisticTabs: 0,
        maxAdjacentTabsPerAnchor: 0,
        maxConcurrentLoads: 0
    )

    let maxTotalOpportunisticTabs: Int
    let maxAdjacentTabsPerAnchor: Int
    let maxConcurrentLoads: Int

    var isEnabled: Bool {
        maxTotalOpportunisticTabs > 0
            && maxAdjacentTabsPerAnchor > 0
            && maxConcurrentLoads > 0
    }
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
                guard tab.suspensionState.isSuspended || tab.isUnloaded else { continue }
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

    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionStateOwner
    private let membership: TabCollectionMembershipOwner
    private var eligibleTabIDs: Set<UUID> = []
    private var queuedTabIDs: [UUID] = []
    private var inFlightTabIDs: Set<UUID> = []
    private var startedTabIDs: Set<UUID> = []
    private var foregroundTabIDs: Set<UUID> = []
    private var preferredWarmupViewportSize: CGSize?
    private var loadingObserver: NSObjectProtocol?
    private let loadWebView: @MainActor (Tab, CGSize?) -> Void

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionStateOwner,
        membership: TabCollectionMembershipOwner,
        policy: TabLazyRestorePolicy = .default,
        loadWebView: @escaping @MainActor (Tab, CGSize?) -> Void = {
            tab,
            preferredViewportSize in
            tab.loadWebViewIfNeeded(
                preferredViewportSize: preferredViewportSize
            )
        }
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.membership = membership
        self.policy = policy
        self.loadWebView = loadWebView
        guard policy.isEnabled else { return }
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
        foregroundTabIDs.removeAll()
        preferredWarmupViewportSize = nil
    }

    func clear() {
        reset(restoredTabIDs: [])
    }

    func refresh(
        anchors: [TabLazyRestoreAnchor],
        selectedTabIDs: Set<UUID>,
        visibleTabIDs: Set<UUID>
    ) {
        guard policy.isEnabled else { return }
        pruneEligibility()
        foregroundTabIDs = selectedTabIDs.union(visibleTabIDs)
        preferredWarmupViewportSize = foregroundTabIDs.lazy
            .compactMap {
                self.membership.tab(for: $0)?
                    .resolvedCurrentWebView()?
                    .bounds.size
            }
            .first(where: Self.isUsableViewportSize)

        guard !eligibleTabIDs.isEmpty else {
            queuedTabIDs.removeAll()
            return
        }

        let remainingBudget = max(0, policy.maxTotalOpportunisticTabs - startedTabIDs.count)
        let tabsBySpace = regularTabs.tabsBySpaceSnapshot()
        queuedTabIDs = TabLazyRestorePlanner.plan(
            anchors: anchors,
            tabsBySpace: tabsBySpace,
            fallbackAnchorTabIDsBySpace: lazyRestoreFallbackAnchorTabIDsBySpace(
                spaces: spaces.spaces,
                tabsBySpace: tabsBySpace
            ),
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
            guard let tab = membership.tab(for: tabID) else { return false }
            return tab.requiresPrimaryWebView && (tab.suspensionState.isSuspended || tab.isUnloaded)
        }
        inFlightTabIDs = inFlightTabIDs.filter { membership.tab(for: $0) != nil }
        queuedTabIDs.removeAll { membership.tab(for: $0) == nil }
    }

    private func startQueuedLoadsIfNeeded() {
        guard hasLoadingForegroundTab == false else { return }

        while inFlightTabIDs.count < policy.maxConcurrentLoads,
              let nextTabID = queuedTabIDs.first {
            queuedTabIDs.removeFirst()
            guard startedTabIDs.insert(nextTabID).inserted else { continue }
            guard let tab = membership.tab(for: nextTabID) else {
                continue
            }

            inFlightTabIDs.insert(nextTabID)
            eligibleTabIDs.remove(nextTabID)

            loadWebView(tab, preferredWarmupViewportSize)
            Task { @MainActor [weak self, weak tab] in
                guard let self else { return }
                await Task.yield()

                if tab?.isLoading != true {
                    self.finishLoad(for: nextTabID)
                }
            }
        }
    }

    private func handleLoadingStateChange(for tab: Tab) {
        if inFlightTabIDs.contains(tab.id), tab.isLoading == false {
            finishLoad(for: tab.id)
        } else if foregroundTabIDs.contains(tab.id), tab.isLoading == false {
            startQueuedLoadsIfNeeded()
        }
    }

    private func finishLoad(for tabID: UUID) {
        guard inFlightTabIDs.remove(tabID) != nil else { return }
        startQueuedLoadsIfNeeded()
    }

    private var hasLoadingForegroundTab: Bool {
        foregroundTabIDs.contains { tabID in
            membership.tab(for: tabID)?.isLoading == true
        }
    }

    private static func isUsableViewportSize(_ size: CGSize) -> Bool {
        size.width > 0 && size.height > 0
    }

    func opportunisticRestoreAnchor(
        in windowState: BrowserWindowState,
        currentTab: Tab?
    ) -> TabLazyRestoreAnchor? {
        let spaceId = currentTab?.spaceId ?? windowState.currentSpaceId
        guard let spaceId else { return nil }

        let tabsBySpace = regularTabs.tabsBySpaceSnapshot()
        let spaces = spaces.spaces

        let regularTabId: UUID?
        if let currentTab, currentTab.spaceId == spaceId {
            regularTabId = currentTab.id
        } else if let rememberedTabID = windowState.activeTabForSpace[spaceId],
                  tabsBySpace[spaceId]?.contains(where: { $0.id == rememberedTabID }) == true {
            regularTabId = rememberedTabID
        } else if let activeTabID = spaces.first(where: { $0.id == spaceId })?.activeTabId,
                  tabsBySpace[spaceId]?.contains(where: { $0.id == activeTabID }) == true {
            regularTabId = activeTabID
        } else {
            regularTabId = tabsBySpace[spaceId]?.first?.id
        }

        return TabLazyRestoreAnchor(spaceId: spaceId, regularTabId: regularTabId)
    }

    private func lazyRestoreFallbackAnchorTabIDsBySpace(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]]
    ) -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: spaces.compactMap { space in
                guard let fallbackTabID = space.activeTabId ?? tabsBySpace[space.id]?.first?.id else {
                    return nil
                }
                return (space.id, fallbackTabID)
            }
        )
    }
}
