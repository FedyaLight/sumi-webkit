import Foundation

/// Canonical per-window membership for materialized shortcut tabs.
///
/// The underlying state store remains shared with structural snapshots, but every
/// live mutation passes through this type so slot identity, deterministic lookup,
/// empty-window pruning, and structural publication cannot drift apart.
@MainActor
final class LiveShortcutTabRegistry {
    private let storage: TabTransientTabRegistryOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        storage: TabTransientTabRegistryOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.storage = storage
        self.structuralLookup = structuralLookup
    }

    convenience init(tabManager: TabManager) {
        self.init(
            storage: tabManager.transientTabRegistryOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }

    var snapshot: [UUID: [UUID: Tab]] {
        storage.transientShortcutTabsByWindow
    }

    private var readModel: LiveShortcutTabSnapshot {
        LiveShortcutTabSnapshot(tabsByWindow: snapshot)
    }

    func tab(for pinId: UUID, in windowId: UUID) -> Tab? {
        storage.transientShortcutTabsByWindow[windowId]?[pinId]
    }

    func entries(for pinId: UUID) -> [LiveShortcutTabEntry] {
        readModel.entries(for: pinId)
    }

    func entries(in windowId: UUID) -> [LiveShortcutTabEntry] {
        readModel.entries(in: windowId)
    }

    func entry(containing tab: Tab) -> LiveShortcutTabEntry? {
        readModel.entry(containing: tab)
    }

    func entry(tabId: UUID) -> LiveShortcutTabEntry? {
        readModel.entry(tabID: tabId)
    }

    @discardableResult
    func register(_ tab: Tab, for pinId: UUID, in windowId: UUID) -> Bool {
        if let existing = storage.transientShortcutTabsByWindow[windowId]?[pinId] {
            precondition(existing === tab, "Live shortcut registry slot replacement")
            return false
        }
        precondition(
            readModel.entry(containing: tab) == nil,
            "Live shortcut tab registered in more than one slot"
        )
        storage.updateTransientShortcutTabsByWindow { tabsByWindow in
            tabsByWindow[windowId, default: [:]][pinId] = tab
        }
        structuralLookup.notifyTransientShortcutStateChanged(
            entries: [LiveShortcutTabEntry(windowId: windowId, pinId: pinId, tab: tab)]
        )
        return true
    }

    @discardableResult
    func rekey(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID
    ) -> Bool {
        guard storage.transientShortcutTabsByWindow[windowId]?[sourcePinId] === tab else {
            return false
        }
        if sourcePinId == targetPinId { return false }
        if let target = storage.transientShortcutTabsByWindow[windowId]?[targetPinId] {
            precondition(target === tab, "Live shortcut registry rekey collision")
        }
        storage.updateTransientShortcutTabsByWindow { tabsByWindow in
            tabsByWindow[windowId]?.removeValue(forKey: sourcePinId)
            tabsByWindow[windowId, default: [:]][targetPinId] = tab
        }
        structuralLookup.notifyTransientShortcutStateChanged(
            entries: [LiveShortcutTabEntry(windowId: windowId, pinId: targetPinId, tab: tab)]
        )
        return true
    }

    @discardableResult
    func remove(pinId: UUID, in windowId: UUID) -> LiveShortcutTabEntry? {
        guard let tab = storage.removeTransientShortcutTab(
            pinId: pinId,
            in: windowId
        ) else { return nil }
        let entry = LiveShortcutTabEntry(windowId: windowId, pinId: pinId, tab: tab)
        structuralLookup.notifyTransientShortcutStateChanged(entries: [entry])
        return entry
    }

    @discardableResult
    func remove(tabId: UUID) -> LiveShortcutTabEntry? {
        guard let removed = storage.removeTransientShortcutTab(tabId: tabId) else {
            return nil
        }
        let entry = LiveShortcutTabEntry(
            windowId: removed.windowId,
            pinId: removed.pinId,
            tab: removed.tab
        )
        structuralLookup.notifyTransientShortcutStateChanged(entries: [entry])
        return entry
    }

    @discardableResult
    func removeAll(pinId: UUID, excluding windowId: UUID? = nil) -> [LiveShortcutTabEntry] {
        removeAll {
            $0.pinId == pinId && $0.windowId != windowId
        }
    }

    @discardableResult
    func removeAll(pinIds: Set<UUID>) -> [LiveShortcutTabEntry] {
        removeAll { pinIds.contains($0.pinId) }
    }

    @discardableResult
    func removeAll(pinIds: Set<UUID>, in windowId: UUID) -> [LiveShortcutTabEntry] {
        removeAll {
            $0.windowId == windowId && pinIds.contains($0.pinId)
        }
    }

    @discardableResult
    func removeAll(in windowId: UUID) -> [LiveShortcutTabEntry] {
        removeAll { $0.windowId == windowId }
    }

    @discardableResult
    func removeAll(inSpace spaceId: UUID) -> [LiveShortcutTabEntry] {
        removeAll { $0.tab.spaceId == spaceId }
    }

    @discardableResult
    func removeAll() -> [LiveShortcutTabEntry] {
        removeAll { _ in true }
    }

    private func removeAll(
        matching predicate: (LiveShortcutTabEntry) -> Bool
    ) -> [LiveShortcutTabEntry] {
        let matches = readModel.orderedEntries.filter(predicate)
        guard matches.isEmpty == false else { return [] }
        storage.updateTransientShortcutTabsByWindow { tabsByWindow in
            for entry in matches {
                tabsByWindow[entry.windowId]?.removeValue(forKey: entry.pinId)
                if tabsByWindow[entry.windowId]?.isEmpty == true {
                    tabsByWindow.removeValue(forKey: entry.windowId)
                }
            }
        }
        structuralLookup.notifyTransientShortcutStateChanged(entries: matches)
        return matches
    }
}
