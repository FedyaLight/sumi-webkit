import Foundation

/// Owns the lifecycle of the empty-split placeholder tab per window: registration when an
/// empty split is created, replacement with a real tab committed from the floating bar,
/// and cancellation, keeping the placeholder registry consistent with the split groups.
@MainActor
final class SplitEmptyPlaceholderOwner {
    private let tabManager: @MainActor () -> TabManager?
    private let membershipResolution: SplitMembershipResolutionOwner
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let notifyChanged: @MainActor (UUID) -> Void

    private var placeholderTabIdsByWindow: [UUID: UUID] = [:]

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        membershipResolution: SplitMembershipResolutionOwner,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        notifyChanged: @escaping @MainActor (UUID) -> Void
    ) {
        self.tabManager = tabManager
        self.membershipResolution = membershipResolution
        self.selectTab = selectTab
        self.notifyChanged = notifyChanged
    }

    func registerPlaceholder(tabId: UUID, for windowId: UUID) {
        placeholderTabIdsByWindow[windowId] = tabId
    }

    func commitPlaceholder(tabId: UUID, in windowState: BrowserWindowState) {
        guard placeholderTabIdsByWindow[windowState.id] == tabId else { return }
        placeholderTabIdsByWindow.removeValue(forKey: windowState.id)
    }

    @discardableResult
    func replacePlaceholder(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = placeholderTabIdsByWindow[windowState.id],
              let tabManager = tabManager(),
              let group = tabManager.splitGroup(containing: placeholderTabId),
              group.contains(placeholderTabId)
        else { return false }

        placeholderTabIdsByWindow.removeValue(forKey: windowState.id)
        guard let resolved = membershipResolution.resolvedSplitTab(
            tab,
            host: group.host,
            sourceGroup: nil,
            in: windowState
        ) else {
            return false
        }
        let updated = SplitGroup(
            id: group.id,
            layoutKind: group.layoutKind,
            layoutTree: group.layoutTree.replacingTab(placeholderTabId, with: resolved.tab.id),
            activeTabId: resolved.tab.id,
            host: group.host,
            members: group.removingMember(tabId: placeholderTabId).members + [resolved.member]
        )

        tabManager.upsertSplitGroup(updated)
        if placeholderTabId != resolved.tab.id {
            tabManager.removeTab(placeholderTabId)
        }
        selectTab(resolved.tab, windowState)
        notifyChanged(windowState.id)
        return true
    }

    @discardableResult
    func cancelPlaceholder(in windowState: BrowserWindowState) -> Bool {
        guard let placeholderTabId = placeholderTabIdsByWindow.removeValue(forKey: windowState.id),
              tabManager()?.tab(for: placeholderTabId) != nil
        else { return false }

        tabManager()?.removeTab(placeholderTabId)
        notifyChanged(windowState.id)
        return true
    }

    func cleanupWindow(_ windowId: UUID) {
        placeholderTabIdsByWindow.removeValue(forKey: windowId)
    }
}
