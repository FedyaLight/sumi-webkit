//
//  SpaceSidebarSnapshots.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

enum SpaceSidebarSnapshotFolderLayout {
    static let contentLeadingPadding: CGFloat = 14
    static let contentVerticalPadding: CGFloat = 4
}

struct SpaceSidebarSnapshotViewport: Equatable {
    static let zero = SpaceSidebarSnapshotViewport(
        contentOffsetY: 0,
        contentHeight: 0,
        viewportHeight: 0
    )

    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    init(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) {
        self.contentOffsetY = contentOffsetY.isFinite ? contentOffsetY : 0
        self.contentHeight = max(contentHeight.isFinite ? contentHeight : 0, 0)
        self.viewportHeight = max(viewportHeight.isFinite ? viewportHeight : 0, 0)
    }

    func clampedOffset(for renderedViewportHeight: CGFloat? = nil) -> CGFloat {
        let resolvedViewportHeight: CGFloat
        if let renderedViewportHeight {
            resolvedViewportHeight = max(renderedViewportHeight.isFinite ? renderedViewportHeight : 0, 0)
        } else {
            resolvedViewportHeight = viewportHeight
        }

        let maximumOffset = max(contentHeight - resolvedViewportHeight, 0)
        return min(max(contentOffsetY, 0), maximumOffset)
    }
}

enum SpaceSidebarSnapshotThemeResolver {
    @MainActor
    static func pageThemeContext(
        for space: Space,
        baseContext: ResolvedThemeContext,
        settings: SumiSettingsService,
        isIncognito: Bool
    ) -> ResolvedThemeContext {
        let workspaceTheme = isIncognito ? WorkspaceTheme.incognito : space.workspaceTheme
        let chromeColorScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: workspaceTheme,
            globalWindowScheme: baseContext.globalColorScheme,
            settings: settings,
            isIncognito: isIncognito
        )

        var context = baseContext
        context.chromeColorScheme = chromeColorScheme
        context.sourceChromeColorScheme = chromeColorScheme
        context.targetChromeColorScheme = chromeColorScheme
        context.workspaceTheme = workspaceTheme
        context.sourceWorkspaceTheme = workspaceTheme
        context.targetWorkspaceTheme = workspaceTheme
        context.isInteractiveTransition = false
        context.transitionProgress = 1.0
        return context
    }
}

enum SpaceSidebarSnapshotIcon {
    case image(Image)
    case system(String)
    case emoji(String)
}

extension SpaceSidebarSnapshotIcon {
    var accentGlyphText: String? {
        if case .emoji(let glyph) = self {
            return glyph
        }
        return nil
    }

    var accentSystemImageName: String? {
        if case .system(let systemName) = self {
            return systemName
        }
        return nil
    }
}

struct SpaceTabRowSnapshot: Identifiable {
    let id: UUID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let isSelected: Bool
    let showsUnloadedIndicator: Bool
    let showsAudioButton: Bool
    let isMuted: Bool
}

struct SpaceShortcutSnapshot: Identifiable {
    let id: UUID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let accentSource: SpaceShortcutSnapshotAccentSource
    let essentialBackdrop: Image?
    let presentationState: ShortcutPresentationState
    let showsAudioButton: Bool
    let isMuted: Bool
    let showsSplitOutline: Bool
}

struct SpaceShortcutSnapshotAccentSource: Equatable {
    let launchURL: URL
    let partition: SumiFaviconPartition
}

struct SpaceFolderSnapshot: Identifiable {
    let id: UUID
    let title: String
    let iconValue: String
    let isOpen: Bool
    let hasActiveSelection: Bool
    let bodyChildren: [SpacePinnedItemSnapshot]
}

struct SpaceSplitGroupMemberSnapshot: Identifiable {
    let id: SplitMemberID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let accentSource: SpaceShortcutSnapshotAccentSource?
    let essentialBackdrop: Image?
    let isSelected: Bool
}

struct SpaceSplitGroupSnapshot: Identifiable {
    let id: UUID
    let members: [SpaceSplitGroupMemberSnapshot]
    let isSelected: Bool
    let isLoaded: Bool
}

indirect enum SpacePinnedItemSnapshot: Identifiable {
    case folder(SpaceFolderSnapshot)
    case shortcut(SpaceShortcutSnapshot)
    case splitGroup(SpaceSplitGroupSnapshot)

    var id: UUID {
        switch self {
        case .folder(let folder):
            return folder.id
        case .shortcut(let shortcut):
            return shortcut.id
        case .splitGroup(let splitGroup):
            return splitGroup.id
        }
    }
}

private extension Array where Element == SpacePinnedItemSnapshot {
    var containsActiveSelection: Bool {
        contains { item in
            switch item {
            case .folder(let folder):
                return folder.hasActiveSelection || folder.bodyChildren.containsActiveSelection
            case .shortcut(let shortcut):
                return shortcut.presentationState.isSelected
            case .splitGroup(let splitGroup):
                return splitGroup.isSelected
            }
        }
    }
}

enum EssentialsSnapshotItem: Identifiable {
    case shortcut(SpaceShortcutSnapshot)
    case splitGroup(SpaceSplitGroupSnapshot)

    var id: UUID {
        switch self {
        case .shortcut(let shortcut): shortcut.id
        case .splitGroup(let group): group.id
        }
    }
}

struct EssentialsSnapshot {
    let items: [EssentialsSnapshotItem]
}

struct ExtensionActionSlotSnapshot: Identifiable {
    let id: String
    let icon: NSImage?
    let badgeText: String?
    let hasUnreadBadgeText: Bool
}

struct ExtensionActionGridSnapshot {
    let slots: [ExtensionActionSlotSnapshot]
}

struct SpaceSidebarPageSnapshot {
    let spaceId: UUID
    let title: String
    let iconValue: String
    let extensionActions: ExtensionActionGridSnapshot?
    let essentials: EssentialsSnapshot?
    let hasPinnedContent: Bool
    let isPinnedContentCollapsed: Bool
    let pinnedItems: [SpacePinnedItemSnapshot]
    let regularTabs: [SpaceTabRowSnapshot]
    let showsNewTabButtonInList: Bool
    let showsTopNewTabButton: Bool
    let rowCornerRadius: CGFloat
    let scrollViewport: SpaceSidebarSnapshotViewport
}

struct SpaceSidebarTransitionSnapshot {
    let source: SpaceSidebarPageSnapshot
    let destination: SpaceSidebarPageSnapshot
    let stationaryEssentials: EssentialsSnapshot?

    func page(for spaceId: UUID) -> SpaceSidebarPageSnapshot? {
        if source.spaceId == spaceId {
            return source
        }
        if destination.spaceId == spaceId {
            return destination
        }
        return nil
    }

    func matches(sourceSpaceId: UUID, destinationSpaceId: UUID) -> Bool {
        source.spaceId == sourceSpaceId && destination.spaceId == destinationSpaceId
    }

    func matches(_ transitionState: SpaceSidebarTransitionState) -> Bool {
        guard let sourceSpaceId = transitionState.sourceSpaceId,
              let destinationSpaceId = transitionState.destinationSpaceId else {
            return false
        }
        return matches(sourceSpaceId: sourceSpaceId, destinationSpaceId: destinationSpaceId)
    }
}

@MainActor
enum SpaceSidebarTransitionSnapshotBuilder {
    static func make(
        sourceSpace: Space,
        destinationSpace: Space,
        browserContext: SidebarBrowserContext,
        spaceCatalog: SidebarSpaceCatalogProjection,
        inventory: SidebarSpaceInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        scrollViewportForSpace: (UUID) -> SpaceSidebarSnapshotViewport? = { _ in nil }
    ) -> SpaceSidebarTransitionSnapshot {
        let sourceProfileId = resolvedProfileId(
            for: sourceSpace,
            browserContext: browserContext,
            windowState: windowState
        )
        let destinationProfileId = resolvedProfileId(
            for: destinationSpace,
            browserContext: browserContext,
            windowState: windowState
        )
        let sharedEssentials = SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
            sourceProfileId: sourceProfileId,
            destinationProfileId: destinationProfileId
        )

        let sourcePage = pageSnapshot(
            for: sourceSpace,
            profileId: sourceProfileId,
            browserContext: browserContext,
            spaceCatalog: spaceCatalog,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState,
            settings: settings,
            scrollViewport: scrollViewportForSpace(sourceSpace.id) ?? .zero
        )
        let destinationPage = pageSnapshot(
            for: destinationSpace,
            profileId: destinationProfileId,
            browserContext: browserContext,
            spaceCatalog: spaceCatalog,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState,
            settings: settings,
            scrollViewport: scrollViewportForSpace(destinationSpace.id) ?? .zero
        )
        let stationaryEssentials = sharedEssentials && !windowState.isIncognito
            ? essentialsSnapshot(
                profileId: sourceProfileId,
                spaceCatalog: spaceCatalog,
                spaceInventory: inventory.snapshot(for: sourceSpace.id),
                selection: selection,
                pinProjection: pinProjection,
                imageReader: browserContext.faviconImageReader,
                backdropReader: browserContext.essentialBackdropReader,
                windowState: windowState
            )
            : nil

        return SpaceSidebarTransitionSnapshot(
            source: sourcePage,
            destination: destinationPage,
            stationaryEssentials: stationaryEssentials
        )
    }

    private static func pageSnapshot(
        for space: Space,
        profileId: UUID?,
        browserContext: SidebarBrowserContext,
        spaceCatalog: SidebarSpaceCatalogProjection,
        inventory: SidebarSpaceInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        scrollViewport: SpaceSidebarSnapshotViewport
    ) -> SpaceSidebarPageSnapshot {
        let projection = windowState.isIncognito ? nil : inventory.snapshot(for: space.id)
        let tabs = windowState.isIncognito
            ? windowState.ephemeralTabs.sorted { $0.index < $1.index }
            : (projection?.regularTabs ?? [])
        let currentTabID = selection.selectedTabID(in: windowState)
        let regularTabs = tabs.map {
            tabSnapshot($0, currentTabId: currentTabID)
        }
        let hasPinnedContent = projection?.topLevelItems.isEmpty == false
        let isPinnedContentCollapsed = hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
        let pinnedItems = isPinnedContentCollapsed
            ? collapsedPinnedItemsSnapshot(
                space: space,
                projection: projection,
                selection: selection,
                pinProjection: pinProjection,
                imageReader: browserContext.faviconImageReader,
                windowState: windowState
            )
            : pinnedItemsSnapshot(
                projection: projection,
                selection: selection,
                pinProjection: pinProjection,
                imageReader: browserContext.faviconImageReader,
                windowState: windowState
            )

        return SpaceSidebarPageSnapshot(
            spaceId: space.id,
            title: space.name,
            iconValue: space.icon,
            extensionActions: windowState.isIncognito
                ? nil
                : extensionActionsSnapshot(
                    profileId: profileId,
                    browserContext: browserContext
                ),
            essentials: windowState.isIncognito
                ? nil
                : essentialsSnapshot(
                    profileId: profileId,
                    spaceCatalog: spaceCatalog,
                    spaceInventory: projection,
                    selection: selection,
                    pinProjection: pinProjection,
                    imageReader: browserContext.faviconImageReader,
                    backdropReader: browserContext.essentialBackdropReader,
                    windowState: windowState
                ),
            hasPinnedContent: hasPinnedContent,
            isPinnedContentCollapsed: isPinnedContentCollapsed,
            pinnedItems: pinnedItems,
            regularTabs: regularTabs,
            showsNewTabButtonInList: settings.showNewTabButtonInTabList,
            showsTopNewTabButton: settings.tabListNewTabButtonPosition == .top,
            rowCornerRadius: settings.resolvedCornerRadius(12),
            scrollViewport: scrollViewport
        )
    }

    private static func extensionActionsSnapshot(
        profileId: UUID?,
        browserContext: SidebarBrowserContext
    ) -> ExtensionActionGridSnapshot? {
        let surfaceStore = browserContext.extensionSurfaceStore
        let slots = browserContext.extensionToolbarActions.orderedPinnedToolbarSlots(
            enabledExtensions: surfaceStore.toolbarDisplaySnapshot.enabledExtensions,
            profileID: profileId
        )
        guard ExtensionActionPlacement.resolve(totalActions: slots.count) == .sidebarGrid else {
            return nil
        }

        return transitionExtensionActionsSnapshot(
            slots: slots,
            surfaceStore: surfaceStore
        )
    }

    static func transitionExtensionActionsSnapshot(
        slots: [PinnedToolbarSlot],
        surfaceStore: BrowserExtensionSurfaceStore
    ) -> ExtensionActionGridSnapshot {
        let snapshots = slots.map { slot -> ExtensionActionSlotSnapshot in
            switch slot {
            case .webExtension(let ext):
                return ExtensionActionSlotSnapshot(
                    id: ext.id,
                    icon: extensionIcon(for: ext, surfaceStore: surfaceStore),
                    badgeText: nil,
                    hasUnreadBadgeText: false
                )
            }
        }

        return ExtensionActionGridSnapshot(slots: snapshots)
    }

    private static func extensionIcon(
        for extensionRecord: BrowserExtensionToolbarDisplayRecord,
        surfaceStore: BrowserExtensionSurfaceStore
    ) -> NSImage? {
        guard let iconPath = extensionRecord.iconPath else { return nil }
        return surfaceStore.iconCache.image(
            extensionId: extensionRecord.id,
            iconPath: iconPath
        )
    }

    private static func resolvedProfileId(
        for space: Space?,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> UUID? {
        space?.profileId
            ?? windowState.currentProfileId
            ?? browserContext.profileAuthority.currentProfile?.id
    }

    private static func essentialsSnapshot(
        profileId: UUID?,
        spaceCatalog: SidebarSpaceCatalogProjection,
        spaceInventory: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        imageReader: any BrowserFaviconImageReading,
        backdropReader: any BrowserEssentialBackdropReading,
        windowState: BrowserWindowState
    ) -> EssentialsSnapshot {
        guard let profileId else { return EssentialsSnapshot(items: []) }
        let pins = spaceCatalog.essentialPins(profileID: profileId)
        let visualItems = SidebarEssentialVisualProjection.make(
            pins: pins,
            splitGroups: spaceInventory.map {
                Array($0.splitGroupsByID.values)
            } ?? [],
            profileID: profileId
        )
        let splitContext = spaceInventory.map { inventory in
            FolderSnapshotContext(
                childFoldersByParentId: inventory.childFoldersByParentID,
                folderPinsByFolderId: inventory.folderPinsByFolderID,
                liveTabsByPinId: Dictionary(
                    uniqueKeysWithValues: pins.compactMap { pin in
                        selection.liveTab(for: pin.id, in: windowState).map {
                            (pin.id, $0)
                        }
                    }
                ),
                inventory: inventory,
                selection: selection,
                pinProjection: pinProjection,
                imageReader: imageReader,
                windowState: windowState
            )
        }
        return EssentialsSnapshot(
            items: visualItems.compactMap { item in
                switch item {
                case .pin(let pin):
                    return .shortcut(
                        shortcutSnapshot(
                            for: pin,
                            liveTab: selection.liveTab(for: pin.id, in: windowState),
                            inventory: spaceInventory,
                            selection: selection,
                            pinProjection: pinProjection,
                            imageReader: imageReader,
                            backdropReader: backdropReader,
                            windowState: windowState
                        )
                    )
                case .splitGroup(let group):
                    guard let splitContext else { return nil }
                    return .splitGroup(
                        splitGroupSnapshot(
                            for: group,
                            context: splitContext,
                            backdropReader: backdropReader
                        )
                    )
                }
            }
        )
    }

    private struct FolderSnapshotContext {
        let childFoldersByParentId: [UUID: [TabFolder]]
        let folderPinsByFolderId: [UUID: [ShortcutPin]]
        let liveTabsByPinId: [UUID: Tab]
        let inventory: SidebarSpaceInventorySnapshot
        let selection: SidebarWindowSelectionQuery
        let pinProjection: SidebarPinFolderProjection
        let imageReader: any BrowserFaviconImageReading
        let windowState: BrowserWindowState
    }

    private static func pinnedItemsSnapshot(
        projection: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        imageReader: any BrowserFaviconImageReading,
        windowState: BrowserWindowState
    ) -> [SpacePinnedItemSnapshot] {
        guard let projection else { return [] }
        let folderContext = FolderSnapshotContext(
            childFoldersByParentId: projection.childFoldersByParentID,
            folderPinsByFolderId: projection.folderPinsByFolderID,
            liveTabsByPinId: Dictionary(
                uniqueKeysWithValues: projection.pinsByID.values.compactMap { pin in
                    selection.liveTab(for: pin.id, in: windowState).map { (pin.id, $0) }
                }
            ),
            inventory: projection,
            selection: selection,
            pinProjection: pinProjection,
            imageReader: imageReader,
            windowState: windowState
        )

        return projection.topLevelItems.compactMap {
            pinnedItemSnapshot(
                for: $0,
                context: folderContext,
                visitedFolderIds: []
            )
        }
    }

    private static func collapsedPinnedItemsSnapshot(
        space: Space,
        projection: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        imageReader: any BrowserFaviconImageReading,
        windowState: BrowserWindowState
    ) -> [SpacePinnedItemSnapshot] {
        guard let projection else { return [] }
        let context = FolderSnapshotContext(
            childFoldersByParentId: projection.childFoldersByParentID,
            folderPinsByFolderId: projection.folderPinsByFolderID,
            liveTabsByPinId: Dictionary(
                uniqueKeysWithValues: projection.pinsByID.values.compactMap { pin in
                    selection.liveTab(for: pin.id, in: windowState).map { (pin.id, $0) }
                }
            ),
            inventory: projection,
            selection: selection,
            pinProjection: pinProjection,
            imageReader: imageReader,
            windowState: windowState
        )
        let owner = SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: projection,
            selection: selection,
            selectionSnapshot: SidebarWindowSelectionSnapshot(windowState: windowState),
            windowState: windowState
        )
        return owner.visibleStickyItemIDs.compactMap { itemID in
            if projection.pin(id: itemID) != nil {
                return pinnedItemSnapshot(
                    for: .shortcut(itemID),
                    context: context,
                    visitedFolderIds: []
                )
            }
            if projection.splitGroup(id: itemID) != nil {
                return pinnedItemSnapshot(
                    for: .splitGroup(itemID),
                    context: context,
                    visitedFolderIds: []
                )
            }
            return nil
        }
    }

    private static func pinnedItemSnapshot(
        for item: SidebarPinnedInventoryItem,
        context: FolderSnapshotContext,
        visitedFolderIds: Set<UUID>
    ) -> SpacePinnedItemSnapshot? {
        switch item {
        case .folder(let folderID):
            guard !visitedFolderIds.contains(folderID),
                  let folder = context.inventory.folder(id: folderID) else { return nil }
            return .folder(
                folderSnapshot(
                    for: folder,
                    context: context,
                    visitedFolderIds: visitedFolderIds
                )
            )
        case .shortcut(let pinID):
            guard let pin = context.inventory.pin(id: pinID) else { return nil }
            return .shortcut(
                shortcutSnapshot(
                    for: pin,
                    liveTab: context.liveTabsByPinId[pin.id],
                    inventory: context.inventory,
                    selection: context.selection,
                    pinProjection: context.pinProjection,
                    imageReader: context.imageReader,
                    windowState: context.windowState
                )
            )
        case .splitGroup(let groupID):
            guard let group = context.inventory.splitGroup(id: groupID) else { return nil }
            return .splitGroup(splitGroupSnapshot(for: group, context: context))
        }
    }

    private static func doesFolderContainActiveSelection(
        folderId: UUID,
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        selection: SidebarWindowSelectionQuery,
        windowState: BrowserWindowState
    ) -> Bool {
        for pin in folderPinsByFolderId.values.flatMap({ $0 })
        where selection.isShortcutSelected(pin, in: windowState) {
            if doesFolderContainPin(folderId: folderId, pinId: pin.id, childFoldersByParentId: childFoldersByParentId, folderPinsByFolderId: folderPinsByFolderId) {
                return true
            }
        }
        if let currentTabId = selection.selectedTabID(in: windowState) {
            if doesFolderContainLiveTab(folderId: folderId, tabId: currentTabId, childFoldersByParentId: childFoldersByParentId, folderPinsByFolderId: folderPinsByFolderId, liveTabsByPinId: liveTabsByPinId) {
                return true
            }
        }
        return false
    }

    private static func doesFolderContainPin(
        folderId: UUID,
        pinId: UUID,
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]]
    ) -> Bool {
        if let pins = folderPinsByFolderId[folderId], pins.contains(where: { $0.id == pinId }) {
            return true
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if doesFolderContainPin(folderId: child.id, pinId: pinId, childFoldersByParentId: childFoldersByParentId, folderPinsByFolderId: folderPinsByFolderId) {
                    return true
                }
            }
        }
        return false
    }

    private static func doesFolderContainLiveTab(
        folderId: UUID,
        tabId: UUID,
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab]
    ) -> Bool {
        if let pins = folderPinsByFolderId[folderId] {
            for pin in pins {
                if liveTabsByPinId[pin.id]?.id == tabId {
                    return true
                }
            }
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if doesFolderContainLiveTab(folderId: child.id, tabId: tabId, childFoldersByParentId: childFoldersByParentId, folderPinsByFolderId: folderPinsByFolderId, liveTabsByPinId: liveTabsByPinId) {
                    return true
                }
            }
        }
        return false
    }

    private static func folderSnapshot(
        for folder: TabFolder,
        context: FolderSnapshotContext,
        visitedFolderIds: Set<UUID>
    ) -> SpaceFolderSnapshot {
        var nextVisited = visitedFolderIds
        nextVisited.insert(folder.id)
        let projectionState = context.windowState.sidebarFolderProjections
            .pendingOrCurrentProjection(for: folder.id)

        let bodyChildren: [SpacePinnedItemSnapshot]
        let hasActiveSelection: Bool

        if folder.isOpen {
            bodyChildren = folderBodyChildSnapshots(
                items: context.inventory.folderItems(for: folder.id),
                context: context,
                visitedFolderIds: nextVisited
            )
            hasActiveSelection = projectionState.hasActiveProjection || bodyChildren.containsActiveSelection
        } else {
            bodyChildren = collapsedStickyItems(
                for: folder.id,
                context: context,
                projectionState: projectionState
            )
            hasActiveSelection = projectionState.hasActiveProjection || doesFolderContainActiveSelection(
                folderId: folder.id,
                childFoldersByParentId: context.childFoldersByParentId,
                folderPinsByFolderId: context.folderPinsByFolderId,
                liveTabsByPinId: context.liveTabsByPinId,
                selection: context.selection,
                windowState: context.windowState
            )
        }

        return SpaceFolderSnapshot(
            id: folder.id,
            title: folder.name,
            iconValue: folder.icon,
            isOpen: folder.isOpen,
            hasActiveSelection: hasActiveSelection || (!folder.isOpen && !bodyChildren.isEmpty),
            bodyChildren: bodyChildren
        )
    }

    private static func folderBodyChildSnapshots(
        items: [SidebarPinnedInventoryItem],
        context: FolderSnapshotContext,
        visitedFolderIds: Set<UUID>
    ) -> [SpacePinnedItemSnapshot] {
        items.compactMap {
            pinnedItemSnapshot(
                for: $0,
                context: context,
                visitedFolderIds: visitedFolderIds
            )
        }
    }

    private static func collapsedStickyItems(
        for folderId: UUID,
        context: FolderSnapshotContext,
        projectionState: SidebarFolderProjectionState
    ) -> [SpacePinnedItemSnapshot] {
        let liveItemsByID = Dictionary(
            uniqueKeysWithValues: SidebarVisualSceneProjection(
                inventory: context.inventory,
                selection: context.selection,
                selectionSnapshot: SidebarWindowSelectionSnapshot(
                    windowState: context.windowState
                ),
                windowState: context.windowState
            ).launcherItems(context.inventory.descendantItems(for: folderId)).map {
                ($0.id, $0)
            }
        )
        return projectionState.stickyItemIDs.compactMap { itemID in
            guard let item = liveItemsByID[itemID], item.isLive else { return nil }
            return pinnedItemSnapshot(
                for: item.source,
                context: context,
                visitedFolderIds: []
            )
        }
    }

    private static func splitGroupSnapshot(
        for group: SplitGroup,
        context: FolderSnapshotContext,
        backdropReader: (any BrowserEssentialBackdropReading)? = nil
    ) -> SpaceSplitGroupSnapshot {
        let selectionSnapshot = SidebarWindowSelectionSnapshot(
            windowState: context.windowState
        )
        let items = SplitGroupSidebarModel.items(
            for: group,
            inventory: context.inventory,
            selection: context.selection,
            windowState: context.windowState
        )
        let members = items.map { item in
            let icon: SpaceSidebarSnapshotIcon
            if let pin = item.pin {
                icon = shortcutIcon(
                    for: pin,
                    liveTab: item.tab,
                    faviconPartition: context.pinProjection.faviconPartition(
                        for: pin,
                        currentSpaceID: context.inventory.spaceID
                    ),
                    imageReader: context.imageReader
                )
            } else if let tab = item.tab {
                icon = tabIcon(for: tab)
            } else {
                icon = .system("globe")
            }
            return SpaceSplitGroupMemberSnapshot(
                id: item.id,
                title: item.title,
                icon: icon,
                accentSource: item.pin.map { pin in
                    SpaceShortcutSnapshotAccentSource(
                        launchURL: pin.launchURL,
                        partition: context.pinProjection.faviconPartition(
                            for: pin,
                            currentSpaceID: context.inventory.spaceID
                        )
                    )
                },
                essentialBackdrop: item.pin.flatMap { pin in
                    backdropReader?.cachedBackdrop(
                        for: pin.launchURL,
                        partition: context.pinProjection.faviconPartition(
                            for: pin,
                            currentSpaceID: context.inventory.spaceID
                        )
                    ).map(Image.init(nsImage:))
                },
                isSelected: selectionSnapshot.splitSelection?.groupID == group.id
                    && selectionSnapshot.splitSelection?.activeMemberID == item.id
            )
        }
        return SpaceSplitGroupSnapshot(
            id: group.id,
            members: members,
            isSelected: context.selection.isSplitGroupSelected(
                group,
                in: context.windowState,
                selection: selectionSnapshot
            ),
            isLoaded: SidebarVisualSceneProjection.isWholeSplitGroupLive(
                group,
                items: items
            )
        )
    }

    private static func shortcutSnapshot(
        for pin: ShortcutPin,
        liveTab: Tab?,
        inventory: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        imageReader: any BrowserFaviconImageReading,
        backdropReader: (any BrowserEssentialBackdropReading)? = nil,
        windowState: BrowserWindowState
    ) -> SpaceShortcutSnapshot {
        let presentationState = selection.presentationState(for: pin, in: windowState)
        let faviconPartition = pinProjection.faviconPartition(
            for: pin,
            currentSpaceID: pin.spaceId ?? windowState.currentSpaceId
        )
        let isInVisibleSplit = liveTab.map {
            selection.selectedSplitGroup(in: windowState)?.contains(.regularTab($0.id)) == true
        } == true
        let essentialRuntimeState = selection.essentialRuntimeState(for: pin, in: windowState)
        let isSplitPlaceholder = inventory?.splitGroup(
            containing: .shortcutPin(pin.id)
        ).map { !$0.container.isShortcutSidebar } == true

        return SpaceShortcutSnapshot(
            id: pin.id,
            title: pin.resolvedDisplayTitle(liveTab: liveTab),
            icon: shortcutIcon(
                for: pin,
                liveTab: liveTab,
                faviconPartition: faviconPartition,
                imageReader: imageReader
            ),
            accentSource: SpaceShortcutSnapshotAccentSource(
                launchURL: pin.launchURL,
                partition: faviconPartition
            ),
            essentialBackdrop: backdropReader?.cachedBackdrop(
                for: pin.launchURL,
                partition: faviconPartition
            ).map(Image.init(nsImage:)),
            presentationState: presentationState,
            showsAudioButton: liveTab?.audioState.showsTabAudioButton ?? false,
            isMuted: liveTab?.audioState.isMuted ?? false,
            showsSplitOutline: isSplitPlaceholder
                || essentialRuntimeState?.showsSplitProxyOutline == true
                || isInVisibleSplit
        )
    }

    private static func tabSnapshot(
        _ tab: Tab,
        currentTabId: UUID?
    ) -> SpaceTabRowSnapshot {
        SpaceTabRowSnapshot(
            id: tab.id,
            title: tab.name,
            icon: tabIcon(for: tab),
            isSelected: currentTabId == tab.id,
            showsUnloadedIndicator: tab.showsWebViewUnloadedIndicator,
            showsAudioButton: tab.audioState.showsTabAudioButton,
            isMuted: tab.audioState.isMuted
        )
    }

    private static func tabIcon(for tab: Tab) -> SpaceSidebarSnapshotIcon {
        guard tab.usesChromeThemedTemplateFavicon else {
            return .image(tab.favicon)
        }

        if tab.representsSumiSettingsSurface {
            return .system(SumiSurface.settingsTabFaviconSystemImageName)
        }
        if tab.representsSumiHistorySurface {
            return .system(SumiSurface.historyTabFaviconSystemImageName)
        }
        if tab.representsSumiBookmarksSurface {
            return .system(SumiSurface.bookmarksTabFaviconSystemImageName)
        }
        return .system("globe")
    }

    private static func shortcutIcon(
        for pin: ShortcutPin,
        liveTab: Tab?,
        faviconPartition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    ) -> SpaceSidebarSnapshotIcon {
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return .emoji(iconAsset)
            }
            return .system(SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
        }

        if let liveTab {
            if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
                return .system(SumiSurface.settingsTabFaviconSystemImageName)
            }

            if let cachedFavicon = ShortcutPin.cachedLaunchFavicon(
                for: pin.launchURL,
                partition: faviconPartition,
                imageReader: imageReader
            ) {
                return .image(cachedFavicon)
            }

            if !liveTab.faviconIsTemplateGlobePlaceholder {
                return .image(liveTab.favicon)
            }

            return .system(SumiPersistentGlyph.launcherSystemImageFallback)
        }

        if let systemName = pin.storedChromeTemplateSystemImageName(
            for: faviconPartition,
            imageReader: imageReader
        ) {
            return .system(systemName)
        }

        return .image(
            pin.storedFaviconImage(
                partition: faviconPartition,
                imageReader: imageReader
            )
        )
    }
}
