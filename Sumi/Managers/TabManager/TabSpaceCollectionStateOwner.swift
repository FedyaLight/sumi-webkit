import Foundation

@MainActor
final class TabSpaceCollectionStateOwner {
    private(set) var spaces: [Space] = []
    private(set) var currentSpace: Space?

    var count: Int {
        spaces.count
    }

    var firstSpace: Space? {
        spaces.first
    }

    var currentSpaceId: UUID? {
        currentSpace?.id
    }

    func replaceSpaces(_ spaces: [Space]) {
        self.spaces = spaces
    }

    func replaceCurrentSpace(_ currentSpace: Space?) {
        self.currentSpace = currentSpace
    }

    func removeAll() {
        spaces.removeAll()
        currentSpace = nil
    }

    func append(_ space: Space) {
        spaces.append(space)
    }

    @discardableResult
    func remove(at index: Int) -> Space? {
        guard spaces.indices.contains(index) else { return nil }
        return spaces.remove(at: index)
    }

    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        guard spaces.count > 1,
              let sourceIndex = index(of: spaceId)
        else {
            return false
        }

        let currentSpaceId = currentSpace?.id
        let movingSpace = spaces[sourceIndex]
        var reorderedSpaces = spaces
        reorderedSpaces.remove(at: sourceIndex)
        let insertionIndex = min(max(targetIndex, 0), reorderedSpaces.count)
        reorderedSpaces.insert(movingSpace, at: insertionIndex)

        guard reorderedSpaces.map(\.id) != spaces.map(\.id) else {
            return false
        }

        spaces = reorderedSpaces
        if let currentSpaceId {
            currentSpace = space(with: currentSpaceId)
        }
        return true
    }

    func sort(by areInIncreasingOrder: (Space, Space) throws -> Bool) rethrows {
        try spaces.sort(by: areInIncreasingOrder)
    }

    func space(with id: UUID) -> Space? {
        spaces.first { $0.id == id }
    }

    func spaces(forProfile profileId: UUID) -> [Space] {
        spaces.filter { $0.profileId == profileId }
    }

    func firstSpace(forProfile profileId: UUID) -> Space? {
        spaces.first { $0.profileId == profileId }
    }

    func first(where predicate: (Space) throws -> Bool) rethrows -> Space? {
        try spaces.first(where: predicate)
    }

    func contains(spaceId: UUID) -> Bool {
        space(with: spaceId) != nil
    }

    func index(of spaceId: UUID) -> Int? {
        spaces.firstIndex { $0.id == spaceId }
    }

    func profileId(for spaceId: UUID) -> UUID? {
        space(with: spaceId)?.profileId
    }

    /// Proves that a profile transaction still owns the one physical catalog
    /// Space it admitted. A detached current-Space mirror is optional, but a
    /// newly installed same-ID mirror is not allowed to join an in-flight
    /// mutation by UUID aliasing.
    func profileMutationResidenceIsExact(
        space: Space,
        selectedSpace: Space?
    ) -> Bool {
        let catalogMatches = spaces.filter { $0.id == space.id }
        guard catalogMatches.count == 1,
              catalogMatches.first === space,
              selectedSpace == nil || selectedSpace?.id == space.id else {
            return false
        }
        guard let currentSpace, currentSpace.id == space.id else {
            return true
        }
        return currentSpace === space || currentSpace === selectedSpace
    }

    @discardableResult
    func renameSpace(spaceId: UUID, to newName: String) -> Bool {
        guard let space = space(with: spaceId) else { return false }
        space.name = newName
        if let currentSpace, currentSpace.id == spaceId, currentSpace !== space {
            currentSpace.name = newName
        }
        return true
    }

    @discardableResult
    func updateIcon(spaceId: UUID, to icon: String) -> Bool {
        guard let space = space(with: spaceId) else { return false }
        let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(icon)
        space.icon = normalized
        if let currentSpace, currentSpace.id == spaceId, currentSpace !== space {
            currentSpace.icon = normalized
        }
        return true
    }

    @discardableResult
    func assignProfileWithoutObservation(
        spaceId: UUID,
        profileId: UUID?
    ) -> Bool {
        guard let space = space(with: spaceId) else { return false }
        space.replaceProfileIDWithoutObservation(profileId)
        if let currentSpace, currentSpace.id == spaceId,
           currentSpace !== space {
            currentSpace.replaceProfileIDWithoutObservation(profileId)
        }
        return true
    }

    /// Mutates only the physical witnesses retained by a staged transaction.
    /// This deliberately does not resolve either witness again by UUID, so it
    /// is also safe for rollback after catalog removal or same-ID replacement.
    @discardableResult
    func assignProfileWithoutObservation(
        space: Space,
        selectedSpace: Space?,
        profileId: UUID?
    ) -> Bool {
        guard selectedSpace == nil || selectedSpace?.id == space.id else {
            return false
        }
        space.replaceProfileIDWithoutObservation(profileId)
        if let selectedSpace, selectedSpace !== space {
            selectedSpace.replaceProfileIDWithoutObservation(profileId)
        }
        return true
    }

    func publishProfileMutation(spaceId: UUID) {
        guard let space = space(with: spaceId) else { return }
        space.publishCurrentProfileID()
        if let currentSpace, currentSpace.id == spaceId,
           currentSpace !== space {
            currentSpace.publishCurrentProfileID()
        }
    }

    /// Publishes only the witnesses mutated by the exact transaction. A
    /// replacement currently occupying the same UUID is never announced as if
    /// it had participated in the staged mutation.
    @discardableResult
    func publishProfileMutation(
        space: Space,
        selectedSpace: Space?
    ) -> Bool {
        guard selectedSpace == nil || selectedSpace?.id == space.id else {
            return false
        }
        space.publishCurrentProfileID()
        if let selectedSpace, selectedSpace !== space {
            selectedSpace.publishCurrentProfileID()
        }
        return true
    }
}
