import SumiDomain
import SwiftUI

@MainActor
enum SpaceSidebarTransitionItemSnapshotProjector {
    struct FolderSnapshotContext {
        let childFoldersByParentId: [UUID: [TabFolder]]
        let folderPinsByFolderId: [UUID: [ShortcutPin]]
        let splitPinsById: [UUID: ShortcutPin]
        let launcherRuntime: SidebarLauncherRuntimeSnapshot
        let inventory: SidebarSpaceInventorySnapshot
        let selection: SidebarWindowSelectionQuery
        let pinProjection: SidebarPinFolderProjection
        let windowState: BrowserWindowState
    }

    static func pinnedItemsSnapshot(
        projection: SidebarSpaceInventorySnapshot?,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState
    ) -> [SpacePinnedItemSnapshot] {
        guard let projection else { return [] }
        let folderContext = FolderSnapshotContext(
            childFoldersByParentId: projection.childFoldersByParentID,
            folderPinsByFolderId: projection.folderPinsByFolderID,
            splitPinsById: projection.pinsByID,
            launcherRuntime: launcherRuntime,
            inventory: projection,
            selection: selection,
            pinProjection: pinProjection,
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

    static func regularRowsSnapshot(
        tabs: [Tab],
        projection: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState,
        currentTabID: UUID?
    ) -> [SpaceRegularRowSnapshot] {
        guard let projection else {
            return tabs.map {
                .tab(tabSnapshot($0, currentTabId: currentTabID))
            }
        }

        let groups = projection.splitGroupsByID.values.filter {
            if case .regularTabs(let spaceID) = $0.container {
                return spaceID == projection.spaceID
            }
            return false
        }
        let groupsByID = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id, $0) }
        )
        let tabsByID = Dictionary(
            uniqueKeysWithValues: tabs.map { ($0.id, $0) }
        )
        let context = FolderSnapshotContext(
            childFoldersByParentId: projection.childFoldersByParentID,
            folderPinsByFolderId: projection.folderPinsByFolderID,
            splitPinsById: projection.pinsByID,
            launcherRuntime: .empty,
            inventory: projection,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState
        )

        return SidebarVisualSceneProjection.regularRun(
            tabIDs: tabs.map(\.id),
            groups: groups
        ).rows.compactMap { row in
            switch row.identity {
            case .tab(let tabID):
                return tabsByID[tabID].map {
                    .tab(tabSnapshot($0, currentTabId: currentTabID))
                }
            case .splitGroup(let groupID):
                return groupsByID[groupID].map {
                    .splitGroup(splitGroupSnapshot(for: $0, context: context))
                }
            }
        }
    }

    static func collapsedPinnedItemsSnapshot(
        space: Space,
        projection: SidebarSpaceInventorySnapshot?,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState
    ) -> [SpacePinnedItemSnapshot] {
        guard let projection else { return [] }
        let context = FolderSnapshotContext(
            childFoldersByParentId: projection.childFoldersByParentID,
            folderPinsByFolderId: projection.folderPinsByFolderID,
            splitPinsById: projection.pinsByID,
            launcherRuntime: launcherRuntime,
            inventory: projection,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState
        )
        let owner = SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: projection,
            launcherRuntime: launcherRuntime,
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
                    liveTab: context.launcherRuntime.liveTab(for: pin.id),
                    inventory: context.inventory,
                    selection: context.selection,
                    pinProjection: context.pinProjection,
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
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
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
            if doesFolderContainLiveTab(
                folderId: folderId,
                tabId: currentTabId,
                childFoldersByParentId: childFoldersByParentId,
                folderPinsByFolderId: folderPinsByFolderId,
                launcherRuntime: launcherRuntime
            ) {
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
        launcherRuntime: SidebarLauncherRuntimeSnapshot
    ) -> Bool {
        if let pins = folderPinsByFolderId[folderId] {
            for pin in pins {
                if launcherRuntime.liveTab(for: pin.id)?.id == tabId {
                    return true
                }
            }
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if doesFolderContainLiveTab(
                    folderId: child.id,
                    tabId: tabId,
                    childFoldersByParentId: childFoldersByParentId,
                    folderPinsByFolderId: folderPinsByFolderId,
                    launcherRuntime: launcherRuntime
                ) {
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
        let presentation = context.inventory.folderPresentation(id: folder.id)
        let isExpanded = presentation?.isExpanded ?? folder.isOpen

        let bodyChildren: [SpacePinnedItemSnapshot]
        let hasActiveSelection: Bool

        if isExpanded {
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
                launcherRuntime: context.launcherRuntime,
                selection: context.selection,
                windowState: context.windowState
            )
        }

        return SpaceFolderSnapshot(
            id: folder.id,
            title: presentation?.title ?? folder.name,
            iconValue: presentation?.iconValue ?? folder.icon,
            isOpen: isExpanded,
            hasActiveSelection: hasActiveSelection || (!isExpanded && !bodyChildren.isEmpty),
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
                launcherRuntime: context.launcherRuntime,
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

    static func splitGroupSnapshot(
        for group: SplitGroup,
        context: FolderSnapshotContext,
        backdropReader: (any BrowserEssentialBackdropReading)? = nil
    ) -> SpaceSplitGroupSnapshot {
        let selectionSnapshot = SidebarWindowSelectionSnapshot(
            windowState: context.windowState
        )
        let items = group.members.compactMap {
            member -> SplitGroupSidebarItem? in
            switch member.memberID {
            case .regularTab(let tabID):
                guard let tab = context.inventory.tab(id: tabID) else {
                    return nil
                }
                return SplitGroupSidebarItem.regular(member, tab: tab)

            case .shortcutPin(let pinID):
                guard let pin = context.splitPinsById[pinID] else {
                    return nil
                }
                return SplitGroupSidebarItem.shortcut(
                    member,
                    pin: pin,
                    liveTab: context.launcherRuntime.liveTab(for: pinID)
                )
            }
        }
        let members = items.map { item in
            let presentation = SplitGroupMemberIconResolver.resolve(
                item: item,
                loadedStoredFavicon: item.pin.flatMap { pin in
                    let partition = context.pinProjection.faviconPartition(
                        for: pin,
                        currentSpaceID: context.inventory.spaceID
                    )
                    return context.windowState.sidebarFaviconImageStore.image(
                        for: pin.launchURL,
                        partition: partition
                    )
                }
            )
            let fallbackIcon: SpaceSidebarSnapshotIcon
            if let glyphText = presentation.glyphText {
                fallbackIcon = .emoji(glyphText)
            } else if let systemImageName = presentation.systemImageName {
                fallbackIcon = .system(systemImageName)
            } else {
                fallbackIcon = .image(presentation.image)
            }
            let icon = resolvableIcon(
                for: item.pin,
                partition: item.pin.map {
                    context.pinProjection.faviconPartition(
                        for: $0,
                        currentSpaceID: context.inventory.spaceID
                    )
                },
                fallback: fallbackIcon
            )
            return SpaceSplitGroupMemberSnapshot(
                id: item.id,
                title: item.title,
                icon: icon,
                desaturatesIcon: presentation.shouldDesaturate,
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
            displayTitle: SplitGroupSidebarModel.displayTitle(for: group),
            customIcon: group.iconAsset.map { iconAsset in
                SumiPersistentGlyph.presentsAsEmoji(iconAsset)
                    ? .emoji(iconAsset)
                    : .system(
                        SumiPersistentGlyph.resolvedLauncherSystemImageName(
                            iconAsset
                        )
                    )
            },
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

    static func shortcutSnapshot(
        for pin: ShortcutPin,
        liveTab: Tab?,
        inventory: SidebarSpaceInventorySnapshot?,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        backdropReader: (any BrowserEssentialBackdropReading)? = nil,
        windowState: BrowserWindowState
    ) -> SpaceShortcutSnapshot {
        let presentationState = selection.presentationState(for: pin, in: windowState)
        let runtimeAffordance = selection.runtimeAffordance(
            for: pin,
            liveTab: liveTab,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
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

        let fallbackIcon = shortcutIcon(
            for: pin,
            liveTab: liveTab,
            faviconPartition: faviconPartition,
            faviconImageStore: windowState.sidebarFaviconImageStore
        )
        return SpaceShortcutSnapshot(
            id: pin.id,
            title: pin.resolvedDisplayTitle(liveTab: liveTab),
            icon: resolvableIcon(
                for: pin,
                partition: faviconPartition,
                fallback: fallbackIcon
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
                || isInVisibleSplit,
            showsChangedURLSlash: runtimeAffordance.showsChangedURLSlash
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
        faviconImageStore: SidebarFaviconImageStore
    ) -> SpaceSidebarSnapshotIcon {
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return .emoji(iconAsset)
            }
            return .system(SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
        }

        let presentation = SidebarShortcutIconResolver.resolve(
            pin: pin,
            liveTab: liveTab,
            loadedStoredFavicon: faviconImageStore.image(
                for: pin.launchURL,
                partition: faviconPartition
            )
        )
        if let glyphText = presentation.glyphText {
            return .emoji(glyphText)
        }
        if let systemImageName = presentation.systemImageName {
            return .system(systemImageName)
        }
        return presentation.image.map(SpaceSidebarSnapshotIcon.image)
            ?? .system(SumiPersistentGlyph.launcherSystemImageFallback)
    }

    private static func resolvableIcon(
        for pin: ShortcutPin?,
        partition: SumiFaviconPartition?,
        fallback: SpaceSidebarSnapshotIcon
    ) -> SpaceSidebarSnapshotIcon {
        guard let pin, pin.iconAsset == nil, let partition else {
            return fallback
        }
        return .resolvable(
            launchURL: pin.launchURL,
            partition: partition,
            fallback: fallback
        )
    }
}
