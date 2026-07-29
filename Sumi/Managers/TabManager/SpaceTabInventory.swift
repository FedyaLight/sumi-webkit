import Foundation

@MainActor
struct SpaceTabInventory {
    let regular: [Tab]
    let transientShortcutEntries: [LiveShortcutTabEntry]
    let transientExtensions: [Tab]
    let auxiliaryMiniWindows: [Tab]
    let all: [Tab]
    let tabIds: Set<UUID>
    let retiredShortcutPinIDsByWindow: [UUID: Set<UUID>]
    init(spaceId: UUID, state: TabStateStore) {
        let regular = state.regularTabs.tabs(in: spaceId)
        let transientShortcutEntries = state.transientTabs
            .liveShortcutEntries(presentedInSpace: spaceId)
        let transientExtensions = state.transientTabs
            .transientExtensionTabsByID.values.filter { $0.spaceId == spaceId }
        let auxiliaryMiniWindows = state.transientTabs
            .auxiliaryMiniWindowTabsByID.values.filter { $0.spaceId == spaceId }
        var seen = Set<UUID>()
        let all = (
            regular
                + transientShortcutEntries.map(\.tab)
                + transientExtensions
                + auxiliaryMiniWindows
        ).filter { seen.insert($0.id).inserted }

        self.regular = regular
        self.transientShortcutEntries = transientShortcutEntries
        self.transientExtensions = transientExtensions
        self.auxiliaryMiniWindows = auxiliaryMiniWindows
        self.all = all
        self.tabIds = Set(all.map(\.id))
        self.retiredShortcutPinIDsByWindow = Dictionary(
            grouping: transientShortcutEntries,
            by: \.windowId
        )
            .mapValues { Set($0.map(\.pinId)) }
    }
}
