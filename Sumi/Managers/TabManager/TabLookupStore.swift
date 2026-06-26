import Foundation

@MainActor
final class TabLookupStore {
    private var tabLookup: [UUID: Tab] = [:]
    private var transientTabLookupIDs: Set<UUID> = []
    private var pendingRemovedIDs: Set<UUID> = []
    private var pendingUpserts: [UUID: Tab] = [:]
    private var pendingTransientRefresh = false

    private(set) var batchFlushCount = 0
    private(set) var immediateFlushCount = 0

    var isEmpty: Bool {
        tabLookup.isEmpty
    }

    func removeAll() {
        tabLookup.removeAll()
        transientTabLookupIDs.removeAll()
        pendingRemovedIDs.removeAll()
        pendingUpserts.removeAll()
        pendingTransientRefresh = false
    }

    func tab(for id: UUID) -> Tab? {
        tabLookup[id]
    }

    func insert(_ tab: Tab) {
        tabLookup[tab.id] = tab
    }

    func remove(_ id: UUID) {
        tabLookup.removeValue(forKey: id)
    }

    func insertTransientExtensionTab(_ tab: Tab) {
        tabLookup[tab.id] = tab
        transientTabLookupIDs.insert(tab.id)
    }

    func removeTransientExtensionTab(_ id: UUID) {
        transientTabLookupIDs.remove(id)
        tabLookup.removeValue(forKey: id)
    }

    func stopTrackingTransientTab(_ id: UUID) {
        transientTabLookupIDs.remove(id)
    }

    func rebuild(
        tabsBySpace: [UUID: [Tab]],
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab],
        auxiliaryMiniWindowTabsByID: [UUID: Tab]
    ) {
        var updatedLookup: [UUID: Tab] = [:]
        updatedLookup.reserveCapacity(
            tabsBySpace.values.reduce(0) { $0 + $1.count }
                + transientShortcutTabsByWindow.values.reduce(0) { $0 + $1.count }
                + transientExtensionTabsByID.count
                + auxiliaryMiniWindowTabsByID.count
        )

        for tabs in tabsBySpace.values {
            for tab in tabs {
                updatedLookup[tab.id] = tab
            }
        }

        for liveTabs in transientShortcutTabsByWindow.values {
            for tab in liveTabs.values {
                updatedLookup[tab.id] = tab
            }
        }
        for tab in transientExtensionTabsByID.values {
            updatedLookup[tab.id] = tab
        }
        for tab in auxiliaryMiniWindowTabsByID.values {
            updatedLookup[tab.id] = tab
        }

        tabLookup = updatedLookup
        transientTabLookupIDs = transientLookupIDs(
            transientShortcutTabsByWindow: transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientExtensionTabsByID
        )
    }

    func queueEntries(removing previousTabs: [Tab], with currentTabs: [Tab], batching: Bool) {
        guard batching else {
            replaceEntries(removing: previousTabs, with: currentTabs)
            return
        }

        let currentIDs = Set(currentTabs.map(\.id))
        for tab in previousTabs where !currentIDs.contains(tab.id) {
            pendingUpserts.removeValue(forKey: tab.id)
            pendingRemovedIDs.insert(tab.id)
        }
        for tab in currentTabs {
            pendingRemovedIDs.remove(tab.id)
            pendingUpserts[tab.id] = tab
        }
    }

    func queueTransientRefresh(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab],
        batching: Bool
    ) {
        guard batching else {
            refreshTransientLookup(
                transientShortcutTabsByWindow: transientShortcutTabsByWindow,
                transientExtensionTabsByID: transientExtensionTabsByID
            )
            return
        }

        pendingTransientRefresh = true
    }

    func flushBatchIfNeeded(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab]
    ) {
        guard hasPendingWork else { return }
        batchFlushCount += 1
        PerformanceTrace.withInterval("TabManager.structuralLookupBatch") {
            applyPendingWork(
                transientShortcutTabsByWindow: transientShortcutTabsByWindow,
                transientExtensionTabsByID: transientExtensionTabsByID
            )
        }
    }

    func flushImmediatelyIfNeeded(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab]
    ) {
        guard hasPendingWork else { return }
        immediateFlushCount += 1
        PerformanceTrace.withInterval("TabManager.structuralLookupImmediate") {
            applyPendingWork(
                transientShortcutTabsByWindow: transientShortcutTabsByWindow,
                transientExtensionTabsByID: transientExtensionTabsByID
            )
        }
    }

    private var hasPendingWork: Bool {
        pendingTransientRefresh
            || pendingRemovedIDs.isEmpty == false
            || pendingUpserts.isEmpty == false
    }

    private func applyPendingWork(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab]
    ) {
        let removedIDs = pendingRemovedIDs
        let upserts = pendingUpserts
        let shouldRefreshTransientLookup = pendingTransientRefresh

        pendingRemovedIDs.removeAll(keepingCapacity: true)
        pendingUpserts.removeAll(keepingCapacity: true)
        pendingTransientRefresh = false

        let liveTransientIDs = transientLookupIDs(
            transientShortcutTabsByWindow: transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientExtensionTabsByID
        )

        if shouldRefreshTransientLookup {
            refreshTransientLookup(
                transientShortcutTabsByWindow: transientShortcutTabsByWindow,
                transientExtensionTabsByID: transientExtensionTabsByID
            )
        }

        for tabId in removedIDs where upserts[tabId] == nil && !liveTransientIDs.contains(tabId) {
            tabLookup.removeValue(forKey: tabId)
        }

        for (tabId, tab) in upserts {
            tabLookup[tabId] = tab
        }
    }

    private func replaceEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        let currentIDs = Set(currentTabs.map(\.id))
        for tab in previousTabs where !currentIDs.contains(tab.id) {
            tabLookup.removeValue(forKey: tab.id)
        }
        for tab in currentTabs {
            tabLookup[tab.id] = tab
        }
    }

    private func refreshTransientLookup(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab]
    ) {
        for tabId in transientTabLookupIDs {
            tabLookup.removeValue(forKey: tabId)
        }

        var updatedIDs: Set<UUID> = []
        for liveTabs in transientShortcutTabsByWindow.values {
            for tab in liveTabs.values {
                tabLookup[tab.id] = tab
                updatedIDs.insert(tab.id)
            }
        }
        for tab in transientExtensionTabsByID.values {
            tabLookup[tab.id] = tab
            updatedIDs.insert(tab.id)
        }

        transientTabLookupIDs = updatedIDs
    }

    private func transientLookupIDs(
        transientShortcutTabsByWindow: [UUID: [UUID: Tab]],
        transientExtensionTabsByID: [UUID: Tab]
    ) -> Set<UUID> {
        var ids = Set(
            transientShortcutTabsByWindow.values
                .flatMap(\.values)
                .map(\.id)
        )
        ids.formUnion(transientExtensionTabsByID.keys)
        return ids
    }
}
