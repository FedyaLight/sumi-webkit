import Foundation

@MainActor
final class BrowserShortcutLiveTabCloseOwner {
    private let tabManager: () -> TabManager
    private let recentlyClosedManager: () -> RecentlyClosedManager
    private let fallbackPlanner: () -> BrowserTabCloseFallbackPlanner
    private let selectTab: (Tab, BrowserWindowState) -> Void
    private let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void
    private let showEmptyState: (BrowserWindowState) -> Void
    private let restoreShortcutSplitMember: (UUID, SplitGroup, BrowserWindowState, Bool) -> Void
    private let unloadShortcutHostedSplitGroup: (SplitGroup, BrowserWindowState) -> Void
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        tabManager: @escaping () -> TabManager,
        recentlyClosedManager: @escaping () -> RecentlyClosedManager,
        fallbackPlanner: @escaping () -> BrowserTabCloseFallbackPlanner,
        selectTab: @escaping (Tab, BrowserWindowState) -> Void,
        performImmediateVisualHandoffIfPossible: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void,
        restoreShortcutSplitMember: @escaping (UUID, SplitGroup, BrowserWindowState, Bool) -> Void,
        unloadShortcutHostedSplitGroup: @escaping (SplitGroup, BrowserWindowState) -> Void,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.tabManager = tabManager
        self.recentlyClosedManager = recentlyClosedManager
        self.fallbackPlanner = fallbackPlanner
        self.selectTab = selectTab
        self.performImmediateVisualHandoffIfPossible = performImmediateVisualHandoffIfPossible
        self.persistWindowSession = persistWindowSession
        self.showEmptyState = showEmptyState
        self.restoreShortcutSplitMember = restoreShortcutSplitMember
        self.unloadShortcutHostedSplitGroup = unloadShortcutHostedSplitGroup
        self.notifications = notifications
    }

    func close(_ tab: Tab, in windowState: BrowserWindowState) {
        guard tab.isShortcutLiveInstance else { return }

        let tabManager = tabManager()
        if let group = tabManager.splitGroupStructureOwner.splitGroup(containing: tab.id)
            ?? tab.shortcutPinId.flatMap({ tabManager.splitGroupStructureOwner.splitGroup(containingPinId: $0) }) {
            if group.isShortcutHosted {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                unloadShortcutHostedSplitGroup(group, windowState)
                notifications()?.presentTabUnloadedNotification(count: 1, in: windowState)
                return
            }
            if group.member(for: tab.id)?.isShortcutBacked == true
                || tab.shortcutPinId.flatMap({ group.member(forPinId: $0)?.isShortcutBacked }) == true {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                restoreShortcutSplitMember(
                    tab.id,
                    group,
                    windowState,
                    false
                )
                notifications()?.presentTabUnloadedNotification(count: 1, in: windowState)
                return
            }
        }

        captureClosedShortcutLiveInstance(tab, in: windowState)

        let wasCurrent =
            windowState.currentTabId == tab.id
            || (tab.shortcutPinId != nil && windowState.currentShortcutPinId == tab.shortcutPinId)
        let fallback = wasCurrent
            ? fallbackPlanner().fallbackAfterClosingShortcutLiveTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil

        if let fallback {
            selectTab(fallback, windowState)
            performImmediateVisualHandoffIfPossible(windowState)
        }

        let didDeactivate: Bool
        if let pinId = tab.shortcutPinId {
            didDeactivate = tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(
                pinId: pinId,
                in: windowState.id
            )
        } else {
            didDeactivate = tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(in: windowState.id)
        }

        if didDeactivate {
            notifications()?.presentTabUnloadedNotification(count: 1, in: windowState)
        }

        guard wasCurrent else {
            persistWindowSession(windowState)
            return
        }

        if fallback != nil {
            persistWindowSession(windowState)
            return
        }

        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.currentTabId = nil

        showEmptyState(windowState)
    }

    private func captureClosedShortcutLiveInstance(_ tab: Tab, in windowState: BrowserWindowState) {
        let tabManager = tabManager()
        guard let pinId = tab.shortcutPinId,
              let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
        else {
            return
        }
        recentlyClosedManager().captureClosedShortcutLiveInstance(
            tab: tab,
            pin: pin,
            sourceWindowId: windowState.id
        )
    }
}
