import Foundation
import SumiDomain

@MainActor
final class SidebarSplitGroupLifecycleCommands {
    private let groups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let pinCommands: SidebarPinCommands
    private let hostedUnload: ShortcutHostedSplitUnloadService
    private let membership: TabCollectionMembershipOwner
    private let close: BrowserTabCloseOrchestrationOwner
    private let notifications: any BrowserNotificationPresenting

    init(
        groups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner,
        pinCommands: SidebarPinCommands,
        hostedUnload: ShortcutHostedSplitUnloadService,
        membership: TabCollectionMembershipOwner,
        close: BrowserTabCloseOrchestrationOwner,
        notifications: any BrowserNotificationPresenting
    ) {
        self.groups = groups
        self.pins = pins
        self.pinCommands = pinCommands
        self.hostedUnload = hostedUnload
        self.membership = membership
        self.close = close
        self.notifications = notifications
    }

    func unload(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard groups.group(id: group.id) == group else { return }
        guard let result = hostedUnload.unloadShortcutHostedSplitGroup(
            group,
            in: windowState
        ) else { return }
        notifications.presentSplitViewUnloadedNotification(
            tabCount: result.unloadedTabCount,
            in: windowState
        )
    }

    func contextMenuActions(
        for group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> SplitGroupContextMenuActions {
        if group.container.isShortcutSidebar {
            return SplitGroupContextMenuActions(
                unload: { [weak self] in self?.unload(group, in: windowState) },
                delete: { [weak self] in
                    self?.deleteSaved(group, in: windowState)
                }
            )
        }
        return SplitGroupContextMenuActions(
            close: { [weak self] in self?.closeRegular(group, in: windowState) }
        )
    }

    func closeRegular(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard groups.group(id: group.id) == group,
              case .regularTabs = group.container else { return }
        let tabs = group.memberIDs.compactMap { memberID -> Tab? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return membership.tab(for: tabID)
        }
        guard tabs.count == group.memberIDs.count else { return }
        close.closeSplitGroup(tabs, in: windowState)
    }

    func deleteSaved(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) {
        guard groups.group(id: group.id) == group,
              group.container.isShortcutSidebar else { return }
        let groupPins = group.memberIDs.compactMap { memberID -> ShortcutPin? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pins.shortcutPin(by: pinID)
        }
        guard groupPins.count == group.memberIDs.count else { return }
        guard pinCommands.remove(
            groupPins,
            presentNotification: false
        ) else { return }
        notifications.presentSavedSplitViewDeletionNotification(
            tabCount: groupPins.count,
            in: windowState
        )
    }
}
