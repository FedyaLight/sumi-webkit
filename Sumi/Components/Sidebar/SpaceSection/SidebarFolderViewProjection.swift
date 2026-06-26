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
        let hiddenPinIds = tabManager.shortcutHostedSplitHiddenPinIds(for: space.id)
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
            childFolders: childFolders,
            shortcutPins: shortcutPins,
            shortcutHostedGroups: shortcutHostedGroups,
            hiddenPinIds: hiddenPinIds,
            spaceId: space.id,
            tabManager: tabManager
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
        childFolders: [TabFolder],
        shortcutPins: [ShortcutPin],
        shortcutHostedGroups: [SplitGroup],
        hiddenPinIds: Set<UUID>,
        spaceId: UUID,
        tabManager: TabManager
    ) -> [SidebarFolderListItem] {
        if isLiveFolder {
            return liveFolderItems.map { .liveItem($0.id) }
        }

        let folders = childFolders.map { ($0.index, 0, SidebarFolderListItem.folder($0.id)) }
        let pins = shortcutPins
            .filter { !hiddenPinIds.contains($0.id) }
            .map { ($0.index, 1, SidebarFolderListItem.shortcut($0.id)) }
        let splitGroups = shortcutHostedGroups
            .map { (tabManager.shortcutHostedSplitGroupVisualIndex($0, in: spaceId), 0, SidebarFolderListItem.splitGroup($0.id)) }

        return (folders + pins + splitGroups)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                switch (lhs.2, rhs.2) {
                case (.folder(let left), .folder(let right)),
                     (.shortcut(let left), .shortcut(let right)),
                     (.splitGroup(let left), .splitGroup(let right)):
                    return left.uuidString < right.uuidString
                case (.liveItem(let left), .liveItem(let right)):
                    return left < right
                case (.splitGroup, .folder), (.splitGroup, .shortcut),
                     (.folder, .shortcut):
                    return true
                case (.folder, .splitGroup), (.shortcut, .splitGroup),
                     (.shortcut, .folder):
                    return false
                case (.liveItem, _), (_, .liveItem):
                    return false
                case (.restoreGap, _), (_, .restoreGap),
                     (.placeholder, _), (_, .placeholder):
                    return false
                }
            }
            .map(\.2)
    }
}

struct SidebarFolderViewProjectionReader<Content: View>: View {
    let folder: TabFolder
    let space: Space
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let shortcutRestoreGaps: [ShortcutRestoreGap]
    @ViewBuilder let content: (SidebarFolderViewProjection) -> Content

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        content(
            SidebarFolderViewProjection(
                folder: folder,
                space: space,
                shortcutPins: shortcutPins,
                childFolders: childFolders,
                shortcutRestoreGaps: shortcutRestoreGaps,
                tabManager: browserManager.tabManager,
                liveFolderManager: browserManager.liveFolderManager,
                currentTab: browserManager.currentTab(for: windowState),
                windowState: windowState
            )
        )
    }
}
