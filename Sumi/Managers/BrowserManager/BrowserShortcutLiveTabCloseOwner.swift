import Foundation

@MainActor
final class BrowserShortcutLiveTabCloseOwner {
    struct Dependencies {
        let tabManager: () -> TabManager
        let recentlyClosedManager: () -> RecentlyClosedManager
        let fallbackPlanner: () -> BrowserTabCloseFallbackPlanner
        let selectTab: (Tab, BrowserWindowState) -> Void
        let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
        let persistWindowSession: (BrowserWindowState) -> Void
        let showEmptyState: (BrowserWindowState) -> Void
        let restoreShortcutSplitMember: (UUID, SplitGroup, BrowserWindowState, Bool) -> Void
        let unloadShortcutHostedSplitGroup: (SplitGroup, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func close(_ tab: Tab, in windowState: BrowserWindowState) {
        guard tab.isShortcutLiveInstance else { return }

        let tabManager = dependencies.tabManager()
        if let group = tabManager.splitGroup(containing: tab.id)
            ?? tab.shortcutPinId.flatMap({ tabManager.splitGroup(containingPinId: $0) }) {
            if group.isShortcutHosted {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                dependencies.unloadShortcutHostedSplitGroup(group, windowState)
                return
            }
            if group.member(for: tab.id)?.isShortcutBacked == true
                || tab.shortcutPinId.flatMap({ group.member(forPinId: $0)?.isShortcutBacked }) == true {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                dependencies.restoreShortcutSplitMember(
                    tab.id,
                    group,
                    windowState,
                    false
                )
                return
            }
        }

        captureClosedShortcutLiveInstance(tab, in: windowState)

        let wasCurrent =
            windowState.currentTabId == tab.id
            || (tab.shortcutPinId != nil && windowState.currentShortcutPinId == tab.shortcutPinId)
        let fallback = wasCurrent
            ? dependencies.fallbackPlanner().fallbackAfterClosingShortcutLiveTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil

        if let fallback {
            dependencies.selectTab(fallback, windowState)
            dependencies.performImmediateVisualHandoffIfPossible(windowState)
        }

        if let pinId = tab.shortcutPinId {
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        } else {
            tabManager.deactivateShortcutLiveTab(in: windowState.id)
        }

        guard wasCurrent else {
            dependencies.persistWindowSession(windowState)
            return
        }

        if fallback != nil {
            dependencies.persistWindowSession(windowState)
            return
        }

        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.currentTabId = nil

        dependencies.showEmptyState(windowState)
    }

    private func captureClosedShortcutLiveInstance(_ tab: Tab, in windowState: BrowserWindowState) {
        let tabManager = dependencies.tabManager()
        guard let pinId = tab.shortcutPinId,
              let pin = tabManager.shortcutPin(by: pinId)
        else {
            return
        }
        dependencies.recentlyClosedManager().captureClosedShortcutLiveInstance(
            tab: tab,
            pin: pin,
            sourceWindowId: windowState.id
        )
    }
}
