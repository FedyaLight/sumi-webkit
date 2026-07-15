import Foundation

@MainActor
final class TabStructuralCollectionStore {
    private let regularTabs: RegularTabCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let shortcutPins: ShortcutPinCollectionStateOwner

    init(
        regularTabs: RegularTabCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        shortcutPins: ShortcutPinCollectionStateOwner
    ) {
        self.regularTabs = regularTabs
        self.folders = folders
        self.shortcutPins = shortcutPins
    }

    func tabs(for spaceID: UUID) -> [Tab] {
        regularTabs.tabsBySpaceSnapshot()[spaceID] ?? []
    }

    func folders(for spaceID: UUID) -> [TabFolder] {
        folders.foldersBySpaceSnapshot()[spaceID] ?? []
    }

    func profilePins(for profileID: UUID) -> [ShortcutPin] {
        shortcutPins.pinnedByProfileSnapshot()[profileID] ?? []
    }

    func spacePins(for spaceID: UUID) -> [ShortcutPin] {
        shortcutPins.spacePinnedShortcutsSnapshot()[spaceID] ?? []
    }

    func replaceTabs(_ tabs: [Tab], for spaceID: UUID) {
        var snapshot = regularTabs.tabsBySpaceSnapshot()
        snapshot[spaceID] = tabs
        regularTabs.replaceTabsBySpace(snapshot, publish: false)
    }

    func replaceFolders(_ items: [TabFolder], for spaceID: UUID) {
        var snapshot = folders.foldersBySpaceSnapshot()
        snapshot[spaceID] = items
        folders.replaceFoldersBySpace(snapshot)
    }

    func replaceProfilePins(_ pins: [ShortcutPin], for profileID: UUID) {
        var snapshot = shortcutPins.pinnedByProfileSnapshot()
        snapshot[profileID] = pins
        shortcutPins.replacePinnedByProfile(snapshot)
    }

    func replaceSpacePins(_ pins: [ShortcutPin], for spaceID: UUID) {
        var snapshot = shortcutPins.spacePinnedShortcutsSnapshot()
        snapshot[spaceID] = pins
        shortcutPins.replaceSpacePinnedShortcuts(snapshot)
    }

    func allPins() -> [ShortcutPin] {
        shortcutPins.pinnedByProfileSnapshot().values.flatMap(\.self)
            + shortcutPins.spacePinnedShortcutsSnapshot().values.flatMap(\.self)
    }
}
