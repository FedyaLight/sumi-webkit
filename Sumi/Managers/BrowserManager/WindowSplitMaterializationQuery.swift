import Foundation
import SumiDomain

@MainActor
final class WindowSplitMaterializationQuery {
    private let splitGroups: SplitGroupStore
    private let regularTabs: RegularTabCollectionOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let liveShortcuts: LiveShortcutTabRegistry

    init(
        splitGroups: SplitGroupStore,
        regularTabs: RegularTabCollectionOwner,
        pins: ShortcutPinCollectionStateOwner,
        liveShortcuts: LiveShortcutTabRegistry
    ) {
        self.splitGroups = splitGroups
        self.regularTabs = regularTabs
        self.pins = pins
        self.liveShortcuts = liveShortcuts
    }

    func containsExact(_ group: SumiDomain.SplitGroup) -> Bool {
        splitGroups.group(id: group.id) == group
    }

    func projection() -> WindowSplitProjection {
        WindowSplitProjection(
            group: { [splitGroups] in splitGroups.group(id: $0) },
            regularTabExists: { [regularTabs] in
                regularTabs.tab(for: $0) != nil
            },
            shortcutPinExists: { [pins] in
                pins.shortcutPin(by: $0) != nil
            },
            shortcutLiveTabID: { [liveShortcuts] pinID, windowID in
                liveShortcuts.tab(for: pinID, in: windowID)?.id
            }
        )
    }

    func activeTab(
        for memberID: SplitMemberID,
        in windowID: UUID
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            return regularTabs.tab(for: tabID)
        case .shortcutPin(let pinID):
            return liveShortcuts.tab(for: pinID, in: windowID)
        }
    }
}
