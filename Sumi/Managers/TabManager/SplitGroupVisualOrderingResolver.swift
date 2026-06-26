import Foundation

enum SplitGroupVisualListItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)
    case splitGroup(UUID)

    var id: UUID {
        switch self {
        case .folder(let id), .shortcut(let id), .splitGroup(let id):
            return id
        }
    }
}

@MainActor
struct SplitGroupVisualOrderingResolver {
    let spaceId: UUID
    let splitGroups: [SplitGroup]
    let folders: [TabFolder]
    let spacePinnedPins: [ShortcutPin]

    private let pinsById: [UUID: ShortcutPin]

    init(
        spaceId: UUID,
        splitGroups: [SplitGroup],
        folders: [TabFolder],
        spacePinnedPins: [ShortcutPin]
    ) {
        self.spaceId = spaceId
        self.splitGroups = splitGroups
        self.folders = folders
        self.spacePinnedPins = spacePinnedPins
        self.pinsById = spacePinnedPins.reduce(into: [UUID: ShortcutPin]()) { result, pin in
            result[pin.id] = pin
        }
    }

    func shortcutHostedGroups(inFolder folderId: UUID?) -> [SplitGroup] {
        shortcutHostedGroups().filter { group in
            self.folderId(for: group) == folderId
        }
    }

    func shortcutHostedGroups() -> [SplitGroup] {
        splitGroups.filter { group in
            guard case .shortcutPinned(let hostSpaceId, _, _) = group.host else { return false }
            return hostSpaceId == spaceId
        }
        .sorted { lhs, rhs in
            let lhsIndex = visualIndex(for: lhs)
            let rhsIndex = visualIndex(for: rhs)
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func hiddenPinIds() -> Set<UUID> {
        Set(shortcutHostedGroups().flatMap(\.shortcutPinIds))
    }

    func visualIndex(for group: SplitGroup) -> Int {
        if let index = group.shortcutPinnedIndex {
            return index
        }

        let memberIndexes = group.members.compactMap { member -> Int? in
            if let pinId = member.pinId,
               let pin = pinsById[pinId],
               pin.role == .spacePinned,
               pin.spaceId == spaceId {
                return pin.index
            }

            switch member.origin {
            case .spacePinned(let originSpaceId, _, let index) where originSpaceId == spaceId:
                return index
            case .generatedSpacePinnedFromRegular(let originSpaceId, let index) where originSpaceId == spaceId:
                return index
            default:
                return nil
            }
        }

        return memberIndexes.min() ?? 0
    }

    func folderId(for group: SplitGroup) -> UUID? {
        guard group.isShortcutHosted, group.hostSpaceId == spaceId else { return nil }

        if let hostIndex = group.shortcutPinnedIndex {
            let hostTopLevelMemberExists = group.members.contains { member in
                if let pinId = member.pinId,
                   let pin = pinsById[pinId],
                   pin.role == .spacePinned,
                   pin.spaceId == spaceId,
                   pin.folderId == nil,
                   pin.index == hostIndex {
                    return true
                }

                switch member.origin {
                case .spacePinned(let originSpaceId, nil, let index):
                    return originSpaceId == spaceId && index == hostIndex
                default:
                    return false
                }
            }
            if hostTopLevelMemberExists {
                return nil
            }

            let hostFolderMembers = group.members.compactMap { member -> UUID? in
                if let pinId = member.pinId,
                   let pin = pinsById[pinId],
                   pin.role == .spacePinned,
                   pin.spaceId == spaceId,
                   let folderId = pin.folderId,
                   pin.index == hostIndex {
                    return folderId
                }

                switch member.origin {
                case .spacePinned(let originSpaceId, let folderId, let index) where originSpaceId == spaceId && index == hostIndex:
                    return folderId
                default:
                    return nil
                }
            }
            if let folderId = hostFolderMembers.sorted(by: { $0.uuidString < $1.uuidString }).first {
                return folderId
            }
        }

        let memberFolders = group.members.compactMap { member -> (Int, UUID)? in
            if let pinId = member.pinId,
               let pin = pinsById[pinId],
               pin.role == .spacePinned,
               pin.spaceId == spaceId,
               let folderId = pin.folderId {
                return (pin.index, folderId)
            }

            switch member.origin {
            case .spacePinned(let originSpaceId, let folderId, let index) where originSpaceId == spaceId:
                return folderId.map { (index, $0) }
            default:
                return nil
            }
        }

        return memberFolders
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1.uuidString < rhs.1.uuidString
            }
            .first?.1
    }

    func topLevelItems() -> [SplitGroupVisualListItem] {
        let topLevelShortcutHostedGroups = shortcutHostedGroups(inFolder: nil)
        let hiddenPinIds = hiddenPinIds()
        let folderItems = folders
            .filter { $0.parentFolderId == nil }
            .map { folder in
                (index: folder.index, priority: 1, item: SplitGroupVisualListItem.folder(folder.id))
            }
        let shortcutItems = spacePinnedPins
            .filter { $0.folderId == nil && !hiddenPinIds.contains($0.id) }
            .map { pin in
                (index: pin.index, priority: 2, item: SplitGroupVisualListItem.shortcut(pin.id))
            }
        let splitItems = topLevelShortcutHostedGroups.map { group in
            (index: visualIndex(for: group), priority: 0, item: SplitGroupVisualListItem.splitGroup(group.id))
        }

        return sortedItems(folderItems + shortcutItems + splitItems)
    }

    func folderItems(for folderId: UUID) -> [SplitGroupVisualListItem] {
        let folderShortcutHostedGroups = shortcutHostedGroups(inFolder: folderId)
        let hiddenPinIds = hiddenPinIds()
        let folderItems = folders
            .filter { $0.parentFolderId == folderId }
            .map { folder in
                (index: folder.index, priority: 1, item: SplitGroupVisualListItem.folder(folder.id))
            }
        let shortcutItems = spacePinnedPins
            .filter { $0.folderId == folderId && !hiddenPinIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { pin in
                (index: pin.index, priority: 2, item: SplitGroupVisualListItem.shortcut(pin.id))
            }
        let splitItems = folderShortcutHostedGroups.map { group in
            (index: visualIndex(for: group), priority: 0, item: SplitGroupVisualListItem.splitGroup(group.id))
        }

        return sortedItems(folderItems + shortcutItems + splitItems)
    }

    private func sortedItems(
        _ items: [(index: Int, priority: Int, item: SplitGroupVisualListItem)]
    ) -> [SplitGroupVisualListItem] {
        items.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.item.id.uuidString < rhs.item.id.uuidString
        }
        .map(\.item)
    }
}
