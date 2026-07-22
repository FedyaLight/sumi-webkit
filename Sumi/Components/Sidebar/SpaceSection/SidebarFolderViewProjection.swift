//
//  SidebarFolderViewProjection.swift
//  Sumi
//

import SumiDomain
import SwiftUI

enum SidebarFolderListItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)
    case liveItem(String)
    case splitGroup(UUID)
}

struct SidebarFolderDisplayEntry: Identifiable {
    let item: SidebarFolderListItem
    let dropIndex: Int
    let id: String
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
        isFolderOpen: Bool,
        displayedCollapsedProjectionIDs: [UUID],
        stickyItemIDs: [UUID],
        orderedDescendantItemIDs: [UUID],
        projection: SidebarFolderViewProjection
    ) {
        childCount = baseItems.count
        targetCollapsedProjectionIDs = isFolderOpen
            ? []
            : SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
                stickyItemIDs: stickyItemIDs,
                orderedDescendantItemIDs: orderedDescendantItemIDs,
                projection: projection
            )
        visibleCollapsedProjectionIDs = SidebarFolderDisplayProjection.visibleCollapsedProjectionIDs(
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            targetCollapsedProjectionIDs: targetCollapsedProjectionIDs
        )
        bodyItems = isFolderOpen
            ? baseItems
            : visibleCollapsedProjectionIDs.compactMap(projection.collapsedProjectionItem)
        bodyDisplayEntries = SidebarFolderDisplayProjection.displayEntries(from: bodyItems)
    }
}

enum SidebarFolderDisplayProjection {
    static func displayEntries(
        from items: [SidebarFolderListItem]
    ) -> [SidebarFolderDisplayEntry] {
        items.enumerated().map { index, item in
            SidebarFolderDisplayEntry(
                item: item,
                dropIndex: index,
                id: displayID(for: item)
            )
        }
    }

    @MainActor
    static func targetCollapsedProjectionIDs(
        stickyItemIDs: [UUID],
        orderedDescendantItemIDs: [UUID],
        projection: SidebarFolderViewProjection
    ) -> [UUID] {
        let stickyMembers = Set(stickyItemIDs)
        return orderedDescendantItemIDs
            .filter(stickyMembers.contains)
            .filter(projection.isCollapsedProjectionEligible)
    }

    static func visibleCollapsedProjectionIDs(
        displayedCollapsedProjectionIDs: [UUID],
        targetCollapsedProjectionIDs: [UUID]
    ) -> [UUID] {
        displayedCollapsedProjectionIDs.isEmpty
            ? targetCollapsedProjectionIDs
            : displayedCollapsedProjectionIDs
    }

    private static func displayID(for item: SidebarFolderListItem) -> String {
        switch item {
        case .folder(let id):
            return "folder-\(id.uuidString)"
        case .shortcut(let id):
            return "item-\(id.uuidString)"
        case .liveItem(let id):
            return "live-item-\(id)"
        case .splitGroup(let id):
            return "split-group-\(id.uuidString)"
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
    let liveTabsByPinId: [UUID: Tab]
    let liveCollapsedProjectionItemIDs: Set<UUID>
    let selectedPinIds: Set<UUID>
    let currentTabURLString: String?

    var isLiveFolder: Bool {
        liveFolderSource != nil
    }

    init(
        folder: TabFolder,
        space: Space,
        shortcutPins: [ShortcutPin],
        inventory: SidebarSpaceInventorySnapshot,
        selection: SidebarWindowSelectionQuery,
        liveFolderSource: SumiLiveFolderSource?,
        liveFolderItems: [SumiLiveFolderItem],
        currentTab: Tab?,
        windowState: BrowserWindowState,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) {
        let visualItems = inventory.folderItems(for: folder.id)
        let descendantItems = inventory.descendantItems(for: folder.id)
        var shortcutHostedGroups = descendantItems.compactMap { item -> SplitGroup? in
            guard case .splitGroup(let groupID) = item else { return nil }
            return inventory.splitGroup(id: groupID)
        }
        for item in visualItems {
            guard case .splitGroup(let groupID) = item,
                  !shortcutHostedGroups.contains(where: { $0.id == groupID }),
                  let group = inventory.splitGroup(id: groupID) else { continue }
            shortcutHostedGroups.append(group)
        }
        let projectionPins = shortcutPins
            + descendantItems.compactMap { item -> ShortcutPin? in
                guard case .shortcut(let pinID) = item else { return nil }
                return inventory.pin(id: pinID)
            }
        let projectionPinsById = projectionPins.reduce(into: [UUID: ShortcutPin]()) { result, pin in
            result[pin.id] = pin
        }
        let uniqueProjectionPins = Array(projectionPinsById.values)
        let launcherItems = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: selectionSnapshot,
            windowState: windowState
        ).launcherItems(descendantItems)

        self.liveFolderSource = liveFolderSource
        self.liveFolderItems = liveFolderItems
        self.baseItems = Self.makeBaseItems(
            liveFolderItems: liveFolderItems,
            isLiveFolder: liveFolderSource != nil,
            visualItems: visualItems
        )
        self.splitGroupsById = Dictionary(
            uniqueKeysWithValues: shortcutHostedGroups.map { ($0.id, $0) }
        )
        self.splitGroupItemsById = Dictionary(
            uniqueKeysWithValues: shortcutHostedGroups.map { group in
                (
                    group.id,
                    SplitGroupSidebarModel.items(
                        for: group,
                        inventory: inventory,
                        selection: selection,
                        windowState: windowState
                    )
                )
            }
        )
        self.shortcutPinsById = projectionPinsById
        self.liveTabsByPinId = Dictionary(
            uniqueKeysWithValues: uniqueProjectionPins.compactMap { pin in
                guard let liveTab = selection.liveTab(for: pin.id, in: windowState) else {
                    return nil
                }
                return (pin.id, liveTab)
            }
        )
        self.liveCollapsedProjectionItemIDs = Set(
            launcherItems.lazy.filter(\.isLive).map(\.id)
        )
        self.selectedPinIds = Set(
            uniqueProjectionPins.compactMap { pin in
                selection.isShortcutSelected(
                    pin,
                    in: windowState,
                    selection: selectionSnapshot
                )
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

    func liveTab(for pinId: UUID) -> Tab? {
        liveTabsByPinId[pinId]
    }

    func isShortcutSelected(_ pin: ShortcutPin) -> Bool {
        selectedPinIds.contains(pin.id)
    }

    /// Whether a sticky launcher or whole Split Group is live in this window.
    func isCollapsedProjectionEligible(_ itemID: UUID) -> Bool {
        liveCollapsedProjectionItemIDs.contains(itemID)
    }

    func collapsedProjectionItem(_ itemID: UUID) -> SidebarFolderListItem? {
        if shortcutPinsById[itemID] != nil {
            return .shortcut(itemID)
        }
        if splitGroupsById[itemID] != nil {
            return .splitGroup(itemID)
        }
        return nil
    }

    private static func makeBaseItems(
        liveFolderItems: [SumiLiveFolderItem],
        isLiveFolder: Bool,
        visualItems: [SidebarPinnedInventoryItem]
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
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let liveFolderSnapshot: SidebarLiveFolderSnapshot
    @ViewBuilder let content: (SidebarFolderViewProjection) -> Content

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    init(
        folder: TabFolder,
        space: Space,
        shortcutPins: [ShortcutPin],
        inventory: SidebarSpaceInventorySnapshot,
        selection: SidebarWindowSelectionQuery,
        liveFolderSnapshot: SidebarLiveFolderSnapshot,
        @ViewBuilder content: @escaping (SidebarFolderViewProjection) -> Content
    ) {
        self.folder = folder
        self.space = space
        self.shortcutPins = shortcutPins
        self.inventory = inventory
        self.selection = selection
        self.liveFolderSnapshot = liveFolderSnapshot
        self.content = content
    }

    var body: some View {
        let selectionSnapshot = sidebarSelection
        content(
            SidebarFolderViewProjection(
                folder: folder,
                space: space,
                shortcutPins: shortcutPins,
                inventory: inventory,
                selection: selection,
                liveFolderSource: liveFolderSnapshot.source,
                liveFolderItems: liveFolderSnapshot.items,
                currentTab: selection.currentTab(in: windowState),
                windowState: windowState,
                selectionSnapshot: selectionSnapshot
            )
        )
    }
}
