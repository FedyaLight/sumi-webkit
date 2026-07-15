import Foundation
import SumiDomain

@MainActor
final class ShortcutLiveTabCloseService {
    private let tabManager: () -> TabManager?
    private let recentlyClosedManager: () -> RecentlyClosedManager
    private let fallbackPlanner: () -> BrowserTabCloseFallbackPlanner
    private let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
    private let splitShortcuts: () -> SplitShortcutServices?
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        tabManager: @escaping () -> TabManager?,
        recentlyClosedManager: @escaping () -> RecentlyClosedManager,
        fallbackPlanner: @escaping () -> BrowserTabCloseFallbackPlanner,
        performImmediateVisualHandoffIfPossible: @escaping (BrowserWindowState) -> Void,
        splitShortcuts: @escaping () -> SplitShortcutServices?,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.tabManager = tabManager
        self.recentlyClosedManager = recentlyClosedManager
        self.fallbackPlanner = fallbackPlanner
        self.performImmediateVisualHandoffIfPossible = performImmediateVisualHandoffIfPossible
        self.splitShortcuts = splitShortcuts
        self.notifications = notifications
    }

    @discardableResult
    func close(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        presentNotification: Bool = true
    ) -> Bool {
        guard tab.isShortcutLiveInstance,
              let pinId = tab.shortcutPinId,
              let tabManager = tabManager() else { return false }
        if let group = tabManager.splitGroupStore.group(
            containing: .shortcutPin(pinId)
        ) {
            if group.container.isShortcutSidebar {
                guard let hostedUnload = splitShortcuts()?.hostedUnload,
                      hostedUnload.unloadShortcutHostedSplitGroup(
                          group,
                          in: windowState
                      ) else { return false }
                captureClosedShortcutLiveInstance(tab, in: windowState, tabManager: tabManager)
                if presentNotification {
                    notifications()?.presentTabUnloadedNotification(
                        count: 1,
                        in: windowState
                    )
                }
                return true
            }
            guard let memberRestoration = splitShortcuts()?.memberRestoration,
                  memberRestoration.restoreShortcutSplitMember(
                      .shortcutPin(pinId),
                      from: group,
                      in: windowState,
                      preserveLiveInstance: false
                  ) else { return false }
            captureClosedShortcutLiveInstance(tab, in: windowState, tabManager: tabManager)
            if presentNotification {
                notifications()?.presentTabUnloadedNotification(
                    count: 1,
                    in: windowState
                )
            }
            return true
        }

        let wasCurrent = ShortcutSelectionIdentity.isSelected(
            tabId: tab.id,
            pinId: tab.shortcutPinId,
            in: windowState
        )
        let fallback = wasCurrent
            ? fallbackPlanner().fallbackAfterClosingShortcutLiveTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil

        var target = windowState.unpublishedShortcutMutationState
        if wasCurrent, let fallback {
            _ = WindowTabSelectionStateApplicator.apply(
                fallback,
                to: &target,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        } else if wasCurrent {
            target.currentTabId = nil
            target.currentShortcutPinId = nil
            target.currentShortcutPinRole = nil
            target.isShowingEmptyState = true
        }
        let preparedRetirement = tabManager.structuralLookupCoordinator
            .withTransaction {
                tabManager.shortcutLiveTabRetirement.prepareRetirement(
                    pinId: pinId,
                    in: windowState.id,
                    targetWindowState: target
                )
            }
        guard let preparedRetirement else { return false }
        let retirement = preparedRetirement.result
        guard retirement.didRetire else { return false }

        captureClosedShortcutLiveInstance(tab, in: windowState, tabManager: tabManager)

        if wasCurrent {
            performImmediateVisualHandoffIfPossible(windowState)
        }
        _ = tabManager.shortcutLiveTabRetirement.finish(preparedRetirement)

        if retirement.didRetire, presentNotification {
            notifications()?.presentTabUnloadedNotification(count: 1, in: windowState)
        }

        return retirement.didRetire
    }

    private func captureClosedShortcutLiveInstance(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) {
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
