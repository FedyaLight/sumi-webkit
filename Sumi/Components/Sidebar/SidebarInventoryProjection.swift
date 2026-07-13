import Foundation
import SumiDomain

enum SidebarPinnedInventoryItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)
    case splitGroup(UUID)
}

/// Immutable structural input for one sidebar space page.
///
/// Window-local live tabs and selection are intentionally absent. Consumers
/// resolve those through `SidebarWindowSelectionQuery` so a snapshot from one
/// window can never make another window look selected.
struct SidebarSpaceInventorySnapshot {
    let spaceID: UUID
    let regularTabs: [Tab]
    let topLevelItems: [SidebarPinnedInventoryItem]
    let topLevelFolders: [TabFolder]
    let topLevelPins: [ShortcutPin]
    let childFoldersByParentID: [UUID: [TabFolder]]
    let folderPinsByFolderID: [UUID: [ShortcutPin]]
    let folderItemsByFolderID: [UUID: [SidebarPinnedInventoryItem]]
    let foldersByID: [UUID: TabFolder]
    let pinsByID: [UUID: ShortcutPin]
    let tabsByID: [UUID: Tab]
    let splitGroupsByID: [UUID: SplitGroup]

    var userVisibleTabCount: Int {
        regularTabs.count + topLevelPins.count
            + folderPinsByFolderID.values.reduce(0) { $0 + $1.count }
    }

    func folder(id: UUID) -> TabFolder? {
        foldersByID[id]
    }

    func pin(id: UUID) -> ShortcutPin? {
        pinsByID[id]
    }

    func tab(id: UUID) -> Tab? {
        tabsByID[id]
    }

    func splitGroup(id: UUID) -> SplitGroup? {
        splitGroupsByID[id]
    }

    func splitGroup(containing memberID: SplitMemberID) -> SplitGroup? {
        splitGroupsByID.values.first { $0.contains(memberID) }
    }

    func folderItems(for folderID: UUID) -> [SidebarPinnedInventoryItem] {
        folderItemsByFolderID[folderID] ?? []
    }

    func recursiveChildCount(for folderID: UUID) -> Int {
        func count(_ parentID: UUID, visited: Set<UUID>) -> Int {
            guard !visited.contains(parentID) else { return 0 }
            var nextVisited = visited
            nextVisited.insert(parentID)
            let directPins = folderPinsByFolderID[parentID]?.count ?? 0
            let childFolders = childFoldersByParentID[parentID] ?? []
            return directPins + childFolders.reduce(0) { total, child in
                total + 1 + count(child.id, visited: nextVisited)
            }
        }

        return count(folderID, visited: [])
    }

    @MainActor
    static func ephemeral(spaceID: UUID, regularTabs: [Tab]) -> Self {
        Self(
            spaceID: spaceID,
            regularTabs: regularTabs.sorted { $0.index < $1.index },
            topLevelItems: [],
            topLevelFolders: [],
            topLevelPins: [],
            childFoldersByParentID: [:],
            folderPinsByFolderID: [:],
            folderItemsByFolderID: [:],
            foldersByID: [:],
            pinsByID: [:],
            tabsByID: Dictionary(
                uniqueKeysWithValues: regularTabs.map { ($0.id, $0) }
            ),
            splitGroupsByID: [:]
        )
    }
}

/// Structural sidebar read boundary. It snapshots canonical owners at the
/// moment a page is built and never retains rendered SwiftUI arrays.
@MainActor
final class SidebarInventoryProjection {
    private let runtimeIsAlive: @MainActor () -> Bool
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let splitGroups: SplitGroupStore
    private let splitOrdering: SplitGroupSidebarOrderingService

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        splitGroups: SplitGroupStore,
        splitOrdering: SplitGroupSidebarOrderingService
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.folders = folders
        self.pins = pins
        self.splitGroups = splitGroups
        self.splitOrdering = splitOrdering
    }

    func availableSpaces(
        isIncognito: Bool,
        ephemeralSpaces: [Space]
    ) -> [Space] {
        if isIncognito { return ephemeralSpaces }
        guard runtimeIsAlive() else { return [] }
        return spaces.spaces
    }

    func currentSpace() -> Space? {
        guard runtimeIsAlive() else { return nil }
        return spaces.currentSpace
    }

    func space(id: UUID) -> Space? {
        guard runtimeIsAlive() else { return nil }
        return spaces.space(with: id)
    }

    func essentialPins(profileID: UUID?) -> [ShortcutPin] {
        guard runtimeIsAlive() else { return [] }
        return pins.essentialPins(for: profileID)
    }

    func snapshot(for spaceID: UUID) -> SidebarSpaceInventorySnapshot? {
        guard runtimeIsAlive(), spaces.contains(spaceId: spaceID) else {
            return nil
        }

        let allFolders = folders.folders(for: spaceID)
        let allPins = pins.spacePinnedPins(for: spaceID)
        let groupValues = splitGroups.groups
        let shortcutHostedPinIDs = Set(
            groupValues
                .filter { $0.container.isShortcutSidebar }
                .flatMap { group in
                    group.memberIDs.compactMap { memberID -> UUID? in
                        guard case .shortcutPin(let pinID) = memberID else {
                            return nil
                        }
                        return pinID
                    }
                }
        )
        let visiblePins = allPins.filter { !shortcutHostedPinIDs.contains($0.id) }
        let foldersByID = Dictionary(uniqueKeysWithValues: allFolders.map { ($0.id, $0) })
        let pinsByID = Dictionary(uniqueKeysWithValues: allPins.map { ($0.id, $0) })
        let pageTabs = regularTabs.tabs(in: spaceID)
        let tabsByID = Dictionary(uniqueKeysWithValues: pageTabs.map { ($0.id, $0) })
        let resolver = splitOrdering.resolver(for: spaceID)
        let topLevelItems = resolver.topLevelItems().map(Self.inventoryItem)

        let topLevelFolders = topLevelItems.compactMap { item -> TabFolder? in
            guard case .folder(let folderID) = item else { return nil }
            return foldersByID[folderID]
        }
        let topLevelPins = topLevelItems.compactMap { item -> ShortcutPin? in
            guard case .shortcut(let pinID) = item else { return nil }
            return pinsByID[pinID]
        }
        let childFoldersByParentID = Dictionary(
            grouping: allFolders.filter { $0.parentFolderId != nil },
            by: { $0.parentFolderId! }
        ).mapValues(Self.sortedFolders)
        let folderPinsByFolderID = Dictionary(
            grouping: visiblePins.filter { $0.folderId != nil },
            by: { $0.folderId! }
        ).mapValues(Self.sortedPins)
        let folderItemsByFolderID = Dictionary(
            uniqueKeysWithValues: allFolders.map { folder in
                (
                    folder.id,
                    resolver.folderItems(for: folder.id).map(Self.inventoryItem)
                )
            }
        )

        return SidebarSpaceInventorySnapshot(
            spaceID: spaceID,
            regularTabs: pageTabs,
            topLevelItems: topLevelItems,
            topLevelFolders: topLevelFolders,
            topLevelPins: topLevelPins,
            childFoldersByParentID: childFoldersByParentID,
            folderPinsByFolderID: folderPinsByFolderID,
            folderItemsByFolderID: folderItemsByFolderID,
            foldersByID: foldersByID,
            pinsByID: pinsByID,
            tabsByID: tabsByID,
            splitGroupsByID: splitGroups.groupMap
        )
    }

    private static func inventoryItem(
        _ item: SplitGroupVisualListItem
    ) -> SidebarPinnedInventoryItem {
        switch item {
        case .folder(let id): return .folder(id)
        case .shortcut(let id): return .shortcut(id)
        case .splitGroup(let id): return .splitGroup(id)
        }
    }

    private static func sortedFolders(_ values: [TabFolder]) -> [TabFolder] {
        values.sorted {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func sortedPins(_ values: [ShortcutPin]) -> [ShortcutPin] {
        values.sorted {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
