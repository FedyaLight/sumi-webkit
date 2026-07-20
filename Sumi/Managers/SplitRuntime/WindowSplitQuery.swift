import Foundation
import SumiDomain

/// Read-only window projection used by tab suspension, WebKit ownership and
/// split chrome. No query mutates durable or window-local state.
@MainActor
final class WindowSplitQuery {
    private let splitGroups: SplitGroupStore
    private let regularTabs: RegularTabCollectionOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let liveShortcuts: LiveShortcutTabRegistry
    private let windows: WindowRegistry
    private let previewIsActive: @MainActor (UUID) -> Bool

    init(
        splitGroups: SplitGroupStore,
        regularTabs: RegularTabCollectionOwner,
        pins: ShortcutPinCollectionStateOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        windows: WindowRegistry,
        previewIsActive: @escaping @MainActor (UUID) -> Bool
    ) {
        self.splitGroups = splitGroups
        self.regularTabs = regularTabs
        self.pins = pins
        self.liveShortcuts = liveShortcuts
        self.windows = windows
        self.previewIsActive = previewIsActive
    }

    func group(in windowID: UUID) -> SumiDomain.SplitGroup? {
        guard let selection = windows.windows[windowID]?.splitSelection else {
            return nil
        }
        guard let group = splitGroups.group(
            id: selection.groupID
        ), group.contains(selection.activeMemberID) else {
            return nil
        }
        return group
    }

    func group(id: UUID) -> SumiDomain.SplitGroup? {
        splitGroups.group(id: id)
    }

    func resolution(in windowID: UUID) -> WindowSplitResolution {
        guard let windowState = windows.windows[windowID] else {
            return .inactive
        }
        return WindowSplitProjection(
            group: { [splitGroups] in splitGroups.group(id: $0) },
            regularTabExists: { [regularTabs] in
                regularTabs.tab(for: $0) != nil
            },
            shortcutPinExists: { [pins] in
                pins.shortcutPin(by: $0) != nil
            },
            shortcutLiveTabID: { [liveShortcuts] pinID, windowID in
                liveShortcuts.tab(
                    for: pinID,
                    in: windowID
                )?.id
            }
        ).resolve(
            selection: windowState.splitSelection,
            in: windowID
        )
    }

    func visibleTabIDs(in windowID: UUID) -> [UUID] {
        if previewIsActive(windowID) {
            return windows.windows[windowID]?.currentTabId.map { [$0] } ?? []
        }
        return resolution(in: windowID).presentation?.visibleTabIDs ?? []
    }

    func contains(tabID: UUID, in windowID: UUID) -> Bool {
        resolution(in: windowID).presentation?.contains(tabID: tabID) == true
    }

    func isActive(tabID: UUID, in windowID: UUID) -> Bool {
        resolution(in: windowID).presentation?.activeTabID == tabID
    }

    func memberID(for tabID: UUID, in windowID: UUID) -> SplitMemberID? {
        resolution(in: windowID).presentation?.memberID(for: tabID)
    }
}
