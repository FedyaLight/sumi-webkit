//
//  SpacesSideBarView.swift
//  Sumi
//
//

import SwiftUI

enum SidebarPageRenderMode: Equatable {
    case interactive
    case transitionSnapshot

    var spaceRenderMode: SpaceViewRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }

    var animatesEssentialsLayout: Bool {
        self == .interactive
    }
}

private extension SidebarPageRenderMode {
    var geometryRenderMode: SidebarPageGeometryRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }
}

enum SpaceSidebarRenderPolicy {
    static let completionDelay = SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration

    static func pageRenderMode(for role: Role) -> SidebarPageRenderMode {
        switch role {
        case .committed:
            return .interactive
        case .transitionLayer:
            return .transitionSnapshot
        }
    }

    static func shouldUseTransitionLayers(for state: SpaceSidebarTransitionState) -> Bool {
        state.hasDestination
    }

    static func shouldBeginSwipeTransition(for event: SpaceSwipeGestureEvent) -> Bool {
        event.phase == .changed && event.direction != nil
    }

    enum Role {
        case committed
        case transitionLayer
    }
}

@MainActor
enum SpaceSidebarChromePreviewPolicy {
    static func shouldAnimateEssentialsLayout(
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode
    ) -> Bool {
        isActiveWindow
            && !isTransitioningProfile
            && pageRenderMode.animatesEssentialsLayout
    }
}

enum SpaceSidebarEssentialsPlacementPolicy {
    static func usesSharedPinnedGrid(
        sourceProfileId: UUID?,
        destinationProfileId: UUID?
    ) -> Bool {
        sourceProfileId == destinationProfileId
    }
}

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
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager,
        settings: SumiSettingsService
    ) -> SpaceSidebarTransitionSnapshot {
        let sourceProfileId = resolvedProfileId(
            for: sourceSpace,
            browserManager: browserManager,
            windowState: windowState
        )
        let destinationProfileId = resolvedProfileId(
            for: destinationSpace,
            browserManager: browserManager,
            windowState: windowState
        )
        let sharedEssentials = SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
            sourceProfileId: sourceProfileId,
            destinationProfileId: destinationProfileId
        )

        let sourcePage = pageSnapshot(
            for: sourceSpace,
            profileId: sourceProfileId,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager,
            settings: settings
        )
        let destinationPage = pageSnapshot(
            for: destinationSpace,
            profileId: destinationProfileId,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager,
            settings: settings
        )
        let stationaryEssentials = sharedEssentials && !windowState.isIncognito
            ? essentialsSnapshot(
                profileId: sourceProfileId,
                browserManager: browserManager,
                windowState: windowState,
                splitManager: splitManager
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
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager,
        settings: SumiSettingsService
    ) -> SpaceSidebarPageSnapshot {
        let projection = windowState.isIncognito
            ? nil
            : browserManager.tabManager.launcherProjection(for: space.id, in: windowState.id)
        let tabs = windowState.isIncognito
            ? windowState.ephemeralTabs.sorted { $0.index < $1.index }
            : (projection?.regularTabs ?? browserManager.tabManager.tabs(in: space))
        let regularTabs = tabs.map { tabSnapshot($0, currentTabId: windowState.currentTabId) }

        return SpaceSidebarPageSnapshot(
            spaceId: space.id,
            title: space.name,
            iconValue: space.icon,
            extensionActions: windowState.isIncognito
                ? nil
                : extensionActionsSnapshot(
                    profileId: profileId,
                    browserManager: browserManager
                ),
            essentials: windowState.isIncognito
                ? nil
                : essentialsSnapshot(
                    profileId: profileId,
                    browserManager: browserManager,
                    windowState: windowState,
                    splitManager: splitManager
                ),
            pinnedItems: pinnedItemsSnapshot(
                projection: projection,
                browserManager: browserManager,
                windowState: windowState,
                splitManager: splitManager
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
        browserManager: BrowserManager
    ) -> ExtensionActionGridSnapshot? {
        let surfaceStore = browserManager.extensionsModule.surfaceStore
        let slots = browserManager.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: surfaceStore.enabledExtensions,
            sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled,
            profileId: profileId
        )
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
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> UUID? {
        space?.profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
    }

    private static func essentialsSnapshot(
        profileId: UUID?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager
    ) -> EssentialsSnapshot {
        EssentialsSnapshot(
            items: profileId == nil
                ? []
                : browserManager.tabManager.essentialPins(for: profileId).map {
                    shortcutSnapshot(
                        for: $0,
                        liveTab: browserManager.tabManager.shortcutLiveTab(for: $0.id, in: windowState.id),
                        browserManager: browserManager,
                        windowState: windowState,
                        splitManager: splitManager
                    )
                }
        )
    }

    private static func pinnedItemsSnapshot(
        projection: TabManager.SpaceLauncherProjection?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager
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
                            browserManager: browserManager,
                            windowState: windowState,
                            splitManager: splitManager,
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
                            browserManager: browserManager,
                            windowState: windowState,
                            splitManager: splitManager
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

    private static func folderSnapshot(
        for folder: TabFolder,
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager,
        visitedFolderIds: Set<UUID>
    ) -> SpaceFolderSnapshot {
        var nextVisited = visitedFolderIds
        nextVisited.insert(folder.id)
        let directChildFolders = (childFoldersByParentId[folder.id] ?? [])
            .filter { nextVisited.contains($0.id) == false }
        let directShortcutPins = folderPinsByFolderId[folder.id] ?? []
        let childSnapshots = folderBodyChildSnapshots(
            childFolders: directChildFolders,
            shortcutPins: directShortcutPins,
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            liveTabsByPinId: liveTabsByPinId,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager,
            visitedFolderIds: nextVisited
        )
        let childSnapshotsById = Dictionary(
            childSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let projectionState = windowState.sidebarFolderProjection(for: folder.id)
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
            hasActiveSelection: projectionState.hasActiveProjection
                || childSnapshots.containsActiveSelection
                || (!folder.isOpen && !bodyChildren.isEmpty),
            bodyChildren: bodyChildren
        )
    }

    private static func folderBodyChildSnapshots(
        childFolders: [TabFolder],
        shortcutPins: [ShortcutPin],
        childFoldersByParentId: [UUID: [TabFolder]],
        folderPinsByFolderId: [UUID: [ShortcutPin]],
        liveTabsByPinId: [UUID: Tab],
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager,
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
                            browserManager: browserManager,
                            windowState: windowState,
                            splitManager: splitManager,
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
                            browserManager: browserManager,
                            windowState: windowState,
                            splitManager: splitManager
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
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        splitManager: SplitViewManager
    ) -> SpaceShortcutSnapshot {
        let presentationState = browserManager.tabManager.shortcutPresentationState(
            for: pin,
            in: windowState
        )
        let isInVisibleSplit = liveTab.map { splitManager.isTabVisibleInSplit($0.id, in: windowState.id) } == true
        let essentialRuntimeState = browserManager.tabManager.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitManager: splitManager
        )
        let isSplitPlaceholder = browserManager.tabManager.splitGroup(containingPinId: pin.id) != nil

        return SpaceShortcutSnapshot(
            id: pin.id,
            title: pin.resolvedDisplayTitle(liveTab: liveTab),
            icon: shortcutIcon(
                for: pin,
                liveTab: liveTab,
                browserManager: browserManager,
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
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> SpaceSidebarSnapshotIcon {
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return .emoji(iconAsset)
            }
            return .system(SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
        }

        let faviconPartition = browserManager.tabManager.resolvedFaviconPartition(
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

private struct SpaceTransitionSnapshotPageView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let includesEssentials: Bool
    let width: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    private var innerWidth: CGFloat {
        max(width - BrowserWindowState.sidebarHorizontalPadding, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            if includesEssentials, let extensionActions = snapshot.extensionActions {
                ExtensionActionSnapshotGrid(
                    snapshot: extensionActions,
                    tokens: tokens
                )
                .padding(.horizontal, 8)
            }

            if includesEssentials, let essentials = snapshot.essentials {
                EssentialsSnapshotGrid(
                    snapshot: essentials,
                    width: innerWidth,
                    configuration: snapshot.pinnedTabsConfiguration,
                    tokens: tokens
                )
                .padding(.horizontal, 8)
            }

            VStack(spacing: 4) {
                SpaceSnapshotTitleView(
                    title: snapshot.title,
                    iconValue: snapshot.iconValue,
                    rowCornerRadius: snapshot.rowCornerRadius,
                    tokens: tokens
                )

                SpaceSnapshotContentView(
                    snapshot: snapshot,
                    innerWidth: innerWidth,
                    tokens: tokens,
                    themeContext: themeContext
                )
            }
            .padding(.horizontal, 8)
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
}

private struct ExtensionActionSnapshotGrid: View {
    let snapshot: ExtensionActionGridSnapshot
    let tokens: ChromeThemeTokens

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 32, maximum: .infinity),
                spacing: 8,
                alignment: .center
            ),
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(snapshot.slots) { slot in
                ExtensionActionSnapshotButton(slot: slot, tokens: tokens)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("sidebar-extension-action-grid-snapshot")
    }
}

private struct ExtensionActionSnapshotButton: View {
    let slot: ExtensionActionSlotSnapshot
    let tokens: ChromeThemeTokens

    var body: some View {
        iconView
            .frame(width: 16, height: 16)
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(tokens.pinnedIdleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let badgeText = slot.badgeText {
                    Text(badgeText)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 10, minHeight: 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(slot.hasUnreadBadgeText ? 0.95 : 0.78))
                        )
                        .padding(2)
                }
            }
    }

    @ViewBuilder
    private var iconView: some View {
        switch slot.kind {
        case .sumiScriptsManager:
            Image(systemName: "curlybraces.square")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
        case .webExtension:
            if let icon = slot.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
            }
        }
    }
}

private struct SpaceSnapshotContentView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        SpaceSnapshotPinnedSectionView(
                            items: snapshot.pinnedItems,
                            rowCornerRadius: snapshot.rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )

                        SpaceSnapshotRegularTabsSectionView(
                            snapshot: snapshot,
                            innerWidth: innerWidth,
                            tokens: tokens
                        )
                    }
                    .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("space-transition-snapshot-scroll-\(snapshot.spaceId.uuidString)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SpaceSnapshotTitleView: View {
    let title: String
    let iconValue: String
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    private var spaceIconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * 0.78
    }

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            Group {
                if SumiPersistentGlyph.presentsAsEmoji(iconValue) {
                    Text(iconValue)
                        .font(.system(size: spaceIconFontSize))
                } else {
                    Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(iconValue))
                        .font(.system(size: spaceIconFontSize, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                }
            }
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(
                    width: SpaceSidebarSnapshotTitleLayout.trailingControlSize,
                    height: SpaceSidebarSnapshotTitleLayout.trailingControlSize
                )
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.vertical, SpaceSidebarSnapshotTitleLayout.verticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: SpaceSidebarSnapshotTitleLayout.minimumHeight)
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .accessibilityIdentifier("space-transition-snapshot-title")
    }
}

private struct EssentialsSnapshotGrid: View {
    let snapshot: EssentialsSnapshot
    let width: CGFloat
    let configuration: PinnedTabsConfiguration
    let tokens: ChromeThemeTokens

    private var rows: [EssentialsSnapshotRow] {
        let columns = capacityColumnCount
        guard !snapshot.items.isEmpty else { return [] }

        return stride(from: 0, to: snapshot.items.count, by: columns).map { index in
            let rowItems = Array(snapshot.items[index..<min(index + columns, snapshot.items.count)])
            let visualColumnCount = max(1, min(rowItems.count, columns))
            let tileSize = visualTileSize(visualColumnCount: visualColumnCount)
            return EssentialsSnapshotRow(items: rowItems, tileSize: tileSize)
        }
    }

    private var capacityColumnCount: Int {
        guard width > 0 else { return 1 }

        var columns = SidebarEssentialsProjectionPolicy.maxColumns
        while columns > 1 {
            let neededWidth = CGFloat(columns) * configuration.minWidth
                + CGFloat(columns - 1) * configuration.gridSpacing
            if neededWidth <= width {
                break
            }
            columns -= 1
        }
        return max(1, columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: configuration.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: configuration.gridSpacing) {
                    ForEach(row.items) { item in
                        SpaceSnapshotPinnedTileView(
                            item: item,
                            tileSize: row.tileSize,
                            configuration: configuration,
                            tokens: tokens
                        )
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(height: rows.isEmpty ? 6 : nil, alignment: .top)
    }

    private func visualTileSize(visualColumnCount: Int) -> CGSize {
        let columns = max(visualColumnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * configuration.gridSpacing), 0)
        let tileWidth = max(availableWidth / CGFloat(columns), configuration.minWidth)
        return CGSize(width: tileWidth, height: configuration.height)
    }

    private struct EssentialsSnapshotRow {
        let items: [SpaceShortcutSnapshot]
        let tileSize: CGSize
    }
}

private struct SpaceSnapshotPinnedSectionView: View {
    let items: [SpacePinnedItemSnapshot]
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        Group {
            if items.isEmpty {
                Color.clear
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: SidebarInsertionGuide.visualCenterY)

                    ForEach(items) { item in
                        SpaceSnapshotPinnedItemView(
                            item: item,
                            rowCornerRadius: rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SpaceSnapshotPinnedItemView: View {
    let item: SpacePinnedItemSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        switch item {
        case .folder(let folder):
            SpaceSnapshotFolderView(
                folder: folder,
                rowCornerRadius: rowCornerRadius,
                tokens: tokens,
                themeContext: themeContext
            )
        case .shortcut(let shortcut):
            SpaceSnapshotShortcutRowView(
                shortcut: shortcut,
                rowCornerRadius: rowCornerRadius,
                tokens: tokens
            )
        }
    }
}

private struct SpaceSnapshotFolderView: View {
    let folder: SpaceFolderSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    private var showsBody: Bool {
        folder.isOpen || !folder.bodyChildren.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
                    SumiFolderGlyphView(
                        presentation: SumiFolderGlyphPresentationState(
                            iconValue: folder.iconValue,
                            isOpen: folder.isOpen,
                            hasActiveProjection: folder.hasActiveSelection
                        ),
                        palette: folderPalette
                    )
                    .frame(
                        width: SidebarRowLayout.folderGlyphSize,
                        height: SidebarRowLayout.folderGlyphSize,
                        alignment: .center
                    )
                    .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
                }
                .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)

                Text(folder.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))

            if showsBody {
                VStack(spacing: 0) {
                    ForEach(folder.bodyChildren) { child in
                        SpaceSnapshotPinnedItemView(
                            item: child,
                            rowCornerRadius: rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )
                    }
                }
                .padding(.leading, SpaceSidebarSnapshotFolderLayout.contentLeadingPadding)
                .padding(.vertical, SpaceSidebarSnapshotFolderLayout.contentVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(tokens.separator.opacity(0.55))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                        .offset(x: 6)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var folderPalette: SumiFolderGlyphPalette {
        let accent = themeContext.gradient.primaryColor

        let backFill: Color
        let frontFill: Color
        let stroke: Color

        switch themeContext.chromeColorScheme {
        case .light:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        case .dark:
            backFill = accent.mixed(with: Color(hex: "C1C1C1"), amount: 0.4)
            frontFill = accent.mixed(with: .black, amount: 0.4)
            stroke = Color(hex: "EBEBEB").mixed(with: tokens.primaryText, amount: 0.15)
        @unknown default:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        }

        let iconForeground = stroke.mixed(with: tokens.primaryText, amount: 0.35)

        return SumiFolderGlyphPalette(
            backFill: backFill,
            frontFill: frontFill,
            stroke: stroke,
            iconForeground: iconForeground,
            backOverlayTop: Color.white.opacity(0.1),
            backOverlayBottom: Color.black.opacity(0.1),
            frontOverlayTop: Color.white.opacity(0.1),
            frontOverlayBottom: Color.black.opacity(0.1)
        )
    }
}

private struct SpaceSnapshotShortcutRowView: View {
    let shortcut: SpaceShortcutSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: 0) {
            SpaceSnapshotIconView(
                icon: shortcut.icon,
                size: SidebarRowLayout.faviconSize,
                foregroundColor: tokens.primaryText
            )
            .saturation(shortcut.presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
            .opacity(shortcut.presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

            if shortcut.showsAudioButton {
                Image(systemName: shortcut.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(shortcut.isMuted ? tokens.secondaryText : tokens.primaryText)
                    .frame(width: 22, height: 22)
                    .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
            }

            SpaceSnapshotFadingTitleLabel(
                title: shortcut.title,
                font: .system(size: 13, weight: .medium),
                color: tokens.primaryText
            )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowSurface(
            background: shortcut.presentationState.isSelected ? tokens.sidebarRowActive : .clear,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: shortcut.presentationState.isSelected,
            drawsSelectionShadow: shortcut.presentationState.isSelected
        )
    }
}

private struct SpaceSnapshotRegularTabsSectionView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens

    private var showsBottomNewTabButton: Bool {
        snapshot.showsNewTabButtonInList && !snapshot.showsTopNewTabButton
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 100)
                .fill(tokens.separator.opacity(0.82))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .frame(height: 2)

            VStack(spacing: 2) {
                if snapshot.showsNewTabButtonInList && snapshot.showsTopNewTabButton {
                    newTabRow
                        .padding(.top, 4)
                }

                VStack(spacing: 2) {
                    ForEach(snapshot.regularItems) { tab in
                        SpaceSnapshotRegularTabRowView(
                            tab: tab,
                            rowCornerRadius: snapshot.rowCornerRadius,
                            tokens: tokens
                        )
                    }
                }
                .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)

                if showsBottomNewTabButton {
                    newTabRow
                }
            }
            .padding(.top, 8)

            Color.clear
                .frame(height: snapshot.regularTabs.isEmpty ? 48 : 24)
        }
    }

    private var newTabRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
            Text("New Tab")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(tokens.primaryText)
        .padding(.horizontal, 10)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SpaceSnapshotRegularTabRowView: View {
    let tab: SpaceTabRowSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            favicon

            if tab.showsAudioButton {
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tab.isMuted ? tokens.secondaryText : tokens.primaryText)
                    .frame(width: 22, height: 22)
            }

            SpaceSnapshotFadingTitleLabel(
                title: tab.title,
                font: .system(size: 13, weight: .medium),
                color: tokens.primaryText
            )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowSurface(
            background: tab.isSelected ? tokens.sidebarRowActive : .clear,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: tab.isSelected,
            drawsSelectionShadow: tab.isSelected
        )
    }

    @ViewBuilder
    private var favicon: some View {
        if tab.showsUnloadedIndicator {
            SidebarUnloadedRegularTabFaviconIndicator(
                size: SidebarRowLayout.faviconSize
            ) {
                SpaceSnapshotIconView(
                    icon: tab.icon,
                    size: SidebarRowLayout.faviconSize,
                    foregroundColor: tokens.primaryText
                )
            }
        } else {
            SpaceSnapshotIconView(
                icon: tab.icon,
                size: SidebarRowLayout.faviconSize,
                foregroundColor: tokens.primaryText
            )
        }
    }
}

private struct SpaceSnapshotFadingTitleLabel: View {
    let title: String
    let font: Font
    let color: Color
    var fadeWidth: CGFloat = 32
    var trailingFadePadding: CGFloat = 0
    var height: CGFloat = SidebarRowLayout.titleHeight

    var body: some View {
        GeometryReader { proxy in
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .allowsTightening(false)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipped()
                .mask(
                    SpaceSnapshotTrailingFadeMask(
                        fadeWidth: fadeWidth,
                        trailingPadding: trailingFadePadding
                    )
                )
        }
        .frame(height: height, alignment: .center)
        .accessibilityLabel(title)
    }
}

private struct SpaceSnapshotTrailingFadeMask: View {
    let fadeWidth: CGFloat
    let trailingPadding: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let availableWidth = max(width - trailingPadding, 0)
            let safeFadeWidth = min(fadeWidth, availableWidth)
            let start = width > 0
                ? (width - (trailingPadding + safeFadeWidth)) / width
                : 1
            let end = width > 0
                ? (width - trailingPadding) / width
                : 1

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: max(0, min(start, 1))),
                    .init(color: .clear, location: max(0, min(end, 1))),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct SpaceSnapshotIconView: View {
    let icon: SpaceSidebarSnapshotIcon
    let size: CGFloat
    let foregroundColor: Color

    var body: some View {
        Group {
            switch icon {
            case .image(let image):
                image
            case .system(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: size * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: size * 0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SidebarPageInputGraphIdentity: Hashable {
    let spaceId: UUID
    let profileId: UUID?
    let recoveryGeneration: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spaceId == rhs.spaceId
            && lhs.profileId == rhs.profileId
            && lhs.recoveryGeneration == rhs.recoveryGeneration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(profileId)
        hasher.combine(recoveryGeneration)
    }
}

struct SpacesSideBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @State private var isSidebarHovered: Bool = false
    @State private var transitionState = SpaceSidebarTransitionState()
    @State private var transitionSnapshot: SpaceSidebarTransitionSnapshot?
    @State private var transitionTask: Task<Void, Never>?
    @ObservedObject private var dragState = SidebarDragState.shared
    @ObservedObject private var nowPlayingController = SumiNativeNowPlayingController.shared
    @ObservedObject private var updaterService = SumiUpdaterService.shared

    private var shouldMountMiniPlayer: Bool {
        guard sumiSettings.sidebarMiniPlayerEnabled else { return false }
        return SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
            globalState: nowPlayingController.cardState,
            in: windowState
        )
    }

    var body: some View {
        sidebarContent
            .contentShape(Rectangle())
            .onDisappear {
                cancelLocalSpaceTransitionIfNeeded(cancelTheme: true)
            }
            .onHover { state in
                isSidebarHovered = allowsSidebarInteractiveWork ? state : false
            }
            .onChange(of: allowsSidebarInteractiveWork) { _, allowsInteractiveWork in
                if !allowsInteractiveWork {
                    isSidebarHovered = false
                }
            }
    }

    // MARK: - Main Content

    private var sidebarContent: some View {
        mainSidebarContent
            .overlay {
                ZStack {
                    SidebarGlobalDragOverlay()
                        .allowsHitTesting(allowsSidebarInteractiveWork)
                }
            }
    }

    private var mainSidebarContent: some View {
        _ = browserManager.tabStructuralRevision
        let spaces = availableSpaces
        let visualSpaceId = visualSelectedSpaceId(in: spaces)

        return VStack(spacing: 8) {
            SidebarHeader()
                .environmentObject(browserManager)
                .environment(windowState)

            if let creationSession = windowState.activeSpaceCreationSession {
                SidebarSpaceCreationView(
                    session: creationSession,
                    onCreate: { commitSpaceCreationSession(creationSession) },
                    onCancel: { cancelSpaceCreationSession(creationSession) }
                )
                .environmentObject(browserManager)
                .environment(windowState)
                .transition(spaceCreationTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                spacesPageView(spaces: spaces)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 8) {
                    if let notice = updaterService.sidebarNotice {
                        sidebarUpdateNotice(notice)
                    }

                    if shouldMountMiniPlayer {
                        MediaControlsView()
                            .environmentObject(browserManager)
                            .environment(windowState)
                    }

                    SidebarBottomBar(
                        visualSelectedSpaceId: visualSpaceId,
                        onNewSpaceTap: beginSpaceCreationMode,
                        onSelectSpace: { switchSpace(to: $0, spaces: spaces) }
                    )
                    .environmentObject(browserManager)
                    .environment(windowState)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.top, SidebarChromeMetrics.topControlInset)
        .environment(sidebarInteractionState)
        .sidebarAppKitBackgroundContextMenu(
            controller: windowState.sidebarContextMenuController,
            entries: { sidebarContextMenuEntries() },
            onMenuVisibilityChanged: handleSidebarContextMenuVisibility
        )
        .onChange(of: dragState.isDragging) { _, isDragging in
            Task { @MainActor in
                sidebarInteractionState.syncSidebarItemDrag(isDragging)
            }
        }
        .onAppear {
            handlePendingSplitGroupFocusRequest(
                windowState.pendingSplitGroupFocusRequest,
                spaces: spaces
            )
        }
        .onChange(of: windowState.pendingSplitGroupFocusRequest) { _, request in
            handlePendingSplitGroupFocusRequest(request, spaces: spaces)
        }
    }

    @ViewBuilder
    private func sidebarUpdateNotice(_ notice: SumiUpdateSidebarNotice) -> some View {
        if sidebarPresentationContext.inputMode == .collapsedOverlay {
            HStack {
                Spacer(minLength: 0)
                SumiUpdateSidebarCompactIndicator(
                    notice: notice,
                    onUpdate: { updaterService.startUpdateFromSidebarNotice() }
                )
                .disabled(notice.primaryActionTitle == nil)
            }
            .padding(.horizontal, 8)
        } else {
            SumiUpdateSidebarNoticeView(
                notice: notice,
                onUpdate: { updaterService.startUpdateFromSidebarNotice() },
                onDismiss: { updaterService.dismissSidebarNotice(notice) }
            )
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Spaces Page View

    private func spacesPageView(spaces: [Space]) -> some View {
        Group {
            if spaces.isEmpty {
                emptyStateView
            } else {
                GeometryReader { geo in
                    spaceTransitionContainer(spaces: spaces, size: geo.size)
                        .modifier(
                            SpaceTransitionProgressObserver(progress: transitionState.progress) { progress in
                                handleTransitionProgressFrame(progress, spaces: spaces)
                            }
                        )
                        .overlay {
                            SidebarSwipeCaptureSurface(
                                isEnabled: allowsSidebarInteractiveWork
                                    && spaces.count > 1
                                    && (transitionState.phase == .idle || transitionState.phase == .interactive)
                                    && sidebarInteractionState.allowsSidebarSwipeCapture
                            ) { event in
                                handleSwipeEvent(event, spaces: spaces)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                }
                .clipped()
                .onAppear {
                    handleSpacesCollectionChange(spaces)
                    refreshCommittedSidebarDragGeometryIfInteractive(spaces: spaces)
                }
                .onChange(of: spaces.map(\.id)) { _, _ in
                    handleSpacesCollectionChange(spaces)
                    refreshCommittedSidebarDragGeometryIfInteractive(spaces: spaces)
                }
                .onChange(of: committedSpaceId(in: spaces)) { _, _ in
                    refreshCommittedSidebarDragGeometryIfInteractive(spaces: spaces)
                }
                .onChange(of: allowsSidebarInteractiveWork) { _, allowsInteractiveWork in
                    if allowsInteractiveWork {
                        refreshCommittedSidebarDragGeometry(spaces: spaces)
                    }
                }
            }
        }
    }

    private var availableSpaces: [Space] {
        windowState.isIncognito
            ? windowState.ephemeralSpaces
            : browserManager.tabManager.spaces
    }

    private var sidebarInteractionState: SidebarInteractionState {
        windowState.sidebarInteractionState
    }

    private var allowsSidebarInteractiveWork: Bool {
        sidebarPresentationContext.allowsInteractiveWork
    }

    @ViewBuilder
    private func spaceTransitionContainer(
        spaces: [Space],
        size: CGSize
    ) -> some View {
        let width = max(size.width, 1)
        let travelProgress = transitionState.progress

        ZStack(alignment: .topLeading) {
            if SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: transitionState),
               let sourceSpace = space(for: transitionState.sourceSpaceId, in: spaces),
               let destinationSpace = space(for: transitionState.destinationSpaceId, in: spaces)
            {
                if usesSharedPinnedGrid(
                    sourceSpace: sourceSpace,
                    destinationSpace: destinationSpace
                ) {
                    sameProfileTransitionContainer(
                        sourceSpace: sourceSpace,
                        destinationSpace: destinationSpace,
                        width: width,
                        travelProgress: travelProgress
                    )
                } else {
                    transitionLayer(
                        for: sourceSpace,
                        pageRenderMode: SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer),
                        width: width,
                        offsetX: sourceOffsetX(width: width),
                        opacity: sourceOpacity(for: travelProgress),
                        zIndex: 0,
                        includesPinnedGrid: true,
                        isVisuallyActive: false
                    )

                    transitionLayer(
                        for: destinationSpace,
                        pageRenderMode: SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer),
                        width: width,
                        offsetX: destinationOffsetX(width: width),
                        opacity: destinationOpacity(for: travelProgress),
                        zIndex: 1,
                        includesPinnedGrid: true,
                        isVisuallyActive: true
                    )
                }
            } else if transitionState.isGestureActive,
                      transitionState.destinationSpaceId == nil
            {
                committedSidebarPage(spaces: spaces, width: width)
            } else {
                committedSidebarPage(spaces: spaces, width: width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func committedSidebarPage(
        spaces: [Space],
        width: CGFloat
    ) -> some View {
        if let committedSpace = space(for: committedSpaceId(in: spaces), in: spaces) {
            makeSidebarPage(
                for: committedSpace,
                pageRenderMode: SpaceSidebarRenderPolicy.pageRenderMode(for: .committed)
            )
            .frame(width: width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.identity)
        }
    }

    @ViewBuilder
    private func sameProfileTransitionContainer(
        sourceSpace: Space,
        destinationSpace: Space,
        width: CGFloat,
        travelProgress: Double
    ) -> some View {
        let pageRenderMode = SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer)

        VStack(spacing: 8) {
            if !windowState.isIncognito {
                if let extensionActions = transitionSnapshot?.source.extensionActions {
                    ExtensionActionSnapshotGrid(
                        snapshot: extensionActions,
                        tokens: themeContext.tokens(settings: sumiSettings)
                    )
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)
                } else {
                    makeSidebarExtensionGrid(
                        profileId: resolvedPageProfileId(for: sourceSpace),
                        pageRenderMode: pageRenderMode
                    )
                    .allowsHitTesting(false)
                }

                if let essentials = transitionSnapshot?.stationaryEssentials {
                    EssentialsSnapshotGrid(
                        snapshot: essentials,
                        width: max(width - BrowserWindowState.sidebarHorizontalPadding, 0),
                        configuration: transitionSnapshot?.source.pinnedTabsConfiguration ?? .large,
                        tokens: themeContext.tokens(settings: sumiSettings)
                    )
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)
                } else {
                    makePinnedGrid(
                        spaceId: sourceSpace.id,
                        profileId: resolvedPageProfileId(for: sourceSpace),
                        pageRenderMode: pageRenderMode
                    )
                    .allowsHitTesting(false)
                }
            }

            ZStack(alignment: .topLeading) {
                transitionLayer(
                    for: sourceSpace,
                    pageRenderMode: pageRenderMode,
                    width: width,
                    offsetX: sourceOffsetX(width: width),
                    opacity: sourceOpacity(for: travelProgress),
                    zIndex: 0,
                    includesPinnedGrid: false,
                    isVisuallyActive: false
                )

                transitionLayer(
                    for: destinationSpace,
                    pageRenderMode: pageRenderMode,
                    width: width,
                    offsetX: destinationOffsetX(width: width),
                    opacity: destinationOpacity(for: travelProgress),
                    zIndex: 1,
                    includesPinnedGrid: false,
                    isVisuallyActive: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func transitionLayer(
        for space: Space,
        pageRenderMode: SidebarPageRenderMode,
        width: CGFloat,
        offsetX: CGFloat,
        opacity: Double,
        zIndex: Double,
        includesPinnedGrid: Bool,
        isVisuallyActive _: Bool
    ) -> some View {
        transitionLayerContent(
            for: space,
            pageRenderMode: pageRenderMode,
            width: width,
            includesPinnedGrid: includesPinnedGrid
        )
            .frame(width: width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: offsetX)
            .opacity(opacity)
            .zIndex(zIndex)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func transitionLayerContent(
        for space: Space,
        pageRenderMode: SidebarPageRenderMode,
        width: CGFloat,
        includesPinnedGrid: Bool
    ) -> some View {
        if pageRenderMode == .transitionSnapshot,
           let pageSnapshot = transitionSnapshot?.page(for: space.id)
        {
            SpaceTransitionSnapshotPageView(
                snapshot: pageSnapshot,
                includesEssentials: includesPinnedGrid,
                width: width,
                tokens: themeContext.tokens(settings: sumiSettings),
                themeContext: SpaceSidebarSnapshotThemeResolver.pageThemeContext(
                    for: space,
                    baseContext: themeContext,
                    settings: sumiSettings,
                    isIncognito: windowState.isIncognito
                )
            )
        } else {
            makeSidebarPage(
                for: space,
                pageRenderMode: pageRenderMode,
                includesPinnedGrid: includesPinnedGrid
            )
        }
    }

    private func sourceOpacity(for travelProgress: Double) -> Double {
        1 - (travelProgress * 0.12)
    }

    private func destinationOpacity(for travelProgress: Double) -> Double {
        0.88 + (travelProgress * 0.12)
    }

    private func sourceOffsetX(width: CGFloat) -> CGFloat {
        guard transitionState.hasDestination else { return 0 }
        return -CGFloat(transitionState.direction) * width * transitionState.progress
    }

    private func destinationOffsetX(width: CGFloat) -> CGFloat {
        guard transitionState.hasDestination else { return 0 }
        return CGFloat(transitionState.direction) * width * (1 - transitionState.progress)
    }

    private func committedSpaceId(in spaces: [Space]) -> UUID? {
        if let currentSpaceId = windowState.currentSpaceId,
           spaces.contains(where: { $0.id == currentSpaceId }) {
            return currentSpaceId
        }
        return spaces.first?.id
    }

    private func visualSelectedSpaceId(in spaces: [Space]) -> UUID? {
        transitionState.visualSelectedSpaceId ?? committedSpaceId(in: spaces)
    }

    private func usesSharedPinnedGrid(
        sourceSpace: Space,
        destinationSpace: Space
    ) -> Bool {
        SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
            sourceProfileId: resolvedPageProfileId(for: sourceSpace),
            destinationProfileId: resolvedPageProfileId(for: destinationSpace)
        )
    }

    private func space(for id: UUID?, in spaces: [Space]) -> Space? {
        guard let id else { return nil }
        return spaces.first(where: { $0.id == id })
    }

    private func handlePendingSplitGroupFocusRequest(
        _ request: SplitGroupFocusRequest?,
        spaces: [Space]
    ) {
        guard let request else { return }

        if windowState.currentSpaceId == request.targetSpaceId {
            browserManager.completePendingSplitGroupFocusIfReady(
                in: windowState,
                spaceId: request.targetSpaceId
            )
            return
        }

        guard let targetSpace = space(for: request.targetSpaceId, in: spaces) else {
            windowState.pendingSplitGroupFocusRequest = nil
            return
        }

        switchSpace(to: targetSpace, spaces: spaces)
    }

    private func handleSpacesCollectionChange(_ spaces: [Space]) {
        let wasGestureActive = transitionState.isGestureActive
        let hadThemeTransition = hasActiveThemeTransition
        transitionState.syncSpaces(
            orderedSpaceIds: spaces.map(\.id),
            committedSpaceId: committedSpaceId(in: spaces)
        )

        if wasGestureActive && !transitionState.isGestureActive {
            cancelPendingSpaceTransition()
            cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: hadThemeTransition)
            clearTransitionSnapshot()
        }

        guard let firstSpace = spaces.first else {
            cancelLocalSpaceTransitionIfNeeded(cancelTheme: true)
            return
        }

        guard let currentSpaceId = windowState.currentSpaceId,
              spaces.contains(where: { $0.id == currentSpaceId })
        else {
            browserManager.setActiveSpace(firstSpace, in: windowState)
            return
        }
    }

    private func handleTransitionProgressFrame(
        _ progress: Double,
        spaces: [Space]
    ) {
        guard !(transitionState.trigger == .swipe && transitionState.phase == .interactive) else {
            return
        }

        guard transitionState.hasDestination,
              space(for: transitionState.sourceSpaceId, in: spaces) != nil,
              space(for: transitionState.destinationSpaceId, in: spaces) != nil
        else {
            return
        }

        updateInteractiveThemeTransitionProgress(progress)
    }

    private func handleSwipeEvent(
        _ event: SpaceSwipeGestureEvent,
        spaces: [Space]
    ) {
        let orderedSpaceIds = spaces.map(\.id)

        switch event.phase {
        case .began:
            return

        case .changed:
            guard SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(for: event) else {
                return
            }

            if transitionState.phase == .idle {
                _ = transitionState.beginSwipeGesture(
                    from: committedSpaceId(in: spaces),
                    orderedSpaceIds: orderedSpaceIds
                )
            }

            guard transitionState.trigger == .swipe else { return }

            let previousDestinationSpaceId = transitionState.destinationSpaceId
            let hadThemeTransition = hasActiveThemeTransition
            transitionState.updateSwipeGesture(
                progress: event.progress,
                latchedDirection: event.direction,
                orderedSpaceIds: orderedSpaceIds
            )

            guard transitionState.destinationSpaceId != nil else {
                cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: hadThemeTransition)
                transitionState.reset()
                clearTransitionSnapshot()
                refreshCommittedSidebarDragGeometry(spaces: spaces)
                return
            }

            reconcileSwipeThemeTransition(
                previousDestinationSpaceId: previousDestinationSpaceId,
                hadThemeTransition: hadThemeTransition,
                spaces: spaces
            )

        case .ended:
            guard transitionState.trigger == .swipe else { return }
            if transitionState.destinationSpaceId == nil && transitionState.progress < 0.001 {
                transitionState.reset()
                clearTransitionSnapshot()
                return
            }
            settleInteractiveSpaceTransition(commit: transitionState.shouldCommitSwipeOnEnd)

        case .cancelled:
            guard transitionState.trigger == .swipe else { return }
            if transitionState.destinationSpaceId == nil && transitionState.progress < 0.001 {
                cancelInteractiveThemeTransitionIfNeeded()
                transitionState.reset()
                clearTransitionSnapshot()
                return
            }
            settleInteractiveSpaceTransition(commit: false)
        }
    }

    private func settleInteractiveSpaceTransition(commit: Bool) {
        guard transitionState.isGestureActive else { return }

        transitionState.markSettling()
        let targetProgress = commit ? 1.0 : 0.0

        withAnimation(spaceSwitchAnimation()) {
            transitionState.updateProgress(targetProgress)
        }

        scheduleTransitionCompletion(
            after: SpaceSidebarRenderPolicy.completionDelay,
            commit: commit
        )
    }

    private func switchSpace(
        to targetSpace: Space,
        spaces: [Space]
    ) {
        guard transitionState.beginClick(
            from: committedSpaceId(in: spaces),
            to: targetSpace.id,
            orderedSpaceIds: spaces.map(\.id)
        ),
        let sourceSpace = space(for: transitionState.sourceSpaceId, in: spaces),
        let destinationSpace = space(for: transitionState.destinationSpaceId, in: spaces)
        else {
            return
        }

        cancelPendingSpaceTransition()
        captureTransitionSnapshot(sourceSpace: sourceSpace, destinationSpace: destinationSpace)
        startInteractiveThemeTransition(from: sourceSpace, to: destinationSpace)
        updateInteractiveThemeTransitionProgress(0)

        withAnimation(spaceSwitchAnimation()) {
            transitionState.updateProgress(1)
        }

        scheduleTransitionCompletion(
            after: SpaceSidebarRenderPolicy.completionDelay,
            commit: true
        )
    }

    private func scheduleTransitionCompletion(
        after duration: Double,
        commit: Bool
    ) {
        cancelPendingSpaceTransition()
        let destinationSpaceId = transitionState.destinationSpaceId
        let hadThemeTransition = hasActiveThemeTransition

        transitionTask = Task { @MainActor in
            let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }

            finishScheduledSpaceTransition(
                commit: commit,
                destinationSpaceId: destinationSpaceId,
                hadThemeTransition: hadThemeTransition
            )
        }
    }

    private func cancelPendingSpaceTransition() {
        transitionTask?.cancel()
        transitionTask = nil
    }

    private func cancelLocalSpaceTransitionIfNeeded(cancelTheme: Bool) {
        cancelPendingSpaceTransition()
        if cancelTheme {
            cancelInteractiveThemeTransitionIfNeeded()
        }
        transitionState.reset()
        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(spaces: availableSpaces)
    }

    private func spaceSwitchAnimation() -> Animation {
        SidebarMotionPolicy.spaceSwitchAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: reduceMotion)
        ) ?? .linear(duration: 0)
    }

    private var hasActiveThemeTransition: Bool {
        transitionState.hasDestination || windowState.isInteractiveSpaceTransition
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func startInteractiveThemeTransition(
        from sourceSpace: Space,
        to destinationSpace: Space
    ) {
        browserManager.beginInteractiveSpaceTransition(
            from: sourceSpace,
            to: destinationSpace,
            in: windowState
        )
    }

    private func updateInteractiveThemeTransitionProgress(_ progress: Double) {
        browserManager.updateInteractiveSpaceTransition(
            progress: progress,
            in: windowState
        )
    }

    private func cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: Bool? = nil) {
        let shouldCancel = hadThemeTransition ?? hasActiveThemeTransition
        guard shouldCancel else { return }
        browserManager.cancelInteractiveSpaceTransition(in: windowState)
    }

    private func reconcileSwipeThemeTransition(
        previousDestinationSpaceId: UUID?,
        hadThemeTransition: Bool,
        spaces: [Space]
    ) {
        guard let sourceSpace = space(for: transitionState.sourceSpaceId, in: spaces) else {
            return
        }

        if let destinationSpaceId = transitionState.destinationSpaceId,
           let destinationSpace = space(for: destinationSpaceId, in: spaces)
        {
            if previousDestinationSpaceId != destinationSpaceId || !windowState.isInteractiveSpaceTransition {
                cancelPendingSpaceTransition()
                captureTransitionSnapshot(sourceSpace: sourceSpace, destinationSpace: destinationSpace)
                startInteractiveThemeTransition(from: sourceSpace, to: destinationSpace)
            } else if transitionSnapshot == nil {
                captureTransitionSnapshot(sourceSpace: sourceSpace, destinationSpace: destinationSpace)
            }

            updateInteractiveThemeTransitionProgress(transitionState.progress)
            return
        }

        if previousDestinationSpaceId != nil || hadThemeTransition {
            cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: true)
            clearTransitionSnapshot()
        }
    }

    private func finishScheduledSpaceTransition(
        commit: Bool,
        destinationSpaceId: UUID?,
        hadThemeTransition: Bool
    ) {
        // Reset the local render mode before publishing the committed space.
        // Otherwise the destination can briefly rebuild as a transition snapshot,
        // leaving non-drag-capable AppKit row owners under the visible sidebar.
        let completedDestinationSpaceId = transitionState.finishTransition(commit: commit)

        if commit,
           let destinationSpaceId = completedDestinationSpaceId ?? destinationSpaceId,
           let destinationSpace = space(for: destinationSpaceId, in: availableSpaces)
        {
            browserManager.setActiveSpace(destinationSpace, in: windowState)
        } else {
            cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: hadThemeTransition)
        }

        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(spaces: availableSpaces)
        transitionTask = nil
    }

    private func refreshCommittedSidebarDragGeometryIfInteractive(spaces: [Space]) {
        guard allowsSidebarInteractiveWork else { return }
        refreshCommittedSidebarDragGeometry(spaces: spaces)
    }

    private func refreshCommittedSidebarDragGeometry(spaces: [Space]) {
        guard allowsSidebarInteractiveWork else { return }
        guard transitionState.phase == .idle,
              let committedSpace = space(for: committedSpaceId(in: spaces), in: spaces) else {
            return
        }

        dragState.beginPendingGeometryEpoch(
            expectedSpaceId: committedSpace.id,
            profileId: resolvedPageProfileId(for: committedSpace)
        )
    }

    private func captureTransitionSnapshot(
        sourceSpace: Space,
        destinationSpace: Space
    ) {
        if transitionSnapshot?.matches(
            sourceSpaceId: sourceSpace.id,
            destinationSpaceId: destinationSpace.id
        ) == true {
            return
        }

        transitionSnapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: sumiSettings
        )
    }

    private func clearTransitionSnapshot() {
        transitionSnapshot = nil
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                Text("No Spaces")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Create a space to start browsing")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Button(action: beginSpaceCreationMode) {
                Label("Create Space", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Context Menu

    private func sidebarContextMenuEntries() -> [SidebarContextMenuEntry] {
        let newFolderAction: (() -> Void)? = browserManager.spaceForSidebarActions(in: windowState) == nil
            ? nil
            : {
                browserManager.createFolderInCurrentSpace(in: windowState)
            }
        let changeThemeAction: (() -> Void)? = browserManager.tabManager.currentSpace == nil
            ? nil
            : {
                browserManager.showGradientEditor(
                    source: windowState.resolveSidebarPresentationSource()
                )
            }

        return makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: !windowState.isSidebarVisible,
            actions: .init(
                newTab: {
                    browserManager.openNewTabOrFloatingBar(in: windowState)
                },
                newFolder: newFolderAction,
                changeTheme: changeThemeAction,
                toggleCompactMode: {
                    browserManager.toggleSidebar(for: windowState)
                },
                openSettings: {
                    browserManager.openSettingsTab(selecting: .appearance, in: windowState)
                }
            )
        )
    }

    // MARK: - Helper Functions

    private func handleSidebarContextMenuVisibility(_ presented: Bool) {
        if presented {
            browserManager.closeDownloadsPopover(in: windowState)
        }
    }

    @ViewBuilder
    private func makeSpaceView(
        for space: Space,
        renderMode: SpaceViewRenderMode,
        allowsInteraction: Bool
    ) -> some View {
        SpaceView(
            space: space,
            renderMode: renderMode,
            allowsInteraction: allowsInteraction,
            isSidebarHovered: $isSidebarHovered,
            onActivateTab: {
                browserManager.requestUserTabActivation(
                    $0,
                    in: windowState
                )
            },
            onCloseTab: { browserManager.closeTab($0, in: windowState) },
            onMoveTabUp: { browserManager.tabManager.moveTabUp($0.id) },
            onMoveTabDown: { browserManager.tabManager.moveTabDown($0.id) },
            onMuteTab: { $0.toggleMute() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(browserManager)
        .environmentObject(browserManager.glanceManager)
        .environment(windowState)
        .environmentObject(browserManager.splitManager)
        .id(space.id)
    }

    @ViewBuilder
    private func makeSidebarPage(
        for space: Space,
        pageRenderMode: SidebarPageRenderMode,
        includesPinnedGrid: Bool = true
    ) -> some View {
        let pageProfileId = resolvedPageProfileId(for: space)
        // Fallback-only identity change for unresolved AppKit owner/input graph recovery.
        let inputRecoveryGeneration = pageRenderMode == .interactive
            ? windowState.sidebarInputRecoveryGeneration
            : 0
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork

        VStack(spacing: 8) {
            if includesPinnedGrid && !windowState.isIncognito {
                makeSidebarExtensionGrid(
                    profileId: pageProfileId,
                    pageRenderMode: pageRenderMode
                )

                makePinnedGrid(
                    spaceId: space.id,
                    profileId: pageProfileId,
                    pageRenderMode: pageRenderMode
                )
            }

            makeSpaceView(
                for: space,
                renderMode: pageRenderMode.spaceRenderMode,
                allowsInteraction: pageRenderMode == .interactive && allowsSidebarInteractiveWork
            )
        }
        .animation(allowsInteractiveWork ? .easeInOut(duration: 0.18) : nil, value: dragState.hoveredSlot)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sidebarPageGeometry(
            spaceId: space.id,
            profileId: pageProfileId,
            renderMode: pageRenderMode.geometryRenderMode,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: allowsInteractiveWork
        )
        .id(
            SidebarPageInputGraphIdentity(
                spaceId: space.id,
                profileId: pageProfileId,
                recoveryGeneration: inputRecoveryGeneration
            )
        )
    }

    @ViewBuilder
    private func makeSidebarExtensionGrid(
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let slots = browserManager.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: extensionSurfaceStore.enabledExtensions,
            sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled,
            profileId: profileId
        )
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork

        if ExtensionActionPlacement.resolve(totalActions: slots.count) == .sidebarGrid {
            ExtensionActionView(
                extensions: extensionSurfaceStore.enabledExtensions,
                layout: .sidebarGrid,
                profileId: profileId
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .padding(.horizontal, 8)
            .allowsHitTesting(allowsInteractiveWork)
            .transaction { transaction in
                if !allowsInteractiveWork {
                    transaction.disablesAnimations = true
                }
            }
        }
    }

    @ViewBuilder
    private func makePinnedGrid(
        spaceId: UUID,
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork
        let shouldAnimate = SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: browserManager.isTransitioningProfile,
            pageRenderMode: pageRenderMode
        ) && allowsInteractiveWork

        PinnedGrid(
            width: windowState.sidebarContentWidth,
            spaceId: spaceId,
            profileId: profileId,
            animateLayout: shouldAnimate,
            reportsGeometry: allowsInteractiveWork,
            isAppKitInteractionEnabled: allowsInteractiveWork
        )
        .environmentObject(browserManager)
        .environment(windowState)
        .padding(.horizontal, 8)
    }

    private func resolvedPageProfileId(for space: Space?) -> UUID? {
        space?.profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
    }

    // MARK: - Space Creation

    private var spaceCreationTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }

    private func beginSpaceCreationMode() {
        let source = windowState.resolveSidebarPresentationSource()
        let defaultProfileID = windowState.currentProfileId
            ?? browserManager.currentProfile?.id
            ?? browserManager.profileManager.profiles.first?.id

        windowState.beginSpaceCreationSession(
            source: source,
            defaultProfileID: defaultProfileID
        )
    }

    private func commitSpaceCreationSession(_ session: SpaceCreationSession) {
        guard session.canCommit else { return }

        let profileId: UUID?
        if session.createsNewProfile {
            guard isNewProfileNameAvailable(for: session) else { return }
            let createdProfile = browserManager.profileManager.createProfile(
                name: session.trimmedNewProfileName,
                icon: session.resolvedNewProfileIcon
            )
            profileId = createdProfile.id
        } else {
            profileId = session.profileID
        }

        let newSpace = browserManager.tabManager.createSpace(
            name: session.trimmedName,
            icon: session.resolvedIcon,
            profileId: profileId
        )
        if let resolvedSpace = browserManager.tabManager.spaces.first(where: { $0.id == newSpace.id }) {
            browserManager.setActiveSpace(resolvedSpace, in: windowState)
        }

        windowState.finishSpaceCreationSession(
            session,
            reason: "SpacesSideBarView.commitSpaceCreationSession"
        )
    }

    private func cancelSpaceCreationSession(_ session: SpaceCreationSession) {
        session.cancelsOnDismiss = true
        windowState.finishSpaceCreationSession(
            session,
            reason: "SpacesSideBarView.cancelSpaceCreationSession"
        )
    }

    private func isNewProfileNameAvailable(for session: SpaceCreationSession) -> Bool {
        let trimmed = session.trimmedNewProfileName
        guard !trimmed.isEmpty else { return false }
        return !browserManager.profileManager.profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    // MARK: - Computed Properties
}
