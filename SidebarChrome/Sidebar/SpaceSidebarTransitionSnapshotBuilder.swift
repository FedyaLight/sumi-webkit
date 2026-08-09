import SumiDomain
import SwiftUI

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
        let sharedFavorite = SpaceSidebarFavoritePlacementPolicy.usesSharedPinnedGrid(
            sourceProfileId: sourceProfileId,
            destinationProfileId: destinationProfileId
        )
        let sourceProjection = windowState.isIncognito
            ? nil : inventory.snapshot(for: sourceSpace.id)
        let destinationProjection = windowState.isIncognito
            ? nil : inventory.snapshot(for: destinationSpace.id)
        var launcherPinIDs = Set<UUID>()
        if let sourceProjection {
            launcherPinIDs.formUnion(sourceProjection.pinsByID.keys)
        }
        if let destinationProjection {
            launcherPinIDs.formUnion(destinationProjection.pinsByID.keys)
        }
        if let sourceProfileId {
            launcherPinIDs.formUnion(
                spaceCatalog.favoritePins(profileID: sourceProfileId).map(\.id)
            )
        }
        if let destinationProfileId {
            launcherPinIDs.formUnion(
                spaceCatalog.favoritePins(profileID: destinationProfileId).map(\.id)
            )
        }
        let launcherRuntime = selection.launcherRuntimeSnapshot(
            pinIDs: launcherPinIDs,
            in: windowState
        )

        let sourcePage = pageSnapshot(
            for: sourceSpace,
            profileId: sourceProfileId,
            browserContext: browserContext,
            spaceCatalog: spaceCatalog,
            projection: sourceProjection,
            launcherRuntime: launcherRuntime,
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
            projection: destinationProjection,
            launcherRuntime: launcherRuntime,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState,
            settings: settings,
            scrollViewport: scrollViewportForSpace(destinationSpace.id) ?? .zero
        )
        let stationaryFavorite = sharedFavorite && !windowState.isIncognito
            ? favoriteSnapshot(
                profileId: sourceProfileId,
                spaceCatalog: spaceCatalog,
                spaceInventory: sourceProjection,
                launcherRuntime: launcherRuntime,
                selection: selection,
                pinProjection: pinProjection,
                backdropReader: browserContext.favoriteBackdropReader,
                windowState: windowState,
                settings: settings
            )
            : nil

        return SpaceSidebarTransitionSnapshot(
            source: sourcePage,
            destination: destinationPage,
            stationaryFavorite: stationaryFavorite
        )
    }

    private static func pageSnapshot(
        for space: Space,
        profileId: UUID?,
        browserContext: SidebarBrowserContext,
        spaceCatalog: SidebarSpaceCatalogProjection,
        projection: SidebarSpaceInventorySnapshot?,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        scrollViewport: SpaceSidebarSnapshotViewport
    ) -> SpaceSidebarPageSnapshot {
        let tabs = windowState.isIncognito
            ? windowState.ephemeralTabs.sorted { $0.index < $1.index }
            : (projection?.regularTabs ?? [])
        let currentTabID = selection.selectedTabID(in: windowState)
        let regularRows = SpaceSidebarTransitionItemSnapshotProjector
            .regularRowsSnapshot(
            tabs: tabs,
            projection: projection,
            selection: selection,
            pinProjection: pinProjection,
            windowState: windowState,
            currentTabID: currentTabID
        )
        let hasPinnedContent = projection?.topLevelItems.isEmpty == false
        let isPinnedContentCollapsed = hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
        let pinnedItems = isPinnedContentCollapsed
            ? SpaceSidebarTransitionItemSnapshotProjector
                .collapsedPinnedItemsSnapshot(
                space: space,
                projection: projection,
                launcherRuntime: launcherRuntime,
                selection: selection,
                pinProjection: pinProjection,
                windowState: windowState
            )
            : SpaceSidebarTransitionItemSnapshotProjector
                .pinnedItemsSnapshot(
                projection: projection,
                launcherRuntime: launcherRuntime,
                selection: selection,
                pinProjection: pinProjection,
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
            favorite: windowState.isIncognito
                ? nil
                : favoriteSnapshot(
                    profileId: profileId,
                    spaceCatalog: spaceCatalog,
                    spaceInventory: projection,
                    launcherRuntime: launcherRuntime,
                    selection: selection,
                    pinProjection: pinProjection,
                    backdropReader: browserContext.favoriteBackdropReader,
                    windowState: windowState,
                    settings: settings
                ),
            supportsPinnedContent: !windowState.isIncognito,
            hasPinnedContent: hasPinnedContent,
            isPinnedContentCollapsed: isPinnedContentCollapsed,
            pinnedItems: pinnedItems,
            regularRows: regularRows,
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

    private static func favoriteSnapshot(
        profileId: UUID?,
        spaceCatalog: SidebarSpaceCatalogProjection,
        spaceInventory: SidebarSpaceInventorySnapshot?,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        backdropReader: any BrowserFavoriteBackdropReading,
        windowState: BrowserWindowState,
        settings: SumiSettingsService
    ) -> FavoriteSnapshot {
        guard let profileId else {
            return FavoriteSnapshot(items: [], showsPlaceholder: false)
        }
        let showsPlaceholder = settings.showsFavoritePlaceholder(profileId: profileId)
        let pins = spaceCatalog.favoritePins(profileID: profileId)
        let visualItems = SidebarFavoriteVisualProjection.make(
            pins: pins,
            splitGroups: spaceInventory.map {
                Array($0.splitGroupsByID.values)
            } ?? [],
            profileID: profileId
        )
        let splitContext = spaceInventory.map { inventory in
            SpaceSidebarTransitionItemSnapshotProjector.FolderSnapshotContext(
                childFoldersByParentId: inventory.childFoldersByParentID,
                folderPinsByFolderId: inventory.folderPinsByFolderID,
                splitPinsById: Dictionary(
                    uniqueKeysWithValues: pins.map { ($0.id, $0) }
                ),
                launcherRuntime: launcherRuntime,
                inventory: inventory,
                selection: selection,
                pinProjection: pinProjection,
                windowState: windowState
            )
        }
        return FavoriteSnapshot(
            items: visualItems.compactMap { item in
                switch item {
                case .pin(let pin):
                    return .shortcut(
                        SpaceSidebarTransitionItemSnapshotProjector
                            .shortcutSnapshot(
                            for: pin,
                            liveTab: launcherRuntime.liveTab(for: pin.id),
                            inventory: spaceInventory,
                            selection: selection,
                            pinProjection: pinProjection,
                            backdropReader: backdropReader,
                            windowState: windowState
                        )
                    )
                case .splitGroup(let group):
                    guard let splitContext else { return nil }
                    return .splitGroup(
                        SpaceSidebarTransitionItemSnapshotProjector
                            .splitGroupSnapshot(
                            for: group,
                            context: splitContext,
                            backdropReader: backdropReader
                        )
                    )
                }
            },
            showsPlaceholder: showsPlaceholder
        )
    }

}
