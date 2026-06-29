//
//  SpaceSidebarSnapshots.swift
//  Sumi
//
//

import SwiftUI

enum SpaceSidebarSnapshotFolderLayout {
    static let contentLeadingPadding: CGFloat = 14
    static let contentVerticalPadding: CGFloat = 4

    static func bodyHeight(childCount: Int) -> CGFloat {
        CGFloat(max(childCount, 0)) * SidebarRowLayout.rowHeight
            + contentVerticalPadding * 2
    }
}
enum SpaceSidebarSnapshotTitleLayout {
    static let trailingControlSize: CGFloat = 28
    static let verticalPadding: CGFloat = 5

    static var minimumHeight: CGFloat {
        trailingControlSize + verticalPadding * 2
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
    let presentationState: ShortcutPresentationState
    let showsAudioButton: Bool
    let isMuted: Bool
    let showsSplitOutline: Bool
}

struct SpaceFolderSnapshot: Identifiable {
    let id: UUID
    let title: String
    let iconValue: String
    let isOpen: Bool
    let hasActiveSelection: Bool
    let bodyChildren: [SpacePinnedItemSnapshot]
}

indirect enum SpacePinnedItemSnapshot: Identifiable {
    case folder(SpaceFolderSnapshot)
    case shortcut(SpaceShortcutSnapshot)

    var id: UUID {
        switch self {
        case .folder(let folder):
            return folder.id
        case .shortcut(let shortcut):
            return shortcut.id
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
            }
        }
    }
}

struct EssentialsSnapshot {
    let items: [SpaceShortcutSnapshot]
}

enum ExtensionActionSlotSnapshotKind {
    case sumiScriptsManager
    case webExtension
}

struct ExtensionActionSlotSnapshot: Identifiable {
    let id: String
    let kind: ExtensionActionSlotSnapshotKind
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
    let pinnedItems: [SpacePinnedItemSnapshot]
    let regularItems: [SpaceTabRowSnapshot]
    let regularTabs: [SpaceTabRowSnapshot]
    let showsNewTabButtonInList: Bool
    let showsTopNewTabButton: Bool
    let rowCornerRadius: CGFloat
    let pinnedTabsConfiguration: PinnedTabsConfiguration
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
}

@MainActor
enum SpaceSidebarTransitionSnapshotBuilder {
    static func make(
        sourceSpace: Space,
        destinationSpace: Space,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState,
        settings: SumiSettingsService
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
            windowState: windowState,
            settings: settings
        )
        let destinationPage = pageSnapshot(
            for: destinationSpace,
            profileId: destinationProfileId,
            browserContext: browserContext,
            windowState: windowState,
            settings: settings
        )
        let stationaryEssentials = sharedEssentials && !windowState.isIncognito
            ? essentialsSnapshot(
                profileId: sourceProfileId,
                browserContext: browserContext,
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
        windowState: BrowserWindowState,
        settings: SumiSettingsService
    ) -> SpaceSidebarPageSnapshot {
        let projection = windowState.isIncognito
            ? nil
            : browserContext.tabManager.launcherProjection(for: space.id, in: windowState.id)
        let tabs = windowState.isIncognito
            ? windowState.ephemeralTabs.sorted { $0.index < $1.index }
            : (projection?.regularTabs ?? browserContext.tabManager.tabs(in: space))
        let regularTabs = tabs.map { tabSnapshot($0, currentTabId: windowState.currentTabId) }

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
                    browserContext: browserContext,
                    windowState: windowState
                ),
            pinnedItems: pinnedItemsSnapshot(
                projection: projection,
                browserContext: browserContext,
                windowState: windowState,
            ),
            regularItems: regularTabs,
            regularTabs: regularTabs,
            showsNewTabButtonInList: settings.showNewTabButtonInTabList,
            showsTopNewTabButton: settings.tabListNewTabButtonPosition == .top,
            rowCornerRadius: settings.resolvedCornerRadius(12),
            pinnedTabsConfiguration: .large
        )
    }

    private static func extensionActionsSnapshot(
        profileId: UUID?,
        browserContext: SidebarBrowserContext
    ) -> ExtensionActionGridSnapshot? {
        let surfaceStore = browserContext.extensionSurfaceStore
        let slots = browserContext.extensionToolbarSlots(surfaceStore.enabledExtensions, profileId)
        guard ExtensionActionPlacement.resolve(totalActions: slots.count) == .sidebarGrid else {
            return nil
        }

        let snapshots = slots.map { slot -> ExtensionActionSlotSnapshot in
            switch slot {
            case .sumiScriptsManager:
                return ExtensionActionSlotSnapshot(
                    id: SumiScriptsToolbarConstants.nativeToolbarItemID,
                    kind: .sumiScriptsManager,
                    icon: nil,
                    badgeText: nil,
                    hasUnreadBadgeText: false
                )
            case .webExtension(let ext):
                let actionState = surfaceStore.actionStatesByExtensionID[ext.id]
                let icon = actionState?.icon ?? extensionIcon(for: ext)
                let badgeText = actionState?.badgeText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return ExtensionActionSlotSnapshot(
                    id: ext.id,
                    kind: .webExtension,
                    icon: icon,
                    badgeText: badgeText?.isEmpty == false ? badgeText : nil,
                    hasUnreadBadgeText: actionState?.hasUnreadBadgeText == true
                )
            }
        }

        return ExtensionActionGridSnapshot(slots: snapshots)
    }

    private static func extensionIcon(for extensionRecord: InstalledExtension) -> NSImage? {
        guard let iconPath = extensionRecord.iconPath else { return nil }
        return ExtensionIconCache.shared.image(
            extensionId: extensionRecord.id,
            iconPath: iconPath
        )
    }

    private static func resolvedProfileId(
        for space: Space?,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> UUID? {
        space?.profileId ?? windowState.currentProfileId ?? browserContext.currentProfile()?.id
    }

    private static func essentialsSnapshot(
        profileId: UUID?,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> EssentialsSnapshot {
        EssentialsSnapshot(
            items: profileId == nil
                ? []
                : browserContext.tabManager.essentialPins(for: profileId).map {
                    shortcutSnapshot(
                        for: $0,
                        liveTab: browserContext.tabManager.shortcutLiveTab(for: $0.id, in: windowState.id),
                        browserContext: browserContext,
                        windowState: windowState
                    )
                }
        )
    }

    private static func pinnedItemsSnapshot(
        projection: TabManager.SpaceLauncherProjection?,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> [SpacePinnedItemSnapshot] {
        guard let projection else { return [] }

        return (
            projection.topLevelFolders.map { folder in
                (
                    folder.index,
                    SpacePinnedItemSnapshot.folder(
                        folderSnapshot(
                            for: folder,
                            childFoldersByParentId: projection.childFolders,
                            folderPinsByFolderId: projection.folderPins,
                            liveTabsByPinId: projection.liveTabsByPinId,
                            browserContext: browserContext,
                            windowState: windowState,
                            visitedFolderIds: []
                        )
                    )
                )
            }
            + projection.topLevelPins.map { pin in
                (
                    pin.index,
                    SpacePinnedItemSnapshot.shortcut(
                        shortcutSnapshot(
                            for: pin,
                            liveTab: projection.liveTabsByPinId[pin.id],
                            browserContext: browserContext,
                            windowState: windowState
                        )
                    )
                )
            }
        )
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            switch (lhs.1, rhs.1) {
            case (.folder(let left), .folder(let right)):
                return left.id.uuidString < right.id.uuidString
            case (.shortcut(let left), .shortcut(let right)):
                return left.id.uuidString < right.id.uuidString
            case (.folder, .shortcut):
                return true
            case (.shortcut, .folder):
                return false
            }
        }
        .map(\.1)
    }

    private static func doesFolderContainActiveSelection(
        folderId: UUID,
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        windowState: BrowserWindowState
    ) -> Bool {
        if let currentShortcutPinId = windowState.currentShortcutPinId {
            if doesFolderContainPin(folderId: folderId, pinId: currentShortcutPinId, childFoldersByParentId: childFoldersByParentId, folderPinsByFolderId: folderPinsByFolderId) {
                return true
            }
        }
        if let currentTabId = windowState.currentTabId {
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
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState,
        visitedFolderIds: Set<UUID>
    ) -> SpaceFolderSnapshot {
        var nextVisited = visitedFolderIds
        nextVisited.insert(folder.id)
        let directChildFolders = (childFoldersByParentId[folder.id] ?? [])
            .filter { nextVisited.contains($0.id) == false }
        let directShortcutPins = folderPinsByFolderId[folder.id] ?? []

        let projectionState = windowState.sidebarFolderProjection(for: folder.id)

        let childSnapshots: [SpacePinnedItemSnapshot]
        let hasActiveSelection: Bool

        if folder.isOpen || projectionState.hasActiveProjection {
            childSnapshots = folderBodyChildSnapshots(
                childFolders: directChildFolders,
                shortcutPins: directShortcutPins,
                childFoldersByParentId: childFoldersByParentId,
                folderPinsByFolderId: folderPinsByFolderId,
                liveTabsByPinId: liveTabsByPinId,
                browserContext: browserContext,
                windowState: windowState,
                visitedFolderIds: nextVisited
            )
            hasActiveSelection = projectionState.hasActiveProjection || childSnapshots.containsActiveSelection
        } else {
            let livePins = directShortcutPins.filter { liveTabsByPinId[$0.id] != nil }
            childSnapshots = livePins.map { pin in
                SpacePinnedItemSnapshot.shortcut(
                    shortcutSnapshot(
                        for: pin,
                        liveTab: liveTabsByPinId[pin.id],
                        browserContext: browserContext,
                        windowState: windowState
                    )
                )
            }
            hasActiveSelection = projectionState.hasActiveProjection || doesFolderContainActiveSelection(
                folderId: folder.id,
                childFoldersByParentId: childFoldersByParentId,
                folderPinsByFolderId: folderPinsByFolderId,
                liveTabsByPinId: liveTabsByPinId,
                windowState: windowState
            )
        }

        let childSnapshotsById = Dictionary(
            childSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let collapsedProjectedChildSnapshots = collapsedProjectedShortcutPins(
            directShortcutPins,
            liveTabsByPinId: liveTabsByPinId,
            projectionState: projectionState
        ).compactMap { childSnapshotsById[$0.id] }
        let bodyChildren = folder.isOpen ? childSnapshots : collapsedProjectedChildSnapshots

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
        childFolders: [TabFolder],
        shortcutPins: [ShortcutPin],
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState,
        visitedFolderIds: Set<UUID>
    ) -> [SpacePinnedItemSnapshot] {
        (
            childFolders.map { childFolder in
                (
                    childFolder.index,
                    0,
                    SpacePinnedItemSnapshot.folder(
                        folderSnapshot(
                            for: childFolder,
                            childFoldersByParentId: childFoldersByParentId,
                            folderPinsByFolderId: folderPinsByFolderId,
                            liveTabsByPinId: liveTabsByPinId,
                            browserContext: browserContext,
                            windowState: windowState,
                            visitedFolderIds: visitedFolderIds
                        )
                    )
                )
            }
            + shortcutPins.map { pin in
                (
                    pin.index,
                    1,
                    SpacePinnedItemSnapshot.shortcut(
                        shortcutSnapshot(
                            for: pin,
                            liveTab: liveTabsByPinId[pin.id],
                            browserContext: browserContext,
                            windowState: windowState
                        )
                    )
                )
            }
        )
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2.id.uuidString < rhs.2.id.uuidString
        }
        .map(\.2)
    }

    private static func collapsedProjectedShortcutPins(
        _ children: [ShortcutPin],
        liveTabsByPinId: [UUID: Tab],
        projectionState: SidebarFolderProjectionState
    ) -> [ShortcutPin] {
        let livePins = children.filter { liveTabsByPinId[$0.id] != nil }

        guard !projectionState.projectedChildIDs.isEmpty else {
            return livePins
        }

        let projectedOrder = Dictionary(
            projectionState.projectedChildIDs.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return livePins.sorted { lhs, rhs in
            let leftOrder = projectedOrder[lhs.id] ?? lhs.index
            let rightOrder = projectedOrder[rhs.id] ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func shortcutSnapshot(
        for pin: ShortcutPin,
        liveTab: Tab?,
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> SpaceShortcutSnapshot {
        let presentationState = browserContext.tabManager.shortcutPresentationState(
            for: pin,
            in: windowState
        )
        let isInVisibleSplit = liveTab.map { browserContext.splitManager.isTabVisibleInSplit($0.id, in: windowState.id) } == true
        let essentialRuntimeState = browserContext.tabManager.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitManager: browserContext.splitManager
        )
        let isSplitPlaceholder = browserContext.tabManager.splitGroup(containingPinId: pin.id) != nil

        return SpaceShortcutSnapshot(
            id: pin.id,
            title: pin.resolvedDisplayTitle(liveTab: liveTab),
            icon: shortcutIcon(
                for: pin,
                liveTab: liveTab,
                browserContext: browserContext,
                windowState: windowState
            ),
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
        browserContext: SidebarBrowserContext,
        windowState: BrowserWindowState
    ) -> SpaceSidebarSnapshotIcon {
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return .emoji(iconAsset)
            }
            return .system(SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
        }

        let faviconPartition = browserContext.tabManager.resolvedFaviconPartition(
            for: pin,
            currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
        )

        if let liveTab {
            if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
                return .system(SumiSurface.settingsTabFaviconSystemImageName)
            }

            if let cachedFavicon = ShortcutPin.cachedLaunchFavicon(
                for: pin.launchURL,
                partition: faviconPartition
            ) {
                return .image(cachedFavicon)
            }

            if !liveTab.faviconIsTemplateGlobePlaceholder {
                return .image(liveTab.favicon)
            }

            return .system(SumiPersistentGlyph.launcherSystemImageFallback)
        }

        if let systemName = pin.storedChromeTemplateSystemImageName(for: faviconPartition) {
            return .system(systemName)
        }

        return .image(pin.storedFaviconImage(partition: faviconPartition))
    }
}
