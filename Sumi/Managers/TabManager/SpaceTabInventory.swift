import Foundation

/// Complete live-tab snapshot for one Space. Keeping the four storage
/// categories explicit prevents new transient surfaces from being mistaken
/// for regular persisted tabs during destructive operations.
@MainActor
struct SpaceTabInventory {
    let regular: [Tab]
    let transientShortcutEntries: [LiveShortcutTabEntry]
    let transientExtensions: [Tab]
    let auxiliaryMiniWindows: [Tab]

    init(spaceId: UUID, state: TabStateStore) {
        regular = state.regularTabs.tabs(in: spaceId)
        transientShortcutEntries = state.transientTabs
            .liveShortcutEntries(presentedInSpace: spaceId)
        transientExtensions = state.transientTabs
            .transientExtensionTabsByID.values.filter { $0.spaceId == spaceId }
        auxiliaryMiniWindows = state.transientTabs
            .auxiliaryMiniWindowTabsByID.values.filter { $0.spaceId == spaceId }
    }

    var all: [Tab] {
        var seen = Set<UUID>()
        return (
            regular
                + transientShortcutEntries.map(\.tab)
                + transientExtensions
                + auxiliaryMiniWindows
        ).filter { seen.insert($0.id).inserted }
    }

    var tabIds: Set<UUID> { Set(all.map(\.id)) }

    var retiredShortcutPinIDsByWindow: [UUID: Set<UUID>] {
        Dictionary(grouping: transientShortcutEntries, by: \.windowId)
            .mapValues { Set($0.map(\.pinId)) }
    }
}
