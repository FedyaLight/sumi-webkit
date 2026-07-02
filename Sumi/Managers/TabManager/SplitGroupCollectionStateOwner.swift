import Foundation

@MainActor
final class SplitGroupCollectionStateOwner {
    private(set) var splitGroups: [SplitGroup] = []
    private var indexStore = SplitGroupIndexStore()

    var indexedGroups: Dictionary<UUID, SplitGroup>.Values {
        indexStore.groups
    }

    var groupMap: [UUID: SplitGroup] {
        indexStore.groupMap
    }

    func replaceSplitGroups(_ splitGroups: [SplitGroup]) {
        self.splitGroups = splitGroups
        indexStore.rebuild(from: splitGroups)
    }

    func removeAll() {
        replaceSplitGroups([])
    }

    func group(with id: UUID) -> SplitGroup? {
        indexStore.group(with: id)
    }

    func group(containingMemberId id: UUID) -> SplitGroup? {
        indexStore.group(containingMemberId: id)
    }

    func groupId(containingMemberId id: UUID) -> UUID? {
        indexStore.groupId(containingMemberId: id)
    }

    func index(of groupId: UUID) -> Int? {
        indexStore.index(of: groupId)
    }
}
