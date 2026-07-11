import Foundation

/// Complete live-tab snapshot for one Space. Keeping the four storage
/// categories explicit prevents new transient surfaces from being mistaken
/// for regular persisted tabs during destructive operations.
@MainActor
struct SpaceTabInventory {
    let regular: [Tab]
    let transientShortcuts: [Tab]
    let transientExtensions: [Tab]
    let auxiliaryMiniWindows: [Tab]

    init(spaceId: UUID, state: TabStateStore) {
        regular = state.regularTabs.tabs(in: spaceId)
        transientShortcuts = state.transientTabs
            .transientShortcutTabs(inSpace: spaceId)
        transientExtensions = state.transientTabs
            .transientExtensionTabsByID.values.filter { $0.spaceId == spaceId }
        auxiliaryMiniWindows = state.transientTabs
            .auxiliaryMiniWindowTabsByID.values.filter { $0.spaceId == spaceId }
    }

    var all: [Tab] {
        var seen = Set<UUID>()
        return (
            regular
                + transientShortcuts
                + transientExtensions
                + auxiliaryMiniWindows
        ).filter { seen.insert($0.id).inserted }
    }

    var tabIds: Set<UUID> { Set(all.map(\.id)) }
}
