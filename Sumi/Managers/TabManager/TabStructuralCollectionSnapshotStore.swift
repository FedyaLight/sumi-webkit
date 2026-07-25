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
            pendingPinnedWithoutProfile: shortcutPins.pendingPinnedWithoutProfileSnapshot(),
            folderReceipts: folderSnapshot.values.flatMap(\.self).map(
                TabStructuralMutationTransaction.FolderReceipt.init
            )
        )
    }

    func restore(
        _ snapshot: TabStructuralMutationTransaction.Snapshot
    ) -> [UUID: [UUID: Bool]] {
        var restoredExpansionBySpaceID: [UUID: [UUID: Bool]] = [:]
        for receipt in snapshot.folderReceipts where receipt.restore() {
            restoredExpansionBySpaceID[receipt.folder.spaceId, default: [:]][
                receipt.folder.id
            ] = receipt.isOpen
        }
        regularTabs.replaceTabsBySpace(snapshot.tabs, publish: false)
        folders.replaceFoldersBySpace(snapshot.folders)
        shortcutPins.replaceAll(
            pinnedByProfile: snapshot.pinned,
            spacePinnedShortcuts: snapshot.spacePinned,
            pendingPinnedWithoutProfile: snapshot.pendingPinnedWithoutProfile
        )
        return restoredExpansionBySpaceID
    }

    func restoreUncontended(
        source: TabStructuralMutationTransaction.Snapshot,
        target: TabStructuralMutationTransaction.Snapshot
    ) -> [UUID: [UUID: Bool]] {
        let current = capture()
        let restoredFolderKeys = restorableFolderKeys(
            current: current,
            source: source,
            target: target
        )
        let mergedFolders = Self.restoringUncontended(
            current: current.folders,
            source: source.folders,
            target: target.folders,
            eligibleKeys: restoredFolderKeys
        )
        let sourceFolderReceipts: [
            ObjectIdentifier: TabStructuralMutationTransaction.FolderReceipt
        ] = source.folderReceipts.reduce(into: [:]) {
            $0[ObjectIdentifier($1.folder)] = $1
        }
        var restoredExpansionBySpaceID: [UUID: [UUID: Bool]] = [:]
        restoredFolderKeys.forEach { key in
            source.folders[key]?.forEach { folder in
                guard let receipt = sourceFolderReceipts[ObjectIdentifier(folder)],
                      receipt.restore() else { return }
                restoredExpansionBySpaceID[receipt.folder.spaceId, default: [:]][
                    receipt.folder.id
                ] = receipt.isOpen
            }
        }

        regularTabs.replaceTabsBySpace(
            Self.restoringUncontended(
                current: current.tabs,
                source: source.tabs,
                target: target.tabs
            ),
            publish: false
        )
        folders.replaceFoldersBySpace(mergedFolders)
        shortcutPins.replaceAll(
            pinnedByProfile: Self.restoringUncontended(
                current: current.pinned,
                source: source.pinned,
                target: target.pinned
            ),
            spacePinnedShortcuts: Self.restoringUncontended(
                current: current.spacePinned,
                source: source.spacePinned,
                target: target.spacePinned
            ),
            pendingPinnedWithoutProfile: Self.sameObjects(
                current.pendingPinnedWithoutProfile,
                target.pendingPinnedWithoutProfile
            ) ? source.pendingPinnedWithoutProfile
                : current.pendingPinnedWithoutProfile
        )
        return restoredExpansionBySpaceID
    }

    func matches(_ expected: TabStructuralMutationTransaction.Snapshot) -> Bool {
        let current = capture()
        return Self.sameObjects(current.tabs, expected.tabs)
            && Self.sameObjects(current.folders, expected.folders)
            && Self.sameObjects(current.pinned, expected.pinned)
            && Self.sameObjects(current.spacePinned, expected.spacePinned)
            && Self.sameObjects(
                current.pendingPinnedWithoutProfile,
                expected.pendingPinnedWithoutProfile
            )
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

    private static func sameObjects<T: AnyObject>(
        _ lhs: [T],
        _ rhs: [T]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private func restorableFolderKeys(
        current: TabStructuralMutationTransaction.Snapshot,
        source: TabStructuralMutationTransaction.Snapshot,
        target: TabStructuralMutationTransaction.Snapshot
    ) -> Set<UUID> {
        let targetReceipts: [
            ObjectIdentifier: TabStructuralMutationTransaction.FolderReceipt
        ] = target.folderReceipts.reduce(into: [:]) {
            $0[ObjectIdentifier($1.folder)] = $1
        }
        let sourceReceipts: [
            ObjectIdentifier: TabStructuralMutationTransaction.FolderReceipt
        ] = source.folderReceipts.reduce(into: [:]) {
            $0[ObjectIdentifier($1.folder)] = $1
        }
        let keys = Set(current.folders.keys)
            .union(source.folders.keys)
            .union(target.folders.keys)
        return keys.filter { key in
            guard Self.sameOptionalObjects(
                current.folders[key],
                target.folders[key]
            ) else { return false }
            let targetFolders = target.folders[key, default: []]
            guard targetFolders.allSatisfy({ folder in
                targetReceipts[ObjectIdentifier(folder)]?.acceptsCurrent() == true
            }) else { return false }
            let targetIdentities = Set(targetFolders.map(ObjectIdentifier.init))
            return source.folders[key, default: []].allSatisfy { folder in
                let identity = ObjectIdentifier(folder)
                return targetIdentities.contains(identity)
                    || sourceReceipts[identity]?.acceptsCurrent() == true
            }
        }
    }

    private static func restoringUncontended<T: AnyObject>(
        current: [UUID: [T]],
        source: [UUID: [T]],
        target: [UUID: [T]],
        eligibleKeys: Set<UUID>? = nil
    ) -> [UUID: [T]] {
        var result = current
        let keys = Set(current.keys).union(source.keys).union(target.keys)
        for key in keys where eligibleKeys?.contains(key) ?? true {
            guard sameOptionalObjects(current[key], target[key]) else {
                continue
            }
            if let sourceItems = source[key] {
                result[key] = sourceItems
            } else {
                result.removeValue(forKey: key)
            }
        }
        return result
    }

    private static func sameOptionalObjects<T: AnyObject>(
        _ lhs: [T]?,
        _ rhs: [T]?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            return sameObjects(lhs, rhs)
        case (.some, nil), (nil, .some):
            return false
        }
    }
}
