import Foundation
import SumiDomain

@MainActor
final class SidebarSplitGroupLifecycleCommands {
    private let groups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let pins: ShortcutPinCollectionStateOwner
    private let pinCommands: SidebarPinCommands
    private let hostedUnload: ShortcutHostedSplitUnloadService
    private let membership: TabCollectionMembershipOwner
    private let close: BrowserTabCloseOrchestrationOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        groups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        pins: ShortcutPinCollectionStateOwner,
        pinCommands: SidebarPinCommands,
        hostedUnload: ShortcutHostedSplitUnloadService,
        membership: TabCollectionMembershipOwner,
        close: BrowserTabCloseOrchestrationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.groups = groups
        self.mutations = mutations
        self.pins = pins
        self.pinCommands = pinCommands
        self.hostedUnload = hostedUnload
        self.membership = membership
        self.close = close
        self.structuralLookup = structuralLookup
    }

    func unload(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard groups.group(id: group.id) == group else { return }
        _ = hostedUnload.unloadShortcutHostedSplitGroup(group, in: windowState)
    }

    func contextMenuActions(
        for group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> SplitGroupContextMenuActions {
        if group.container.isShortcutSidebar {
            return SplitGroupContextMenuActions(
                unload: { [weak self] in self?.unload(group, in: windowState) },
                delete: { [weak self] in self?.deleteSaved(group) }
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
        for tab in tabs {
            close.closeTab(tab, in: windowState)
        }
    }

    func deleteSaved(_ group: SplitGroup) {
        guard groups.group(id: group.id) == group,
              group.container.isShortcutSidebar else { return }
        let groupPins = group.memberIDs.compactMap { memberID -> ShortcutPin? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pins.shortcutPin(by: pinID)
        }
        guard groupPins.count == group.memberIDs.count else { return }
        structuralLookup.withTransaction {
            guard mutations.remove(group, persist: false) else { return }
            for pin in groupPins {
                precondition(
                    pinCommands.remove(pin),
                    "Validated split launcher could not be retired"
                )
            }
        }
    }
}
