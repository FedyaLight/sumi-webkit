import Foundation

/// Canonical per-window membership for materialized shortcut tabs.
///
/// The underlying state store remains shared with structural snapshots, but every
/// live mutation passes through this type so slot identity, deterministic lookup,
/// empty-window pruning, and structural publication cannot drift apart.
@MainActor
final class LiveShortcutTabRegistry {
    struct Entry {
        let windowId: UUID
        let pinId: UUID
        let tab: Tab
    }

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

    func tab(for pinId: UUID, in windowId: UUID) -> Tab? {
        storage.transientShortcutTabsByWindow[windowId]?[pinId]
    }

    func entries(for pinId: UUID) -> [Entry] {
        allEntries().filter { $0.pinId == pinId }
    }

    func entry(containing tab: Tab) -> Entry? {
        allEntries().first { $0.tab === tab }
    }

    func entry(tabId: UUID) -> Entry? {
        allEntries().first { $0.tab.id == tabId }
    }

    @discardableResult
    func register(_ tab: Tab, for pinId: UUID, in windowId: UUID) -> Bool {
        if let existing = storage.transientShortcutTabsByWindow[windowId]?[pinId] {
            precondition(existing === tab, "Live shortcut registry slot replacement")
            return false
        }
        precondition(
            allEntries().contains { $0.tab === tab } == false,
            "Live shortcut tab registered in more than one slot"
        )
        storage.updateTransientShortcutTabsByWindow { tabsByWindow in
            tabsByWindow[windowId, default: [:]][pinId] = tab
        }
        structuralLookup.notifyTransientShortcutStateChanged()
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
        structuralLookup.notifyTransientShortcutStateChanged()
        return true
    }

    @discardableResult
    func remove(pinId: UUID, in windowId: UUID) -> Entry? {
        guard let tab = storage.removeTransientShortcutTab(
            pinId: pinId,
            in: windowId
        ) else { return nil }
        structuralLookup.notifyTransientShortcutStateChanged()
        return Entry(windowId: windowId, pinId: pinId, tab: tab)
    }

    @discardableResult
    func remove(tabId: UUID) -> Entry? {
        guard let removed = storage.removeTransientShortcutTab(tabId: tabId) else {
            return nil
        }
        structuralLookup.notifyTransientShortcutStateChanged()
        return Entry(
            windowId: removed.windowId,
            pinId: removed.pinId,
            tab: removed.tab
        )
    }

    @discardableResult
    func removeAll(pinId: UUID, excluding windowId: UUID? = nil) -> [Entry] {
        removeAll {
            $0.pinId == pinId && $0.windowId != windowId
        }
    }

    @discardableResult
    func removeAll(pinIds: Set<UUID>) -> [Entry] {
        removeAll { pinIds.contains($0.pinId) }
    }

    @discardableResult
    func removeAll(inSpace spaceId: UUID) -> [Entry] {
        removeAll { $0.tab.spaceId == spaceId }
    }

    @discardableResult
    func removeAll() -> [Entry] {
        removeAll { _ in true }
    }

    private func removeAll(
        matching predicate: (Entry) -> Bool
    ) -> [Entry] {
        let matches = allEntries().filter(predicate)
        guard matches.isEmpty == false else { return [] }
        storage.updateTransientShortcutTabsByWindow { tabsByWindow in
            for entry in matches {
                tabsByWindow[entry.windowId]?.removeValue(forKey: entry.pinId)
                if tabsByWindow[entry.windowId]?.isEmpty == true {
                    tabsByWindow.removeValue(forKey: entry.windowId)
                }
            }
        }
        structuralLookup.notifyTransientShortcutStateChanged()
        return matches
    }

    private func allEntries() -> [Entry] {
        storage.transientShortcutTabsByWindow.flatMap { windowId, tabsByPin in
            tabsByPin.map { pinId, tab in
                Entry(windowId: windowId, pinId: pinId, tab: tab)
            }
        }
        .sorted {
            if $0.windowId != $1.windowId {
                return $0.windowId.uuidString < $1.windowId.uuidString
            }
            return $0.pinId.uuidString < $1.pinId.uuidString
        }
    }
}
