import Foundation
import OSLog

/// Pure structural-validity policy for tab snapshot persistence, extracted from
/// `TabSnapshotRepository`. Given a full `Snapshot` or an incremental `StructuralDelta`,
/// it throws `TabSnapshotRepository.PersistenceError.invalidModelState` when the shape
/// violates the persistence invariants (negative indexes, duplicate ids, a tab that is
/// both pinned and space-pinned, orphaned or cyclic folder hierarchies, split groups that
/// don't survive sanitization, …).
///
/// This is deliberately free of persistence *mechanism*: no `ModelContext`, no actor
/// state, no error classification. Those stay in `TabSnapshotRepository` (the `upsert*`
/// writes, `validateDataIntegrity`, `classify`). Separating the "what is valid" policy
/// from "how we write" makes the invariants unit-testable without a store.
enum TabSnapshotValidator {
    private static let log = Logger.sumi(category: "TabPersistence")

    static func validateDelta(_ delta: TabSnapshotRepository.StructuralDelta) throws {
        if delta.tabs.contains(where: { $0.index < 0 })
            || delta.folders.contains(where: { $0.index < 0 })
            || delta.spaces.contains(where: { $0.index < 0 }) {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }

        let tabIDs = Set(delta.tabs.map(\.id))
        if tabIDs.count != delta.tabs.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }

        let folderIDs = Set(delta.folders.map(\.id))
        if folderIDs.count != delta.folders.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }

        let spaceIDs = Set(delta.spaces.map(\.id))
        if spaceIDs.count != delta.spaces.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }

        for tab in delta.tabs {
            if tab.isPinned && tab.isSpacePinned {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if let spaceId = tab.spaceId, delta.deletedSpaceIds.contains(spaceId) {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
        }

        if let splitGroups = delta.splitGroups {
            try validateSplitGroups(splitGroups)
        }

        for folder in delta.folders where delta.deletedSpaceIds.contains(folder.spaceId) {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
        try validateFolderHierarchy(delta.folders, requiresCompleteParentSet: false)
    }

    static func validateInput(_ snapshot: TabSnapshotRepository.Snapshot) throws {
        if snapshot.tabs.contains(where: { $0.index < 0 }) {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
        let tabIDs = Set(snapshot.tabs.map { $0.id })
        if tabIDs.count != snapshot.tabs.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
        let spaceIDs = Set(snapshot.spaces.map { $0.id })
        if spaceIDs.count != snapshot.spaces.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
        let folderIDs = Set(snapshot.folders.map(\.id))
        if folderIDs.count != snapshot.folders.count {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }

        for tab in snapshot.tabs {
            if let spaceId = tab.spaceId, !spaceIDs.contains(spaceId) {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.isSpacePinned {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
        }

        for folder in snapshot.folders where !spaceIDs.contains(folder.spaceId) {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
        try validateFolderHierarchy(snapshot.folders, requiresCompleteParentSet: true)

        try validateSplitGroups(snapshot.splitGroups)

        for space in snapshot.spaces where space.profileId == nil {
            log.debug("[validate] Space missing profileId: \(space.id.uuidString, privacy: .public)")
        }
    }

    static func validateSplitGroups(_ splitGroups: [SplitGroup]) throws {
        let sanitized = SplitGroup.sanitized(splitGroups)
        guard sanitized.count == splitGroups.count else {
            throw TabSnapshotRepository.PersistenceError.invalidModelState
        }
    }

    static func validateFolderHierarchy(
        _ folders: [TabSnapshotRepository.SnapshotFolder],
        requiresCompleteParentSet: Bool
    ) throws {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        for folder in folders {
            guard let parentFolderId = folder.parentFolderId else { continue }
            if parentFolderId == folder.id {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
            if let parent = foldersById[parentFolderId] {
                if parent.spaceId != folder.spaceId {
                    throw TabSnapshotRepository.PersistenceError.invalidModelState
                }
            } else if requiresCompleteParentSet {
                throw TabSnapshotRepository.PersistenceError.invalidModelState
            }
        }

        for folder in folders {
            var visited: Set<UUID> = [folder.id]
            var parentId = folder.parentFolderId
            while let id = parentId,
                  let parent = foldersById[id] {
                guard visited.insert(id).inserted else {
                    throw TabSnapshotRepository.PersistenceError.invalidModelState
                }
                parentId = parent.parentFolderId
            }
        }
    }
}
