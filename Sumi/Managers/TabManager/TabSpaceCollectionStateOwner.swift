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
    func assignProfile(spaceId: UUID, profileId: UUID?) -> Bool {
        guard let space = space(with: spaceId) else { return false }
        space.profileId = profileId
        if let currentSpace, currentSpace.id == spaceId, currentSpace !== space {
            currentSpace.profileId = profileId
        }
        return true
    }
}
