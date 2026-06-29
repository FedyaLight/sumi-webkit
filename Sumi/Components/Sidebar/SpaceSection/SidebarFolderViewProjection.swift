//
//  SidebarFolderViewProjection.swift
//  Sumi
//

import SwiftUI

enum SidebarFolderListItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)
    case liveItem(String)
    case splitGroup(UUID)
    case restoreGap(UUID)
    case placeholder
}

struct SidebarFolderDisplayEntry: Identifiable {
    let item: SidebarFolderListItem
    let dropIndex: Int
    let id: String
}

struct SidebarFolderDragDisplayProjection: Equatable {
    let isActive: Bool
    let sourceFolderID: UUID?
    let draggedItemID: UUID?
    let folderDropIntent: FolderDropIntent
    let suppressesCommittedPlaceholder: Bool

    init(
        isActive: Bool,
        sourceFolderID: UUID?,
        draggedItemID: UUID?,
        folderDropIntent: FolderDropIntent,
        suppressesCommittedPlaceholder: Bool
    ) {
        self.isActive = isActive
        self.sourceFolderID = sourceFolderID
        self.draggedItemID = draggedItemID
        self.folderDropIntent = folderDropIntent
        self.suppressesCommittedPlaceholder = suppressesCommittedPlaceholder
    }

    @MainActor
    init(
        dragSnapshot: SidebarFolderDragSnapshot,
        folderID: UUID,
        baseItems: [SidebarFolderListItem]
    ) {
        let draggedItemID = dragSnapshot.projectionDragItemID

        let targetAlreadyContainsDraggedItem = draggedItemID.map { itemID in
            baseItems.contains { $0.matchesItemID(itemID) }
        } ?? false

        self.init(
            isActive: dragSnapshot.isDropProjectionActive,
            sourceFolderID: dragSnapshot.projectionSourceFolderID,
            draggedItemID: draggedItemID,
            folderDropIntent: dragSnapshot.projectionFolderDropIntent,
            suppressesCommittedPlaceholder: draggedItemID != nil
                && dragSnapshot.shouldHideCommittedPlaceholder(
                    into: .folder(folderID),
                    targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
                )
        )
    }
}

@MainActor
struct SidebarFolderContentProjection {
    let childCount: Int
    let bodyItems: [SidebarFolderListItem]
    let bodyDisplayEntries: [SidebarFolderDisplayEntry]
    let targetCollapsedProjectionIDs: [UUID]
    let visibleCollapsedProjectionIDs: [UUID]

    var hasCollapsedProjectionForLayout: Bool {
        !visibleCollapsedProjectionIDs.isEmpty || !targetCollapsedProjectionIDs.isEmpty
    }

    init(
        baseItems: [SidebarFolderListItem],
        folderID: UUID,
        isFolderOpen: Bool,
        shortcutPins: [ShortcutPin],
        restoreGaps: [ShortcutRestoreGap],
        displayedCollapsedProjectionIDs: [UUID],
        projectedChildIDs: [UUID],
        projection: SidebarFolderViewProjection,
        dragProjection: SidebarFolderDragDisplayProjection
    ) {
        childCount = baseItems.count
        let renderedItems = SidebarFolderDisplayProjection.renderedItems(
            baseItems: baseItems,
            folderID: folderID,
            isFolderOpen: isFolderOpen,
            restoreGaps: restoreGaps,
            dragProjection: dragProjection
        )
        targetCollapsedProjectionIDs = isFolderOpen
            ? []
            : SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
                shortcutPins: shortcutPins,
                projectedChildIDs: projectedChildIDs,
                projection: projection
            )
        visibleCollapsedProjectionIDs = SidebarFolderDisplayProjection.visibleCollapsedProjectionIDs(
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            targetCollapsedProjectionIDs: targetCollapsedProjectionIDs
        )
        bodyItems = isFolderOpen
            ? renderedItems
            : visibleCollapsedProjectionIDs.map(SidebarFolderListItem.shortcut)
        bodyDisplayEntries = SidebarFolderDisplayProjection.displayEntries(
            from: bodyItems,
            restoreGaps: restoreGaps,
            placeholderDragItemID: dragProjection.draggedItemID
        )
    }
}

enum SidebarFolderDisplayProjection {
    static func renderedItems(
        baseItems: [SidebarFolderListItem],
        folderID: UUID,
        isFolderOpen: Bool,
        restoreGaps: [ShortcutRestoreGap],
        dragProjection: SidebarFolderDragDisplayProjection
    ) -> [SidebarFolderListItem] {
        var items = SidebarDropProjection.projectedItems(
            itemIDs: baseItems,
            removesSourceID: projectedSourceItem(
                in: baseItems,
                folderID: folderID,
                dragProjection: dragProjection
            ),
            insertsPlaceholderAt: projectedInsertionIndex(
                folderID: folderID,
                isFolderOpen: isFolderOpen,
                dragProjection: dragProjection
            )
        )
        .map { item in
            switch item {
            case .item(let folderItem):
                return folderItem
            case .placeholder:
                return .placeholder
            }
        }

        let gaps = restoreGaps.filter { gap in
            gap.container == .folder(folderID)
        }
        for gap in gaps.sorted(by: { $0.index < $1.index }) {
            items.removeAll { item in
                if case .shortcut(let pinID) = item {
                    return pinID == gap.pinId
                }
                return false
            }
            items.insert(.restoreGap(gap.id), at: max(0, min(gap.index, items.count)))
        }

        return items
    }

    static func displayEntries(
        from items: [SidebarFolderListItem],
        restoreGaps: [ShortcutRestoreGap],
        placeholderDragItemID: UUID?
    ) -> [SidebarFolderDisplayEntry] {
        var childCount = 0
        return items.map { item in
            let entry = SidebarFolderDisplayEntry(
                item: item,
                dropIndex: childCount,
                id: displayID(
                    for: item,
                    placeholderIndex: childCount,
                    restoreGaps: restoreGaps,
                    placeholderDragItemID: placeholderDragItemID
                )
            )
            switch item {
            case .folder, .shortcut, .liveItem, .splitGroup:
                childCount += 1
            case .restoreGap, .placeholder:
                break
            }
            return entry
        }
    }

    @MainActor
    static func targetCollapsedProjectionPins(
        shortcutPins: [ShortcutPin],
        projectedChildIDs: [UUID],
        projection: SidebarFolderViewProjection
    ) -> [ShortcutPin] {
        let livePins = shortcutPins.filter { pin in
            projection.liveTab(for: pin.id) != nil
        }

        guard !projectedChildIDs.isEmpty else {
            return livePins.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        let projectedOrder = Dictionary(
            uniqueKeysWithValues: projectedChildIDs.enumerated().map { ($1, $0) }
        )
        return livePins.sorted { lhs, rhs in
            let leftOrder = projectedOrder[lhs.id] ?? lhs.index
            let rightOrder = projectedOrder[rhs.id] ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @MainActor
    static func targetCollapsedProjectionIDs(
        shortcutPins: [ShortcutPin],
        projectedChildIDs: [UUID],
        projection: SidebarFolderViewProjection
    ) -> [UUID] {
        targetCollapsedProjectionPins(
            shortcutPins: shortcutPins,
            projectedChildIDs: projectedChildIDs,
            projection: projection
        ).map(\.id)
    }

    static func visibleCollapsedProjectionIDs(
        displayedCollapsedProjectionIDs: [UUID],
        targetCollapsedProjectionIDs: [UUID]
    ) -> [UUID] {
        displayedCollapsedProjectionIDs.isEmpty
            ? targetCollapsedProjectionIDs
            : displayedCollapsedProjectionIDs
    }

    private static func projectedSourceItem(
        in items: [SidebarFolderListItem],
        folderID: UUID,
        dragProjection: SidebarFolderDragDisplayProjection
    ) -> SidebarFolderListItem? {
        guard dragProjection.isActive,
              dragProjection.sourceFolderID == folderID,
              let draggedItemID = dragProjection.draggedItemID else {
            return nil
        }
        return items.first { $0.matchesItemID(draggedItemID) }
    }

    private static func projectedInsertionIndex(
        folderID: UUID,
        isFolderOpen: Bool,
        dragProjection: SidebarFolderDragDisplayProjection
    ) -> Int? {
        guard dragProjection.isActive,
              case .insertIntoFolder(let targetFolderID, let index) = dragProjection.folderDropIntent,
              targetFolderID == folderID,
              isFolderOpen else {
            return nil
        }

        guard !dragProjection.suppressesCommittedPlaceholder else {
            return nil
        }
        return index
    }

    private static func displayID(
        for item: SidebarFolderListItem,
        placeholderIndex: Int,
        restoreGaps: [ShortcutRestoreGap],
        placeholderDragItemID: UUID?
    ) -> String {
        switch item {
        case .folder(let id):
            return "folder-\(id.uuidString)"
        case .shortcut(let id):
            return "item-\(id.uuidString)"
        case .liveItem(let id):
            return "live-item-\(id)"
        case .splitGroup(let id):
            return "split-group-\(id.uuidString)"
        case .restoreGap(let id):
            if let gap = restoreGaps.first(where: { $0.id == id }) {
                return "item-\(gap.pinId.uuidString)"
            }
            return "restore-gap-\(id.uuidString)"
        case .placeholder:
            if let placeholderDragItemID {
                return "item-\(placeholderDragItemID.uuidString)"
            }
            return "placeholder-\(placeholderIndex)"
        }
    }
}

private extension SidebarFolderListItem {
    func matchesItemID(_ id: UUID) -> Bool {
        switch self {
        case .folder(let itemID), .shortcut(let itemID), .splitGroup(let itemID):
            return itemID == id
        case .liveItem, .restoreGap, .placeholder:
            return false
        }
    }
}

@MainActor
struct SidebarFolderViewProjection {
    let liveFolderSource: SumiLiveFolderSource?
    let liveFolderItems: [SumiLiveFolderItem]
    let baseItems: [SidebarFolderListItem]
    let splitGroupsById: [UUID: SplitGroup]
    let splitGroupItemsById: [UUID: [SplitGroupSidebarItem]]
    let shortcutPinsById: [UUID: ShortcutPin]
    let regularPlaceholderGroupsByPinId: [UUID: SplitGroup]
    let liveTabsByPinId: [UUID: Tab]
    let selectedPinIds: Set<UUID>
    let currentTabURLString: String?

    var isLiveFolder: Bool {
        liveFolderSource != nil
    }

    init(
        folder: TabFolder,
        space: Space,
        shortcutPins: [ShortcutPin],
        childFolders: [TabFolder],
        shortcutRestoreGaps: [ShortcutRestoreGap],
        tabManager: TabManager,
        liveFolderManager: SumiLiveFolderManager,
        currentTab: Tab?,
        windowState: BrowserWindowState
    ) {
        let liveFolderSource = liveFolderManager.source(for: folder.id)
        let liveFolderItems = liveFolderSource == nil
            ? []
            : liveFolderManager.visibleItems(for: folder.id)
        let shortcutHostedGroups = tabManager.shortcutHostedSplitGroups(
            for: space.id,
            inFolder: folder.id
        )
        let restorePins = shortcutRestoreGaps
            .filter { $0.container == .folder(folder.id) }
            .compactMap { tabManager.shortcutPin(by: $0.pinId) }
        let projectionPins = shortcutPins + restorePins
        let projectionPinsById = projectionPins.reduce(into: [UUID: ShortcutPin]()) { result, pin in
            result[pin.id] = pin
        }
        let uniqueProjectionPins = Array(projectionPinsById.values)

        self.liveFolderSource = liveFolderSource
        self.liveFolderItems = liveFolderItems
        self.baseItems = Self.makeBaseItems(
            liveFolderItems: liveFolderItems,
            isLiveFolder: liveFolderSource != nil,
            visualItems: tabManager.folderChildVisualItems(for: folder.id, in: space.id)
        )
        self.splitGroupsById = Dictionary(
            uniqueKeysWithValues: shortcutHostedGroups.map { ($0.id, $0) }
        )
        self.splitGroupItemsById = Dictionary(
            uniqueKeysWithValues: shortcutHostedGroups.map { group in
                (group.id, SplitGroupSidebarModel.items(for: group, tabManager: tabManager))
            }
        )
        self.shortcutPinsById = projectionPinsById
        self.regularPlaceholderGroupsByPinId = Dictionary(
            uniqueKeysWithValues: uniqueProjectionPins.compactMap { pin in
                guard let group = tabManager.regularHostedSplitPlaceholderGroup(for: pin) else {
                    return nil
                }
                return (pin.id, group)
            }
        )
        self.liveTabsByPinId = Dictionary(
            uniqueKeysWithValues: uniqueProjectionPins.compactMap { pin in
                guard let liveTab = tabManager.shortcutLiveTab(for: pin.id, in: windowState.id) else {
                    return nil
                }
                return (pin.id, liveTab)
            }
        )
        self.selectedPinIds = Set(
            uniqueProjectionPins.compactMap { pin in
                tabManager.shortcutRuntimeAffordanceState(for: pin, in: windowState).isSelected
                    ? pin.id
                    : nil
            }
        )
        self.currentTabURLString = currentTab?.url.absoluteString
    }

    func liveFolderItem(with id: String) -> SumiLiveFolderItem? {
        liveFolderItems.first { $0.id == id }
    }

    func splitGroup(with id: UUID) -> SplitGroup? {
        splitGroupsById[id]
    }

    func splitGroupItems(for groupId: UUID) -> [SplitGroupSidebarItem] {
        splitGroupItemsById[groupId] ?? []
    }

    func shortcutPin(with id: UUID) -> ShortcutPin? {
        shortcutPinsById[id]
    }

    func regularPlaceholderGroup(for pinId: UUID) -> SplitGroup? {
        regularPlaceholderGroupsByPinId[pinId]
    }

    func liveTab(for pinId: UUID) -> Tab? {
        liveTabsByPinId[pinId]
    }

    func isShortcutSelected(_ pin: ShortcutPin) -> Bool {
        selectedPinIds.contains(pin.id)
    }

    private static func makeBaseItems(
        liveFolderItems: [SumiLiveFolderItem],
        isLiveFolder: Bool,
        visualItems: [TabManager.FolderChildVisualItem]
    ) -> [SidebarFolderListItem] {
        if isLiveFolder {
            return liveFolderItems.map { .liveItem($0.id) }
        }

        return visualItems.map { item in
            switch item {
            case .folder(let id):
                return .folder(id)
            case .shortcut(let id):
                return .shortcut(id)
            case .splitGroup(let id):
                return .splitGroup(id)
            }
        }
    }
}

struct SidebarFolderViewProjectionReader<Content: View>: View {
    let folder: TabFolder
    let space: Space
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let shortcutRestoreGaps: [ShortcutRestoreGap]
    let tabManager: TabManager
    let liveFolderManager: SumiLiveFolderManager
    let currentTab: Tab?
    @ViewBuilder let content: (SidebarFolderViewProjection) -> Content

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        content(
            SidebarFolderViewProjection(
                folder: folder,
                space: space,
                shortcutPins: shortcutPins,
                childFolders: childFolders,
                shortcutRestoreGaps: shortcutRestoreGaps,
                tabManager: tabManager,
                liveFolderManager: liveFolderManager,
                currentTab: currentTab,
                windowState: windowState
            )
        )
    }
}
