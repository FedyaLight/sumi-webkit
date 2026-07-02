import Foundation

struct TabStructuralDirtySet: Sendable {
    var dirtyTabIds: Set<UUID> = []
    var dirtyFolderIds: Set<UUID> = []
    var dirtySpaceIds: Set<UUID> = []
    var deletedTabIds: Set<UUID> = []
    var deletedFolderIds: Set<UUID> = []
    var deletedSpaceIds: Set<UUID> = []
    var splitGroupsDirty = false
    var needsFullReconcileReason: String?

    var isEmpty: Bool {
        dirtyTabIds.isEmpty
            && dirtyFolderIds.isEmpty
            && dirtySpaceIds.isEmpty
            && deletedTabIds.isEmpty
            && deletedFolderIds.isEmpty
            && deletedSpaceIds.isEmpty
            && splitGroupsDirty == false
            && needsFullReconcileReason == nil
    }

    var hasIncrementalChanges: Bool {
        dirtyTabIds.isEmpty == false
            || dirtyFolderIds.isEmpty == false
            || dirtySpaceIds.isEmpty == false
            || deletedTabIds.isEmpty == false
            || deletedFolderIds.isEmpty == false
            || deletedSpaceIds.isEmpty == false
            || splitGroupsDirty
    }

    mutating func markTabsDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedTabIds.remove(id)
            dirtyTabIds.insert(id)
        }
    }

    mutating func markFoldersDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedFolderIds.remove(id)
            dirtyFolderIds.insert(id)
        }
    }

    mutating func markSpacesDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedSpaceIds.remove(id)
            dirtySpaceIds.insert(id)
        }
    }

    mutating func markTabsDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtyTabIds.remove(id)
            deletedTabIds.insert(id)
        }
    }

    mutating func markFoldersDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtyFolderIds.remove(id)
            deletedFolderIds.insert(id)
        }
    }

    mutating func markSpacesDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtySpaceIds.remove(id)
            deletedSpaceIds.insert(id)
        }
    }

    mutating func markSplitGroupsDirty() {
        splitGroupsDirty = true
    }

    mutating func requestFullReconcile(reason: String) {
        if needsFullReconcileReason == nil {
            needsFullReconcileReason = reason
        }
    }

    mutating func takePending() -> TabStructuralDirtySet {
        let pending = self
        self = TabStructuralDirtySet()
        return pending
    }

    mutating func merge(_ other: TabStructuralDirtySet) {
        dirtyTabIds.formUnion(other.dirtyTabIds)
        dirtyFolderIds.formUnion(other.dirtyFolderIds)
        dirtySpaceIds.formUnion(other.dirtySpaceIds)
        deletedTabIds.formUnion(other.deletedTabIds)
        deletedFolderIds.formUnion(other.deletedFolderIds)
        deletedSpaceIds.formUnion(other.deletedSpaceIds)
        splitGroupsDirty = splitGroupsDirty || other.splitGroupsDirty
        if let reason = other.needsFullReconcileReason {
            requestFullReconcile(reason: reason)
        }
    }
}
