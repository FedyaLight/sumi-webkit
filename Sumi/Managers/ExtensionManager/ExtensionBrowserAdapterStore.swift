import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserAdapterStore {
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    private var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    var miniWindowAdapters: [UUID: ExtensionMiniWindowAdapter] = [:]

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
        for tabId: UUID,
        create: () -> ExtensionTabAdapter?
    ) -> ExtensionTabAdapter? {
        if let existing = tabAdapters[tabId] {
            return existing
        }
        guard let created = create() else {
            return nil
        }
        tabAdapters[tabId] = created
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

    func removeMiniWindowAdapter(for sessionId: UUID) {
        miniWindowAdapters.removeValue(forKey: sessionId)
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

    func prune(liveTabIDs: Set<UUID>, liveWindowIDs: Set<UUID>) {
        tabAdapters = tabAdapters.filter { liveTabIDs.contains($0.key) }
        windowAdapters = windowAdapters.filter { liveWindowIDs.contains($0.key) }
    }

    func removeTabAndWindowAdapters() {
        tabAdapters.removeAll()
        windowAdapters.removeAll()
    }
}
