//
//  TabFolderView.swift
//  Sumi
//
//

import SwiftUI
import UniformTypeIdentifiers

private typealias FolderListItem = SidebarFolderListItem
private typealias FolderDisplayEntry = SidebarFolderDisplayEntry

struct TabFolderView: View {
    private static let folderContentLeadingPadding: CGFloat = 14
    private static let folderContentVerticalPadding: CGFloat = 4

    var folder: TabFolder
    let space: Space
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
    @Binding var shortcutRestoreGaps: [ShortcutRestoreGap]
    @Binding var shortcutRestoreAppearingGapIds: Set<UUID>
    let elevatedFolderIds: Set<UUID>
    let renderMode: SpaceViewRenderMode
    let parentFolderId: UUID?
    let containerIndex: Int
    let nestingDepth: Int
    let onUngroup: () -> Void
    let onDelete: () -> Void
    let onPrepareShortcutRestoreGap: (SplitGroupSidebarItem, SplitGroup) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (SplitGroupSidebarItem, SplitGroup, @escaping () -> Void) -> Void

    @State private var displayedCollapsedProjectionIDs: [UUID] = []

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dragState: SidebarDragState

    private var folderDragSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(dragState: dragState)
    }

    private var isInteractive: Bool {
        renderMode.isInteractive
    }

    private var shortcutPinsInFolder: [ShortcutPin] {
        shortcutPins
    }

    private var folderProjectionState: SidebarFolderProjectionState {
        windowState.sidebarFolderProjection(for: folder.id)
    }

    private var contextMenuActionOwner: TabFolderContextMenuActionOwner {
        TabFolderContextMenuActionOwner(
            folder: folder,
            space: space,
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            browserManager: browserManager,
            windowState: windowState,
            themeContext: themeContext,
            folderLayoutAnimation: folderLayoutAnimation,
            onUngroup: onUngroup,
            onDelete: onDelete
        )
    }

    private func targetCollapsedProjectionIDs(
        using projection: SidebarFolderViewProjection
    ) -> [UUID] {
        guard !folder.isOpen else { return [] }
        return SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        )
    }

    private var isFolderDropHighlighted: Bool {
        folderDragSnapshot.isContainTargeted(folderID: folder.id)
    }

    private var folderPreviewIsOpen: Bool {
        folderDragSnapshot.isFolderPreviewOpen(folderID: folder.id, isOpen: folder.isOpen)
    }

    private var resolvedTopLevelPinnedIndex: Int {
        containerIndex
    }

    private func folderContentProjection(
        using projection: SidebarFolderViewProjection,
        dragSnapshot: SidebarFolderDragSnapshot
    ) -> SidebarFolderContentProjection {
        SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            folderID: folder.id,
            isFolderOpen: folder.isOpen,
            shortcutPins: shortcutPinsInFolder,
            restoreGaps: shortcutRestoreGaps,
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection,
            dragProjection: SidebarFolderDragDisplayProjection(
                dragSnapshot: dragSnapshot,
                folderID: folder.id,
                baseItems: projection.baseItems
            )
        )
    }

    private func folderBodyShouldRender(
        contentProjection: SidebarFolderContentProjection
    ) -> Bool {
        folder.isOpen || contentProjection.hasCollapsedProjectionForLayout
    }

    private func folderBodyGeometryIsActive(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> Bool {
        isInteractive && folderBodyShouldRender(contentProjection: contentProjection) && !projection.isLiveFolder
    }

    private var folderLayoutAnimation: Animation? {
        folderDragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive)
            ? SidebarMotionPolicy.folderLayoutAnimation(
                for: SidebarMotionPolicy.currentMode(
                    reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
                )
            )
            : nil
    }

    private func folderHasActiveSelection(
        using projection: SidebarFolderViewProjection
    ) -> Bool {
        if projection.isLiveFolder,
           let currentURLString = projection.currentTabURLString,
           projection.liveFolderItems.contains(where: { $0.urlString == currentURLString }) {
            return true
        }

        return elevatedFolderIds.contains(folder.id)
    }

    private var folderShellPalette: SumiFolderGlyphPalette {
        let accent = themeContext.gradient.primaryColor
        let scheme = themeContext.chromeColorScheme

        let backFill: Color
        let frontFill: Color
        let stroke: Color

        switch scheme {
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

    var body: some View {
        SidebarFolderViewProjectionReader(
            folder: folder,
            space: space,
            shortcutPins: shortcutPins,
            childFolders: childFolders,
            shortcutRestoreGaps: shortcutRestoreGaps,
            tabManager: browserManager.tabManager,
            liveFolderManager: browserManager.liveFolderManager,
            currentTab: browserManager.currentTab(for: windowState)
        ) { projection in
            let dragSnapshot = folderDragSnapshot
            let contentProjection = folderContentProjection(
                using: projection,
                dragSnapshot: dragSnapshot
            )

            folderCompositeContent(
                contentProjection: contentProjection,
                projection: projection
            )
                .transaction { transaction in
                    if dragSnapshot.isCompletingDrop {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .onChange(of: targetCollapsedProjectionIDs(using: projection)) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onChange(of: folder.isOpen) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                    refreshLiveFolderIfNeeded()
                }
                .onChange(of: windowState.currentTabId) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onChange(of: windowState.currentShortcutPinId) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onAppear {
                    syncDisplayedCollapsedProjectionIDs(animated: false, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                    refreshLiveFolderIfNeeded()
                }
        }
    }

    private func refreshLiveFolderIfNeeded() {
        guard folder.isOpen else { return }
        browserManager.liveFolderManager.refreshIfStale(folderId: folder.id)
    }

    private func folderCompositeContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        VStack(spacing: 0) {
            folderHeader(contentProjection: contentProjection, projection: projection)
            folderBodyContainer(
                contentProjection: contentProjection,
                projection: projection
            )
        }
        .background(alignment: .bottom) {
            folderAfterDropTarget(childCount: contentProjection.childCount)
        }
    }

    @ViewBuilder
    private func folderBodyContainer(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        folderBodyAnimatedContent(
            contentProjection: contentProjection,
            projection: projection
        )
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: contentProjection.childCount,
                isOpen: folder.isOpen,
                region: .body,
                generation: folderDragSnapshot.geometryGeneration,
                isActive: folderBodyGeometryIsActive(
                    contentProjection: contentProjection,
                    projection: projection
                )
            )
    }

    @ViewBuilder
    private func folderBodyAnimatedContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        if folderBodyShouldRender(contentProjection: contentProjection) {
            folderBodyVisibleContent(contentProjection: contentProjection, projection: projection)
                .transition(.sidebarRowContentOpacity)
                .animation(folderLayoutAnimation, value: folder.isOpen)
                .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
                .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
                .animation(folderLayoutAnimation, value: contentProjection.targetCollapsedProjectionIDs)
        } else {
            Color.clear
                .frame(height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func folderBodyVisibleContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        folderBodyContent(
            contentProjection: contentProjection,
            reportsGeometry: true,
            reportsFolderChildGeometry: folder.isOpen,
            projection: projection
        )
        .allowsHitTesting(folder.isOpen || !contentProjection.visibleCollapsedProjectionIDs.isEmpty)
        .animation(folderLayoutAnimation, value: folder.isOpen)
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
        .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
        .animation(folderLayoutAnimation, value: contentProjection.targetCollapsedProjectionIDs)
    }

    @ViewBuilder
    private func folderAfterDropTarget(childCount: Int) -> some View {
        let dragSnapshot = folderDragSnapshot
        let height = dragSnapshot.afterDropTargetHeight(rowHeight: SidebarRowLayout.rowHeight)
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .offset(y: height / 2)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: childCount,
                isOpen: folder.isOpen,
                region: .after,
                generation: dragSnapshot.geometryGeneration,
                isActive: isInteractive && height > 0
            )
            .allowsHitTesting(false)
    }

    private func folderHeader(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        TabFolderHeaderRow(
            title: folder.name,
            glyphPresentation: folderGlyphPresentation(
                using: projection,
                contentProjection: contentProjection
            ),
            glyphPalette: folderShellPalette,
            isDropHighlighted: isFolderDropHighlighted,
            isInteractive: isInteractive
        )
        .sidebarFolderDropGeometry(
            folderId: folder.id,
            spaceId: space.id,
            parentFolderId: parentFolderId,
            topLevelIndex: resolvedTopLevelPinnedIndex,
            childCount: contentProjection.childCount,
            isOpen: folder.isOpen,
            region: .header,
            generation: folderDragSnapshot.geometryGeneration,
            isActive: isInteractive && !projection.isLiveFolder
        )
        .sidebarAppKitContextMenu(
            isEnabled: true,
            isInteractionEnabled: isInteractive,
            dragSource: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(folderId: folder.id, title: folder.name),
                sourceZone: parentFolderId.map(DropZoneID.folder) ?? .spacePinned(space.id),
                previewKind: .folderRow,
                pinnedConfig: .large,
                folderGlyphPresentation: folderGlyphPresentation(
                    using: projection,
                    contentProjection: contentProjection
                ),
                folderGlyphPalette: folderShellPalette,
                onActivate: {
                    toggleFolderOpenState()
                },
                isEnabled: isInteractive
            ),
            primaryAction: {
                toggleFolderOpenState()
            },
            sourceID: folderHeaderSourceID,
            entries: {
                contextMenuActionOwner.folderHeaderContextMenuEntries()
            }
        )
        .accessibilityIdentifier("folder-header-\(folder.id.uuidString)")
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.isOpen ? "expanded" : "collapsed")
    }

    private func folderBodyContent(
        contentProjection: SidebarFolderContentProjection,
        reportsGeometry: Bool,
        reportsFolderChildGeometry: Bool,
        projection: SidebarFolderViewProjection
    ) -> some View {
        let childFoldersById = Dictionary(uniqueKeysWithValues: childFolders.map { ($0.id, $0) })
        let shortcutPinsById = Dictionary(uniqueKeysWithValues: shortcutPinsInFolder.map { ($0.id, $0) })

        return LazyVStack(spacing: 0) {
            ForEach(contentProjection.bodyDisplayEntries) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .folder(let folderId):
                        if let childFolder = childFoldersById[folderId] {
                            nestedFolderView(childFolder, containerIndex: entry.dropIndex)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: childFolder.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .shortcut(let pinId):
                        if let pin = shortcutPinsById[pinId] {
                            folderShortcutView(pin, projection: projection)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: pin.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .liveItem(let itemId):
                        if let item = projection.liveFolderItem(with: itemId) {
                            liveFolderItemView(item)
                        }
                    case .splitGroup(let groupId):
                        if let group = projection.splitGroup(with: groupId) {
                            shortcutHostedSplitGroupView(
                                group,
                                items: projection.splitGroupItems(for: groupId)
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: group.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .restoreGap(let gapId):
                        shortcutRestoreGap(gapId, projection: projection)
                    case .placeholder:
                        folderDropGap
                    }
                }
                .zIndex(folderDisplayEntryZIndex(entry, projection: projection))
            }
        }
        .padding(.leading, Self.folderContentLeadingPadding)
        .padding(.vertical, Self.folderContentVerticalPadding)
        .background(alignment: .leading) {
            folderNestingGuide(isVisible: !contentProjection.bodyItems.isEmpty)
        }
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
    }

    private func nestedFolderView(_ childFolder: TabFolder, containerIndex: Int) -> some View {
        TabFolderView(
            folder: childFolder,
            space: space,
            shortcutPins: folderPinsByFolderId[childFolder.id] ?? [],
            childFolders: childFoldersByParentId[childFolder.id] ?? [],
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            shortcutRestoreGaps: $shortcutRestoreGaps,
            shortcutRestoreAppearingGapIds: $shortcutRestoreAppearingGapIds,
            elevatedFolderIds: elevatedFolderIds,
            renderMode: renderMode,
            parentFolderId: folder.id,
            containerIndex: containerIndex,
            nestingDepth: nestingDepth + 1,
            onUngroup: {
                ungroupNestedFolder(childFolder)
            },
            onDelete: {
                deleteNestedFolder(childFolder)
            },
            onPrepareShortcutRestoreGap: onPrepareShortcutRestoreGap,
            onPerformShortcutRestoreWithPreparedGap: onPerformShortcutRestoreWithPreparedGap
        )
        .environmentObject(browserManager)
        .environmentObject(splitManager)
        .environment(windowState)
    }

    @ViewBuilder
    private func folderNestingGuide(isVisible: Bool) -> some View {
        if isVisible {
            Rectangle()
                .fill(tokens.separator.opacity(0.55))
                .frame(width: 1)
                .padding(.vertical, 6)
                .offset(x: 6)
                .accessibilityHidden(true)
        }
    }

    private func folderDisplayEntryZIndex(
        _ entry: FolderDisplayEntry,
        projection: SidebarFolderViewProjection
    ) -> Double {
        SidebarSelectionElevation.zIndex(
            isElevated: folderListItemIsElevated(entry.item, projection: projection)
        )
    }

    private func folderListItemIsElevated(
        _ item: FolderListItem,
        projection: SidebarFolderViewProjection
    ) -> Bool {
        switch item {
        case .folder(let folderId):
            return folderContainsElevatedSelection(folderId)
        case .shortcut(let pinId):
            guard let pin = shortcutPinsInFolder.first(where: { $0.id == pinId }) else {
                return false
            }
            if let placeholderGroup = projection.regularPlaceholderGroup(for: pin.id) {
                return isFolderSplitPlaceholderSelected(placeholderGroup, pin: pin)
            }
            return shortcutPinIsElevated(pin, projection: projection)
        case .liveItem(let itemId):
            guard let item = projection.liveFolderItem(with: itemId) else {
                return false
            }
            return projection.currentTabURLString == item.urlString
        case .splitGroup(let groupId):
            guard let group = projection.splitGroup(with: groupId) else {
                return false
            }
            return splitGroupIsElevated(group)
        case .restoreGap, .placeholder:
            return false
        }
    }

    private func shortcutPinIsElevated(
        _ pin: ShortcutPin,
        projection: SidebarFolderViewProjection
    ) -> Bool {
        projection.isShortcutSelected(pin)
    }

    private func splitGroupIsElevated(_ group: SplitGroup) -> Bool {
        SidebarSelectionElevation.splitGroupContainsCurrentTab(
            group,
            currentTabId: windowState.currentTabId
        )
    }

    private func folderContainsElevatedSelection(_ folderId: UUID) -> Bool {
        elevatedFolderIds.contains(folderId)
    }

    private var folderDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
    }

    private func shortcutRestoreGap(
        _ gapId: UUID,
        projection: SidebarFolderViewProjection
    ) -> some View {
        let isAppearing = shortcutRestoreAppearingGapIds.contains(gapId)
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }),
               let pin = projection.shortcutPin(with: gap.pinId) {
                folderShortcutView(pin, projection: projection)
                    .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
            }
        }
        .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowStagedInsertion(isRevealing: isAppearing)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func shortcutHostedSplitGroupView(
        _ group: SplitGroup,
        items: [SplitGroupSidebarItem]
    ) -> some View {
        if !items.isEmpty {
            ShortcutHostedSplitGroupRow(
                group: group,
                items: items,
                spaceId: space.id,
                tabManager: browserManager.tabManager,
                isAppKitInteractionEnabled: isInteractive,
                accessibilityID: "folder-shortcut-host-split-row-\(group.id.uuidString)",
                onActivateTab: { tab in
                    browserManager.requestUserTabActivation(tab, in: windowState)
                },
                onActivateGroup: { group in
                    browserManager.focusSplitGroup(group, in: windowState)
                },
                onRestoreShortcutSplitMember: { item, group in
                    browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
                },
                onCloseTab: { tab in
                    browserManager.closeTab(tab, in: windowState)
                },
                onPrepareShortcutRestoreGap: onPrepareShortcutRestoreGap,
                onPerformShortcutRestoreWithPreparedGap: onPerformShortcutRestoreWithPreparedGap
            )
            .environmentObject(splitManager)
        }
    }

    @ViewBuilder
    private func folderShortcutView(
        _ pin: ShortcutPin,
        projection: SidebarFolderViewProjection
    ) -> some View {
        if let placeholderGroup = projection.regularPlaceholderGroup(for: pin.id) {
            ShortcutSplitPlaceholderRow(
                pin: pin,
                isSelected: isFolderSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "folder-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isInteractive,
                action: {
                    browserManager.focusSplitGroup(placeholderGroup, in: windowState)
                }
            )
            .opacity(
                folderDragSnapshot.childOpacity(itemID: pin.id)
            )
        } else {
            ShortcutSidebarRow(
                pin: pin,
                liveTab: projection.liveTab(for: pin.id),
                faviconPartition: browserManager.tabManager.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                    for: pin,
                    in: windowState
                ),
                accessibilityID: "folder-shortcut-\(pin.id.uuidString)",
                contextMenuEntries: {
                    contextMenuActionOwner.folderShortcutContextMenuEntries(pin)
                },
                action: { activateShortcutPin(pin) },
                dragSourceZone: .folder(folder.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onResetToLaunchURL: { contextMenuActionOwner.resetShortcutPin(pin) },
                onUnload: { contextMenuActionOwner.unloadShortcutPin(pin) },
                onRemove: { contextMenuActionOwner.removeShortcutPin(pin) }
            )
            .opacity(
                folderDragSnapshot.childOpacity(itemID: pin.id)
            )
        }
    }

    private func liveFolderItemView(_ item: SumiLiveFolderItem) -> some View {
        SumiLiveFolderItemRow(
            item: item,
            accessibilityID: "live-folder-item-\(folder.id.uuidString)-\(item.id)",
            contextMenuEntries: {
                contextMenuActionOwner.liveFolderItemContextMenuEntries(item)
            },
            action: {
                browserManager.liveFolderManager.open(item: item, in: windowState)
            },
            onDismiss: {
                browserManager.liveFolderManager.dismiss(item: item)
            }
        )
        .environmentObject(browserManager)
        .environment(windowState)
    }

    private func isFolderSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        guard let currentTabId = windowState.currentTabId else {
            return false
        }
        return group.contains(currentTabId)
            || group.member(forPinId: pin.id)?.tabId == currentTabId
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var folderHeaderSourceID: String {
        "folder-header-\(folder.id.uuidString)"
    }

    private func toggleFolderOpenState() {
        withAnimation(folderLayoutAnimation) {
            browserManager.tabManager.toggleFolderOpenState(folder.id)
        }
    }

    private func folderGlyphPresentation(
        using projection: SidebarFolderViewProjection,
        contentProjection: SidebarFolderContentProjection
    ) -> SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: folder.icon,
            isOpen: folderPreviewIsOpen,
            hasActiveProjection: folderHasProjectedContent(
                using: projection,
                contentProjection: contentProjection
            )
        )
    }

    private func folderHasProjectedContent(
        using projection: SidebarFolderViewProjection,
        contentProjection: SidebarFolderContentProjection
    ) -> Bool {
        folderProjectionState.hasActiveProjection
            || folderHasActiveSelection(using: projection)
            || contentProjection.hasCollapsedProjectionForLayout
    }

    private func scheduleProjectionStateRefresh(
        projection: SidebarFolderViewProjection
    ) {
        let projectedIDs = SidebarFolderDisplayProjection.targetCollapsedProjectionPins(
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        ).map(\.id)
        let newHasActiveProjection = folderHasActiveSelection(using: projection) || !projectedIDs.isEmpty
        windowState.scheduleSidebarFolderProjectionUpdate(
            for: folder.id,
            projectedChildIDs: projectedIDs,
            hasActiveProjection: newHasActiveProjection
        )
    }

    private func syncDisplayedCollapsedProjectionIDs(
        animated: Bool,
        projection: SidebarFolderViewProjection
    ) {
        let targetIDs = targetCollapsedProjectionIDs(using: projection)
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated && folderDragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive) {
            withAnimation(folderLayoutAnimation, update)
        } else {
            update()
        }
    }

    private func activateShortcutPin(_ pin: ShortcutPin) {
        let tab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func deleteNestedFolder(_ childFolder: TabFolder) {
        let childCount = browserManager.tabManager.folderRecursiveChildCount(
            for: childFolder.id,
            in: space.id
        )
        guard childCount == 0 else {
            SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
                folderName: childFolder.name,
                childCount: childCount,
                window: windowState.window,
                onDelete: {
                    mutateFolderContent {
                        browserManager.tabManager.deleteFolder(childFolder.id)
                    }
                }
            )
            return
        }

        mutateFolderContent {
            browserManager.tabManager.deleteFolder(childFolder.id)
        }
    }

    private func ungroupNestedFolder(_ childFolder: TabFolder) {
        mutateFolderContent {
            browserManager.tabManager.ungroupFolder(childFolder.id)
        }
    }

    private func mutateFolderContent(_ update: () -> Void) {
        if let animation = folderLayoutAnimation {
            withAnimation(animation, update)
        } else {
            update()
        }
    }
}
