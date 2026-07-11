import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserAdapterStore {
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    private var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    private var miniWindowAdapters: [UUID: ExtensionMiniWindowAdapter] = [:]

    func existingMiniWindowAdapter(
        for sessionID: UUID
    ) -> ExtensionMiniWindowAdapter? {
        miniWindowAdapters[sessionID]
    }

    func miniWindowAdaptersSnapshot() -> [ExtensionMiniWindowAdapter] {
        Array(miniWindowAdapters.values)
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        create: () -> ExtensionMiniWindowAdapter?
    ) -> ExtensionMiniWindowAdapter? {
        if let existing = miniWindowAdapters[sessionId] {
            return existing
        }
        guard let created = create() else {
            return nil
        }
        miniWindowAdapters[sessionId] = created
        return created
    }

    func windowAdapter(
        for windowId: UUID,
        create: () -> ExtensionWindowAdapter?
    ) -> ExtensionWindowAdapter? {
        if let existing = windowAdapters[windowId] {
            return existing
        }
        guard let created = create() else {
            return nil
        }
        windowAdapters[windowId] = created
        return created
    }

    /// Non-creating identity read for lifecycle transaction validation. UI and
    /// WebExtension consumers must resolve through the published projection.
    func existingWindowAdapter(
        for windowID: UUID
    ) -> ExtensionWindowAdapter? {
        windowAdapters[windowID]
    }

    func tabAdapter(
        for tab: Tab,
        create: () -> ExtensionTabAdapter?
    ) -> ExtensionTabAdapter? {
        if let existing = tabAdapters[tab.id] {
            if existing.represents(tab) {
                return existing
            }
            guard existing.canBeReplaced(by: tab) else { return nil }
        }
        guard let created = create() else {
            return nil
        }
        tabAdapters[tab.id] = created
        return created
    }

    func removeWindowAdapter(for windowId: UUID) {
        windowAdapters.removeValue(forKey: windowId)
    }

    @discardableResult
    func removeWindowAdapter(
        for windowId: UUID,
        ifIdenticalTo expectedAdapter: ExtensionWindowAdapter
    ) -> Bool {
        guard windowAdapters[windowId] === expectedAdapter else {
            return false
        }
        windowAdapters.removeValue(forKey: windowId)
        return true
    }

    @discardableResult
    func removeMiniWindowAdapter(
        for sessionId: UUID,
        ifIdenticalTo expectedAdapter: ExtensionMiniWindowAdapter
    ) -> Bool {
        guard miniWindowAdapters[sessionId] === expectedAdapter else {
            return false
        }
        miniWindowAdapters.removeValue(forKey: sessionId)
        return true
    }

    func removeTabAdapter(for tabId: UUID) {
        tabAdapters.removeValue(forKey: tabId)
    }

    /// Removes only the adapter created by a rejected prepublication
    /// transaction. A replacement adapter for the same UUID is never evicted.
    @discardableResult
    func removeTabAdapter(
        for tabId: UUID,
        ifIdenticalTo expectedAdapter: ExtensionTabAdapter
    ) -> Bool {
        guard tabAdapters[tabId] === expectedAdapter else { return false }
        tabAdapters.removeValue(forKey: tabId)
        return true
    }

    func prune(liveTabs: [Tab], liveWindowIDs: Set<UUID>) {
        let liveTabsByID = Dictionary(
            liveTabs.map { ($0.id, $0) },
            uniquingKeysWith: { _, current in current }
        )
        tabAdapters = tabAdapters.filter { tabID, adapter in
            guard let liveTab = liveTabsByID[tabID] else { return false }
            return adapter.represents(liveTab)
        }
        windowAdapters = windowAdapters.filter { liveWindowIDs.contains($0.key) }
    }

    func removeTabAndWindowAdapters() {
        tabAdapters.removeAll()
        windowAdapters.removeAll()
    }
}
