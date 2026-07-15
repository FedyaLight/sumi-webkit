import Foundation

public struct WindowSelectionHistory: Equatable, Sendable {
    private static let historyLimit = 20

    /// Most recently selected regular tabs for each space (most recent first).
    public var recentRegularTabIdsBySpace: [UUID: [UUID]] = [:]

    /// Most recently selected tabs and live shortcuts for each space, used only as a close-tab fallback.
    public var recentSelectionItemsBySpace: [UUID: [BrowserWindowSelectionHistoryItem]] = [:]

    public init() {}

    public mutating func recordRegularTabSelection(_ tabId: UUID, in spaceId: UUID) {
        var history = recentRegularTabIdsBySpace[spaceId] ?? []
        history.removeAll { $0 == tabId }
        history.insert(tabId, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        recentRegularTabIdsBySpace[spaceId] = history
    }

    public mutating func removeFromRegularTabHistory(_ tabId: UUID) {
        for (spaceId, history) in recentRegularTabIdsBySpace {
            recentRegularTabIdsBySpace[spaceId] = history.filter { $0 != tabId }
        }
        removeFromSelectionHistory { item in
            if case let .regularTab(historyTabId) = item {
                return historyTabId == tabId
            }
            return false
        }
    }

    @discardableResult
    public mutating func recordSelection(
        _ item: BrowserWindowSelectionHistoryItem,
        in spaceId: UUID
    ) -> Bool {
        let previous = recentSelectionItemsBySpace[spaceId] ?? []
        var history = previous
        history.removeAll { $0 == item }
        history.insert(item, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        recentSelectionItemsBySpace[spaceId] = history
        return history != previous
    }

    public mutating func removeFromShortcutLiveSelectionHistory(_ pinId: UUID) {
        removeFromSelectionHistory { item in
            if case let .shortcutPin(historyPinId) = item {
                return historyPinId == pinId
            }
            return false
        }
    }

    @discardableResult
    public mutating func removeReferences(
        toSpaceID spaceID: UUID,
        tabIDs: Set<UUID>,
        shortcutPinIDs: Set<UUID>
    ) -> Bool {
        let previous = self
        recentRegularTabIdsBySpace = recentRegularTabIdsBySpace.reduce(
            into: [:]
        ) { result, entry in
            guard entry.key != spaceID else { return }
            let remaining = entry.value.filter { !tabIDs.contains($0) }
            if !remaining.isEmpty { result[entry.key] = remaining }
        }
        recentSelectionItemsBySpace = recentSelectionItemsBySpace.reduce(
            into: [:]
        ) { result, entry in
            guard entry.key != spaceID else { return }
            let remaining = entry.value.filter { item in
                switch item {
                case .regularTab(let tabID):
                    return !tabIDs.contains(tabID)
                case .shortcutPin(let pinID):
                    return !shortcutPinIDs.contains(pinID)
                }
            }
            if !remaining.isEmpty { result[entry.key] = remaining }
        }
        return self != previous
    }

    private mutating func removeFromSelectionHistory(
        _ shouldRemove: (BrowserWindowSelectionHistoryItem) -> Bool
    ) {
        for (spaceId, history) in recentSelectionItemsBySpace {
            let filtered = history.filter { !shouldRemove($0) }
            if filtered.isEmpty {
                recentSelectionItemsBySpace.removeValue(forKey: spaceId)
            } else {
                recentSelectionItemsBySpace[spaceId] = filtered
            }
        }
    }
}
