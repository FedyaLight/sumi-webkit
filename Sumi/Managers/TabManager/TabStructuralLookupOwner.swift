import Foundation

struct TabStructuralLookupSnapshot {
    var tabsBySpace: [UUID: [Tab]]
    var transientShortcutTabsByWindow: [UUID: [UUID: Tab]]
    var transientExtensionTabsByID: [UUID: Tab]
    var auxiliaryMiniWindowTabsByID: [UUID: Tab]
}

@MainActor
final class TabStructuralLookupOwner {
    private let store: TabLookupStore
    private var attachedLiveTabIDs: Set<UUID> = []

    init(store: TabLookupStore = TabLookupStore()) {
        self.store = store
    }

    var batchFlushCount: Int { store.batchFlushCount }
    var immediateFlushCount: Int { store.immediateFlushCount }

    func removeAll() {
        attachedLiveTabIDs.removeAll()
        store.removeAll()
    }

    func tab(for id: UUID, snapshot: TabStructuralLookupSnapshot) -> Tab? {
        flushImmediatelyIfNeeded(snapshot: snapshot)
        if let tab = store.tab(for: id) {
            return tab
        }

        rebuild(with: snapshot)
        return store.tab(for: id)
    }

    func rebuild(with snapshot: TabStructuralLookupSnapshot) {
        store.rebuild(
            tabsBySpace: snapshot.tabsBySpace,
            transientShortcutTabsByWindow: snapshot.transientShortcutTabsByWindow,
            transientExtensionTabsByID: snapshot.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: snapshot.auxiliaryMiniWindowTabsByID
        )
    }

    func rebuildIfEmpty(with snapshot: TabStructuralLookupSnapshot) {
        guard store.isEmpty else { return }
        rebuild(with: snapshot)
    }

    func attach(_ tab: Tab) {
        store.insert(tab)
        attachedLiveTabIDs.insert(tab.id)
    }

    func detach(_ tab: Tab) {
        attachedLiveTabIDs.remove(tab.id)
        store.remove(tab.id)
    }

    func remove(_ id: UUID) {
        store.remove(id)
    }

    func insertTransientExtensionTab(_ tab: Tab) {
        store.insertTransientExtensionTab(tab)
    }

    func removeTransientExtensionTab(_ id: UUID) {
        store.removeTransientExtensionTab(id)
    }

    func stopTrackingTransientTab(_ id: UUID) {
        store.stopTrackingTransientTab(id)
    }

    func queueEntries(removing previousTabs: [Tab], with currentTabs: [Tab], batching: Bool) {
        store.queueEntries(removing: previousTabs, with: currentTabs, batching: batching)
    }

    func queueTransientRefresh(snapshot: TabStructuralLookupSnapshot, batching: Bool) {
        store.queueTransientRefresh(
            transientShortcutTabsByWindow: snapshot.transientShortcutTabsByWindow,
            transientExtensionTabsByID: snapshot.transientExtensionTabsByID,
            batching: batching
        )
    }

    func flushBatchIfNeeded(snapshot: TabStructuralLookupSnapshot) {
        store.flushBatchIfNeeded(
            transientShortcutTabsByWindow: snapshot.transientShortcutTabsByWindow,
            transientExtensionTabsByID: snapshot.transientExtensionTabsByID
        )
    }

    func flushImmediatelyIfNeeded(snapshot: TabStructuralLookupSnapshot) {
        store.flushImmediatelyIfNeeded(
            transientShortcutTabsByWindow: snapshot.transientShortcutTabsByWindow,
            transientExtensionTabsByID: snapshot.transientExtensionTabsByID
        )
    }
}
