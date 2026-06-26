import Foundation

struct SplitGroupIndexStore {
    private var groupsById: [UUID: SplitGroup] = [:]
    private var groupIndexesById: [UUID: Int] = [:]
    private var groupIdsByMemberId: [UUID: UUID] = [:]

    var groups: Dictionary<UUID, SplitGroup>.Values {
        groupsById.values
    }

    var groupMap: [UUID: SplitGroup] {
        groupsById
    }

    mutating func rebuild(from groups: [SplitGroup]) {
        groupsById.removeAll(keepingCapacity: true)
        groupIndexesById.removeAll(keepingCapacity: true)
        groupIdsByMemberId.removeAll(keepingCapacity: true)

        for (index, group) in groups.enumerated() {
            groupsById[group.id] = group
            groupIndexesById[group.id] = index
            for tabId in group.tabIds {
                groupIdsByMemberId[tabId] = group.id
            }
            for pinId in group.shortcutPinIds {
                groupIdsByMemberId[pinId] = group.id
            }
        }
    }

    func group(with id: UUID) -> SplitGroup? {
        groupsById[id]
    }

    func group(containingMemberId id: UUID) -> SplitGroup? {
        groupId(containingMemberId: id).flatMap { groupsById[$0] }
    }

    func groupId(containingMemberId id: UUID) -> UUID? {
        groupIdsByMemberId[id]
    }

    func index(of groupId: UUID) -> Int? {
        groupIndexesById[groupId]
    }
}
