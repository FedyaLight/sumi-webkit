import Foundation

/// Owns per-window selection history: recently selected regular tabs and the
/// mixed tab/shortcut selection history used as a close-tab fallback.
@MainActor
@Observable
final class WindowSelectionHistoryOwner {
    private static let historyLimit = 20

    /// Most recently selected regular tabs for each space (most recent first)
    var recentRegularTabIdsBySpace: [UUID: [UUID]] = [:]

    /// Most recently selected tabs and live shortcuts for each space, used only as a close-tab fallback.
    var recentSelectionItemsBySpace: [UUID: [BrowserWindowSelectionHistoryItem]] = [:]

    func recordRegularTabSelection(_ tabId: UUID, in spaceId: UUID) {
        var history = recentRegularTabIdsBySpace[spaceId] ?? []
        history.removeAll { $0 == tabId }
        history.insert(tabId, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        recentRegularTabIdsBySpace[spaceId] = history
    }

    func removeFromRegularTabHistory(_ tabId: UUID) {
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
    func recordSelection(_ item: BrowserWindowSelectionHistoryItem, in spaceId: UUID) -> Bool {
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

    func removeFromShortcutLiveSelectionHistory(_ pinId: UUID) {
        removeFromSelectionHistory { item in
            if case let .shortcutPin(historyPinId) = item {
                return historyPinId == pinId
            }
            return false
        }
    }

    private func removeFromSelectionHistory(_ shouldRemove: (BrowserWindowSelectionHistoryItem) -> Bool) {
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
