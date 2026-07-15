import Foundation

@MainActor
final class TabStructuralCollectionSnapshotStore {
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

    func capture() -> TabStructuralMutationTransaction.Snapshot {
        let folderSnapshot = folders.foldersBySpaceSnapshot()
        return TabStructuralMutationTransaction.Snapshot(
            tabs: regularTabs.tabsBySpaceSnapshot(),
            folders: folderSnapshot,
            pinned: shortcutPins.pinnedByProfileSnapshot(),
            spacePinned: shortcutPins.spacePinnedShortcutsSnapshot(),
            folderReceipts: folderSnapshot.values.flatMap(\.self).map(
                TabStructuralMutationTransaction.FolderReceipt.init
            )
        )
    }

    func restore(_ snapshot: TabStructuralMutationTransaction.Snapshot) {
        snapshot.folderReceipts.forEach { $0.restore() }
        regularTabs.replaceTabsBySpace(snapshot.tabs, publish: false)
        folders.replaceFoldersBySpace(snapshot.folders)
        shortcutPins.replacePinnedByProfile(snapshot.pinned)
        shortcutPins.replaceSpacePinnedShortcuts(snapshot.spacePinned)
    }

    func matches(_ expected: TabStructuralMutationTransaction.Snapshot) -> Bool {
        let current = capture()
        return Self.sameObjects(current.tabs, expected.tabs)
            && Self.sameObjects(current.folders, expected.folders)
            && Self.sameObjects(current.pinned, expected.pinned)
            && Self.sameObjects(current.spacePinned, expected.spacePinned)
            && expected.folderReceipts.allSatisfy { $0.acceptsCurrent() }
    }

    private static func sameObjects<T: AnyObject>(
        _ lhs: [UUID: [T]],
        _ rhs: [UUID: [T]]
    ) -> Bool {
        guard Set(lhs.keys) == Set(rhs.keys) else { return false }
        return lhs.allSatisfy { key, items in
            guard let expected = rhs[key], items.count == expected.count else {
                return false
            }
            return zip(items, expected).allSatisfy { $0 === $1 }
        }
    }
}
