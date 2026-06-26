//
//  TabFolderView.swift
//  Sumi
//
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
    @State private var isFolderHeaderHovered = false

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var dragState = SidebarDragState.shared

    private var folderDragSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(dragState: dragState)
    }

    private var isInteractive: Bool {
        renderMode.isInteractive
    }

    private var shortcutPinsInFolder: [ShortcutPin] {
        shortcutPins
    }

    private var descendantShortcutPins: [ShortcutPin] {
        descendantShortcutPins(in: folder.id, visited: [])
    }

    private func descendantShortcutPins(in folderId: UUID, visited: Set<UUID>) -> [ShortcutPin] {
        guard !visited.contains(folderId) else { return [] }
        var nextVisited = visited
        nextVisited.insert(folderId)

        let directPins = folderPinsByFolderId[folderId] ?? []
        let nestedPins = (childFoldersByParentId[folderId] ?? []).flatMap { childFolder in
            descendantShortcutPins(in: childFolder.id, visited: nextVisited)
        }
        return directPins + nestedPins
    }

    private var folderProjectionState: SidebarFolderProjectionState {
        windowState.sidebarFolderProjection(for: folder.id)
    }

    private func currentLiveFolderSource() -> SumiLiveFolderSource? {
        browserManager.liveFolderManager.source(for: folder.id)
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


    private var folderDragHighlightHorizontalBleed: CGFloat {
        8
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

    private var folderForegroundColor: Color {
        tokens.primaryText
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

        let iconForeground = stroke.mixed(with: folderForegroundColor, amount: 0.35)

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
            shortcutRestoreGaps: shortcutRestoreGaps
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
        folderHeaderRow(contentProjection: contentProjection, projection: projection)
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
                folderHeaderContextMenuEntries()
            }
        )
        .accessibilityIdentifier("folder-header-\(folder.id.uuidString)")
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.isOpen ? "expanded" : "collapsed")
    }

    private func folderHeaderRow(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        HStack(spacing: 0) {
            folderHeaderIconSlot(contentProjection: contentProjection, projection: projection)
            folderTitleView
            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .geometryGroup()
        .background(alignment: .center) {
            if isFolderDropHighlighted {
                RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous)
                    .fill(tokens.sidebarRowHover)
                    .padding(.horizontal, -folderDragHighlightHorizontalBleed)
            }
        }
        .sidebarRowSurface(
            background: displayIsHovering ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displayIsHovering,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
        .sidebarDDGHover($isFolderHeaderHovered, isEnabled: isInteractive)
    }

    private var folderTitleView: some View {
        Text(folder.name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(folderForegroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func folderIconView(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        SumiFolderGlyphView(
            presentation: folderGlyphPresentation(
                using: projection,
                contentProjection: contentProjection
            ),
            palette: folderShellPalette
        )
        .frame(
            width: SidebarRowLayout.folderGlyphSize,
            height: SidebarRowLayout.folderGlyphSize,
            alignment: .center
        )
    }

    /// Full-size Zen glyph; horizontal center matches favicon column, layout width matches tab rows (`folderTitleLeading`).
    private func folderHeaderIconSlot(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
            folderIconView(contentProjection: contentProjection, projection: projection)
                .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
        }
        .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)
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

    private func performShortcutHostedSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) {
        if SplitGroupSidebarModel.member(for: item, in: group)?.isShortcutBacked == true {
            onPerformShortcutRestoreWithPreparedGap(item, group) {
                performFolderSplitModelMutation {
                    browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
                }
            }
            return
        }

        guard let tab = item.tab else { return }
        performFolderSplitModelMutation {
            browserManager.closeTab(tab, in: windowState)
        }
    }

    private func performFolderSplitModelMutation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, update)
    }

    @ViewBuilder
    private func shortcutHostedSplitGroupView(
        _ group: SplitGroup,
        items: [SplitGroupSidebarItem]
    ) -> some View {
        if !items.isEmpty {
            SplitGroupSidebarRow(
                group: group,
                items: items,
                spaceId: space.id,
                isAppKitInteractionEnabled: isInteractive,
                segmentAction: { item in
                    SplitGroupSidebarModel.segmentAction(for: item, in: group)
                },
                dragSource: { item in
                    shortcutHostedSplitSegmentDragSource(for: item, in: group)
                },
                contextMenuEntries: { _ in [] },
                onActivate: { tab in
                    browserManager.requestUserTabActivation(tab, in: windowState)
                },
                onActivateGroup: {
                    browserManager.focusSplitGroup(group, in: windowState)
                },
                onSegmentActionAnimationStart: { item in
                    if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
                        onPrepareShortcutRestoreGap(item, group)
                    }
                },
                onSegmentAction: { item in
                    performShortcutHostedSegmentAction(for: item, in: group)
                }
            )
            .environmentObject(browserManager)
            .environmentObject(splitManager)
            .accessibilityIdentifier("folder-shortcut-host-split-row-\(group.id.uuidString)")
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SidebarDragSourceConfiguration? {
        let member = SplitGroupSidebarModel.member(for: item, in: group)
        if let pin = SplitGroupSidebarModel.shortcutPin(
            for: item,
            member: member,
            tabManager: browserManager.tabManager
        ) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: SplitGroupSidebarModel.sourceZone(for: pin, fallbackSpaceId: space.id),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: {
                    browserManager.focusSplitGroup(group, in: windowState)
                },
                isEnabled: isInteractive
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem(
                tabId: tab.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(space.id),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: {
                browserManager.requestUserTabActivation(tab, in: windowState)
            },
            isEnabled: isInteractive
        )
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
                accessibilityID: "folder-shortcut-\(pin.id.uuidString)",
                contextMenuEntries: {
                    folderShortcutContextMenuEntries(pin)
                },
                action: { activateShortcutPin(pin) },
                dragSourceZone: .folder(folder.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onResetToLaunchURL: { resetShortcutPin(pin) },
                onUnload: { unloadShortcutPin(pin) },
                onRemove: { removeShortcutPin(pin) }
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
                liveFolderItemContextMenuEntries(item)
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

    private func folderShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserManager.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: browserManager.tabManager.folders(for: space.id)
                .filter { !browserManager.liveFolderManager.isLiveFolder($0.id) },
            selectedFolderId: pin.folderId
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: browserManager.tabManager.spaces,
            selectedSpaceId: pin.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: browserManager.tabManager.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: space.id
            )
        )
        let addToEssentialsAction: (() -> Void)? = browserManager.tabManager.canAddURLToEssentials(
            pin.launchURL,
            using: .init(windowState: windowState, spaceId: space.id)
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions: SidebarSavedURLDriftActions? =
            browserManager.tabManager.shortcutHasDrifted(pin, in: windowState)
                ? .init(
                    onBackToSavedURL: { resetShortcutPin(pin) },
                    onUseCurrentPageAsSavedURL: { _ = browserManager.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                )
                : nil
        let unloadAction: (() -> Void)? = presentationState.isOpenLive
            ? { unloadShortcutPin(pin) }
            : nil
        let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
            moveShortcutPin(pin, toSpace: targetSpaceId)
        }

        return makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            actions: .init(
                duplicate: { duplicateShortcutPin(pin) },
                copyLink: { copyLink(pin.launchURL) },
                share: {
                    presentSharePicker(
                        for: pin.launchURL,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in moveShortcutPin(pin, toFolder: folderId) }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: moveToSpaceAction
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        browserManager.tabManager.assign(
                            shortcutPin: pin,
                            toExecutionProfile: profileId
                        )
                    }
                ),
                addToEssentials: addToEssentialsAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
        )
    }

    private func liveFolderItemContextMenuEntries(_ item: SumiLiveFolderItem) -> [SidebarContextMenuEntry] {
        guard let url = item.url else {
            return []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: "Open", systemImage: "arrow.up.right.square", classification: .presentationOnly) {
                        browserManager.liveFolderManager.open(item: item, in: windowState)
                    }),
                    .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly) {
                        copyLink(url)
                    }),
                    .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly) {
                        presentSharePicker(
                            for: url,
                            source: windowState.resolveSidebarPresentationSource()
                        )
                    }),
                ],
                [
                    .action(.init(title: "Hide Item", systemImage: "xmark", classification: .stateMutationNonStructural) {
                        browserManager.liveFolderManager.dismiss(item: item)
                    }),
                ],
            ]
        )
    }

    private func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        if currentLiveFolderSource() != nil {
            return liveFolderHeaderContextMenuEntries()
        }

        let unloadActiveTabsAction: (() -> Void)?
        if folderHasLiveSavedTabs {
            unloadActiveTabsAction = unloadActiveFolderTabs
        } else {
            unloadActiveTabsAction = nil
        }

        return makeFolderHeaderContextMenuEntries(
            actions: .init(
                edit: {
                    browserManager.showFolderEditor(
                        for: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                alphabetize: alphabetizeTabs,
                unloadActiveTabs: unloadActiveTabsAction,
                ungroup: onUngroup,
                delete: onDelete
            )
        )
    }

    private func liveFolderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        let source = currentLiveFolderSource()
        let statusTitle: String = {
            if let error = source?.lastErrorKind {
                return error.displayTitle
            }
            if let lastSuccessAt = source?.lastSuccessAt {
                return "Last Updated \(lastSuccessAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Not Updated Yet"
        }()

        let githubLoginSection: [SidebarContextMenuEntry]
        if source?.lastErrorKind == .notAuthenticated,
           source?.kind == .githubPullRequests || source?.kind == .githubIssues {
            githubLoginSection = [
                .action(.init(title: "Sign in to GitHub", systemImage: "person.crop.circle.badge.exclamationmark", classification: .presentationOnly) {
                    browserManager.openNewTab(
                        url: "https://github.com/login",
                        context: .foreground(windowState: windowState, preferredSpaceId: space.id)
                    )
                }),
            ]
        } else {
            githubLoginSection = []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: statusTitle, systemImage: "clock", isEnabled: false, classification: .presentationOnly) {}),
                    .action(.init(title: "Refresh Now", systemImage: "arrow.clockwise", classification: .stateMutationNonStructural) {
                        browserManager.liveFolderManager.refresh(folderId: folder.id)
                    }),
                    refreshIntervalSubmenu(for: source),
                ],
                githubLoginSection,
                [
                    .action(
                        .init(
                            title: "Delete Live Folder",
                            systemImage: "trash",
                            role: .destructive,
                            classification: .structuralMutation,
                            onAction: onDelete
                        )
                    ),
                ],
            ]
        )
    }

    private func refreshIntervalSubmenu(for source: SumiLiveFolderSource?) -> SidebarContextMenuEntry {
        let options: [(title: String, seconds: TimeInterval)] = [
            ("15 Minutes", 15 * 60),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("6 Hours", 6 * 60 * 60),
        ]
        let currentInterval = source?.refreshIntervalSeconds

        return .submenu(
            title: "Refresh Every",
            systemImage: "timer",
            children: options.map { option in
                .action(
                    .init(
                        title: option.title,
                        systemImage: nil,
                        isEnabled: currentInterval != option.seconds,
                        state: currentInterval == option.seconds ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserManager.liveFolderManager.setRefreshInterval(folderId: folder.id, seconds: option.seconds)
                    }
                )
            }
        )
    }

    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        browserManager.showShortcutEditor(
            for: pin,
            in: windowState,
            themeContext: themeContext,
            source: source ?? windowState.resolveSidebarPresentationSource()
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isFolderHeaderHovered,
            freezesHoverState: freezesHoverState
        )
    }

    private var folderHeaderSourceID: String {
        "folder-header-\(folder.id.uuidString)"
    }

    private func alphabetizeTabs() {
        withAnimation(folderLayoutAnimation) {
            browserManager.tabManager.alphabetizeFolderPins(folder.id, in: space.id)
        }
    }

    private func toggleFolderOpenState() {
        withAnimation(folderLayoutAnimation) {
            browserManager.tabManager.toggleFolderOpenState(folder.id)
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
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

    private func removeShortcutPin(_ pin: ShortcutPin) {
        mutateFolderContent {
            browserManager.tabManager.removeShortcutPin(pin)
        }
    }

    private func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.window,
            onDelete: { removeShortcutPin(pin) }
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

    private func unloadShortcutPin(_ pin: ShortcutPin) {
        if let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserManager.closeTab(current, in: windowState)
            return
        }

        browserManager.tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    private func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserManager.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserManager.tabManager.folder(by: folderId) else { return }
        let targetIndex = browserManager.tabManager.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutateFolderContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                index: targetIndex
            )
        }
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserManager.tabManager.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutateFolderContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: targetIndex
            )
        }
    }

    private func resetShortcutPin(_ pin: ShortcutPin) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let preserveCurrentPage = modifiers.contains(.command) || modifiers.contains(.control)
        _ = browserManager.tabManager.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    private func pinShortcutGlobally(_ pin: ShortcutPin) {
        let syntheticTab = Tab(
            url: pin.launchURL,
            name: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: space.id,
            index: 0,
            browserManager: browserManager
        )
        browserManager.tabManager.pinTab(
            syntheticTab,
            context: .init(windowState: windowState, spaceId: space.id)
        )
    }

    private var folderHasLiveSavedTabs: Bool {
        folderHasLiveSavedTabsHelper(folderId: folder.id)
    }

    private func folderHasLiveSavedTabsHelper(folderId: UUID) -> Bool {
        if let directPins = folderPinsByFolderId[folderId],
           directPins.contains(where: { browserManager.tabManager.shortcutLiveTab(for: $0.id, in: windowState.id) != nil }) {
            return true
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if folderHasLiveSavedTabsHelper(folderId: child.id) {
                    return true
                }
            }
        }
        return false
    }

    private func unloadActiveFolderTabs() {
        for pin in descendantShortcutPins {
            unloadShortcutPin(pin)
        }
    }

    private func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource? = nil
    ) {
        if let source {
            browserManager.presentSharingServicePicker([url], source: source)
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

}
