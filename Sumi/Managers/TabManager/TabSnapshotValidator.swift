import Foundation
import OSLog

/// Pure structural-validity policy for a full snapshot or incremental delta.
/// It throws `TabPersistenceError.invalidModelState` when the shape
/// violates the persistence invariants (negative indexes, duplicate ids, a tab that is
/// both pinned and space-pinned, orphaned or cyclic folder hierarchies, split groups that
/// don't survive sanitization, …).
///
/// This is deliberately free of persistence mechanism: no `ModelContext`, actor state,
/// or error classification. The invariants stay unit-testable without a store.
enum TabSnapshotValidator {
    private static let log = Logger.sumi(category: "TabPersistence")

    static func validateDelta(_ delta: TabStructuralPersistenceDelta) throws {
        if delta.tabs.contains(where: { $0.index < 0 })
            || delta.folders.contains(where: { $0.index < 0 })
            || delta.spaces.contains(where: { $0.index < 0 }) {
            throw TabPersistenceError.invalidModelState
        }

        let tabIDs = Set(delta.tabs.map(\.id))
        if tabIDs.count != delta.tabs.count {
            throw TabPersistenceError.invalidModelState
        }

        let folderIDs = Set(delta.folders.map(\.id))
        if folderIDs.count != delta.folders.count {
            throw TabPersistenceError.invalidModelState
        }

        let spaceIDs = Set(delta.spaces.map(\.id))
        if spaceIDs.count != delta.spaces.count {
            throw TabPersistenceError.invalidModelState
        }

        for tab in delta.tabs {
            if tab.isPinned && tab.isSpacePinned {
                throw TabPersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw TabPersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw TabPersistenceError.invalidModelState
            }
            if let spaceId = tab.spaceId, delta.deletedSpaceIds.contains(spaceId) {
                throw TabPersistenceError.invalidModelState
            }
        }

        if let splitGroups = delta.splitGroups {
            try validateSplitGroups(splitGroups)
        }

        for folder in delta.folders where delta.deletedSpaceIds.contains(folder.spaceId) {
            throw TabPersistenceError.invalidModelState
        }
        try validateFolderHierarchy(delta.folders, requiresCompleteParentSet: false)
    }

    static func validateInput(_ snapshot: TabPersistenceSnapshot) throws {
        if snapshot.tabs.contains(where: { $0.index < 0 }) {
            throw TabPersistenceError.invalidModelState
        }
        let tabIDs = Set(snapshot.tabs.map { $0.id })
        if tabIDs.count != snapshot.tabs.count {
            throw TabPersistenceError.invalidModelState
        }
        let spaceIDs = Set(snapshot.spaces.map { $0.id })
        if spaceIDs.count != snapshot.spaces.count {
            throw TabPersistenceError.invalidModelState
        }
        let folderIDs = Set(snapshot.folders.map(\.id))
        if folderIDs.count != snapshot.folders.count {
            throw TabPersistenceError.invalidModelState
        }

        for tab in snapshot.tabs {
            if let spaceId = tab.spaceId, !spaceIDs.contains(spaceId) {
                throw TabPersistenceError.invalidModelState
            }
            if tab.isPinned && tab.isSpacePinned {
                throw TabPersistenceError.invalidModelState
            }
            if tab.isPinned && tab.spaceId != nil {
                throw TabPersistenceError.invalidModelState
            }
            if tab.isSpacePinned && tab.spaceId == nil {
                throw TabPersistenceError.invalidModelState
            }
        }

        for folder in snapshot.folders where !spaceIDs.contains(folder.spaceId) {
            throw TabPersistenceError.invalidModelState
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
            throw TabPersistenceError.invalidModelState
        }
    }

    static func validateFolderHierarchy(
        _ folders: [TabPersistenceFolder],
        requiresCompleteParentSet: Bool
    ) throws {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        for folder in folders {
            guard let parentFolderId = folder.parentFolderId else { continue }
            if parentFolderId == folder.id {
                throw TabPersistenceError.invalidModelState
            }
            if let parent = foldersById[parentFolderId] {
                if parent.spaceId != folder.spaceId {
                    throw TabPersistenceError.invalidModelState
                }
            } else if requiresCompleteParentSet {
                throw TabPersistenceError.invalidModelState
            }
        }

        for folder in folders {
            var visited: Set<UUID> = [folder.id]
            var parentId = folder.parentFolderId
            while let id = parentId,
                  let parent = foldersById[id] {
                guard visited.insert(id).inserted else {
                    throw TabPersistenceError.invalidModelState
                }
                parentId = parent.parentFolderId
            }
        }
    }
}
