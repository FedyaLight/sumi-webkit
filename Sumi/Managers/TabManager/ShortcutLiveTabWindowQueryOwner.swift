import AppKit

/// Read-only resolver for "which windows currently display or select a given tab", split
/// out of `ShortcutLiveTabOwner`. These queries walk the live window states and order the
/// results (primary window, preferred window, then the rest deterministically) but never
/// mutate anything — so they need only two collaborators (`runtimeContext`, `tab`) instead
/// of `ShortcutLiveTabOwner`'s full ~20-closure mutation surface. Keeping them here makes
/// the display/selection ordering rules readable and independently reasoned about.
@MainActor
final class ShortcutLiveTabWindowQueryOwner {
    struct Dependencies {
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let tab: @MainActor (UUID) -> Tab?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func windowIdDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> UUID? {
        windowIdsDisplaying(tabId: tabId, preferredWindowId: preferredWindowId).first
    }

    func windowIdsSelecting(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtimeContext = dependencies.runtimeContext() else { return [] }

        func windowSelectsTab(_ windowState: BrowserWindowState) -> Bool {
            windowState.currentTabId == tabId
        }

        var orderedWindowIds: [UUID] = []

        if let primaryWindowId = dependencies.tab(tabId)?.primaryWindowId,
           let primaryWindow = runtimeContext.windowState(for: primaryWindowId),
           windowSelectsTab(primaryWindow) {
            orderedWindowIds.append(primaryWindowId)
        }

        if let preferredWindowId,
           let preferredWindow = runtimeContext.windowState(for: preferredWindowId),
           windowSelectsTab(preferredWindow),
           !orderedWindowIds.contains(preferredWindowId) {
            orderedWindowIds.append(preferredWindowId)
        }

        var matchedWindowIds: [UUID] = []
        runtimeContext.forEachWindow { windowId, windowState in
            if !orderedWindowIds.contains(windowId),
               windowSelectsTab(windowState) {
                matchedWindowIds.append(windowId)
            }
        }
        orderedWindowIds.append(
            contentsOf: matchedWindowIds.sorted { $0.uuidString < $1.uuidString }
        )
        return orderedWindowIds
    }

    func windowIdsDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtimeContext = dependencies.runtimeContext() else { return [] }

        func windowDisplaysTab(_ windowId: UUID, _ windowState: BrowserWindowState) -> Bool {
            if windowState.currentTabId == tabId {
                return true
            }

            return runtimeContext.visibleSplitTabIds(for: windowId).contains(tabId)
        }

        var orderedWindowIds: [UUID] = []

        if let preferredWindowId,
           let preferredWindow = runtimeContext.windowState(for: preferredWindowId),
           windowDisplaysTab(preferredWindowId, preferredWindow) {
            orderedWindowIds.append(preferredWindowId)
        }

        if let primaryWindowId = dependencies.tab(tabId)?.primaryWindowId,
           let primaryWindow = runtimeContext.windowState(for: primaryWindowId),
           windowDisplaysTab(primaryWindowId, primaryWindow),
           !orderedWindowIds.contains(primaryWindowId) {
            orderedWindowIds.append(primaryWindowId)
        }

        var matchedWindowIds: [UUID] = []
        runtimeContext.forEachWindow { windowId, windowState in
            if !orderedWindowIds.contains(windowId),
               windowDisplaysTab(windowId, windowState) {
                matchedWindowIds.append(windowId)
            }
        }
        orderedWindowIds.append(
            contentsOf: matchedWindowIds.sorted { $0.uuidString < $1.uuidString }
        )
        return orderedWindowIds
    }

    func windowStateDisplaying(tabId: UUID) -> BrowserWindowState? {
        guard let windowId = windowIdDisplaying(tabId: tabId) else { return nil }
        return dependencies.runtimeContext()?.windowState(for: windowId)
    }
}
