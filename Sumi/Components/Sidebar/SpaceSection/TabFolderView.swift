//
//  TabFolderView.swift
//  Sumi
//
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct TabFolderView: View {
    private enum FolderListItem: Hashable {
        case folder(UUID)
        case shortcut(UUID)
        case splitGroup(UUID)
        case restoreGap(UUID)
        case placeholder
    }

    private struct FolderDisplayEntry: Identifiable {
        let item: FolderListItem
        let dropIndex: Int
        let id: String
    }

    private static let folderContentLeadingPadding: CGFloat = 14
    private static let folderContentVerticalPadding: CGFloat = 4
    private static let zenFolderContentAnimation = Animation.easeInOut(duration: 0.18)

    @ObservedObject var folder: TabFolder
    let space: Space
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
    @Binding var shortcutRestoreGaps: [ShortcutRestoreGap]
    @Binding var shortcutRestoreGapHeights: [UUID: CGFloat]
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

    private var baseFolderItems: [FolderListItem] {
        sortedFolderItems(childFolders: childFolders, shortcutPins: shortcutPinsInFolder)
    }

    private func sortedFolderItems(childFolders: [TabFolder], shortcutPins: [ShortcutPin]) -> [FolderListItem] {
        let shortcutHostedGroups = browserManager.tabManager.shortcutHostedSplitGroups(
            for: space.id,
            inFolder: folder.id
        )
        let hiddenPinIds = browserManager.tabManager.shortcutHostedSplitHiddenPinIds(for: space.id)
        let folders = childFolders.map { ($0.index, 0, FolderListItem.folder($0.id)) }
        let pins = shortcutPins
            .filter { !hiddenPinIds.contains($0.id) }
            .map { ($0.index, 1, FolderListItem.shortcut($0.id)) }
        let splitGroups = shortcutHostedGroups
            .map { (browserManager.tabManager.shortcutHostedSplitGroupVisualIndex($0, in: space.id), 0, FolderListItem.splitGroup($0.id)) }
        return (folders + pins + splitGroups)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                switch (lhs.2, rhs.2) {
                case (.folder(let left), .folder(let right)),
                     (.shortcut(let left), .shortcut(let right)),
                     (.splitGroup(let left), .splitGroup(let right)):
                    return left.uuidString < right.uuidString
                case (.splitGroup, .folder), (.splitGroup, .shortcut),
                     (.folder, .shortcut):
                    return true
                case (.folder, .splitGroup), (.shortcut, .splitGroup),
                     (.shortcut, .folder):
                    return false
                case (.restoreGap, _), (_, .restoreGap),
                     (.placeholder, _), (_, .placeholder):
                    return false
                }
            }
            .map(\.2)
    }

    private var folderModelChildCount: Int {
        baseFolderItems.count
    }

    private var folderItems: [FolderListItem] {
        let baseItems = baseFolderItems
        var items = SidebarDropProjection.projectedItems(
            itemIDs: baseItems,
            removesSourceID: folderProjectedSourceItem(in: baseItems),
            insertsPlaceholderAt: folderProjectedInsertionIndex
        )
        .map { item in
            switch item {
            case .item(let folderItem):
                return folderItem
            case .placeholder:
                return .placeholder
            }
        }

        let gaps = shortcutRestoreGaps.filter { gap in
            gap.container == .folder(folder.id)
        }
        for gap in gaps.sorted(by: { $0.index < $1.index }) {
            items.removeAll { item in
                if case .shortcut(let pinId) = item {
                    return pinId == gap.pinId
                }
                return false
            }
            items.insert(.restoreGap(gap.id), at: max(0, min(gap.index, items.count)))
        }

        return items
    }


    private func folderProjectedSourceItem(in items: [FolderListItem]) -> FolderListItem? {
        guard dragState.isDropProjectionActive,
              dragState.projectionDragScope?.sourceContainer == .folder(folder.id),
              let projectionDragItemId = dragState.projectionDragItemId else {
            return nil
        }
        return items.first { item in
            switch item {
            case .folder(let id), .shortcut(let id), .splitGroup(let id):
                return id == projectionDragItemId
            case .restoreGap, .placeholder:
                return false
            }
        }
    }

    private var folderProjectedInsertionIndex: Int? {
        guard dragState.isDropProjectionActive,
              case .insertIntoFolder(let folderId, let index) = dragState.projectionFolderDropIntent,
              folderId == folder.id,
              folder.isOpen else {
            return nil
        }
        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .folder(folder.id),
                targetAlreadyContainsDraggedItem: baseFolderItems.contains { item in
                    switch item {
                    case .folder(let id), .shortcut(let id), .splitGroup(let id):
                        return id == projectionDragItemId
                    case .restoreGap, .placeholder:
                        return false
                    }
                }
           ) {
            return nil
        }
        return index
    }

    private var targetCollapsedProjectionPins: [ShortcutPin] {
        guard !folder.isOpen else { return [] }
        return collapsedProjectedShortcutPins(using: folderProjectionState.projectedChildIDs)
    }

    private var targetCollapsedProjectionIDs: [UUID] {
        targetCollapsedProjectionPins.map(\.id)
    }

    private var visibleCollapsedProjectionIDs: [UUID] {
        displayedCollapsedProjectionIDs.isEmpty
            ? targetCollapsedProjectionIDs
            : displayedCollapsedProjectionIDs
    }

    private var visibleFolderBodyItems: [FolderListItem] {
        folder.isOpen
            ? folderItems
            : visibleCollapsedProjectionIDs.map(FolderListItem.shortcut)
    }

    private var hasCollapsedProjectionForLayout: Bool {
        !displayedCollapsedProjectionIDs.isEmpty || !targetCollapsedProjectionIDs.isEmpty
    }

    private func collapsedProjectedShortcutPins(
        using projectedChildIDs: [UUID]
    ) -> [ShortcutPin] {
        let livePins = shortcutPinsInFolder.filter { pin in
            browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id) != nil
        }

        guard !projectedChildIDs.isEmpty else {
            return livePins.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        let projectedOrder = Dictionary(
            uniqueKeysWithValues: projectedChildIDs.enumerated().map { ($1, $0) }
        )
        return livePins.sorted { lhs, rhs in
            let leftOrder = projectedOrder[lhs.id] ?? lhs.index
            let rightOrder = projectedOrder[rhs.id] ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // Replaced by SidebarDragState
    private var isFolderContainTargeted: Bool {
        dragState.folderDropIntent == .contain(folderId: folder.id)
    }

    private var isFolderDropHighlighted: Bool {
        isFolderContainTargeted
    }

    private var folderPreviewIsOpen: Bool {
        folder.isOpen || isFolderDragOpenPreviewed
    }

    private var isFolderDragOpenPreviewed: Bool {
        dragState.isDragging
            && !folder.isOpen
            && dragState.activeHoveredFolderId == folder.id
    }

    private var resolvedTopLevelPinnedIndex: Int {
        containerIndex
    }


    private var folderDragHighlightHorizontalBleed: CGFloat {
        8
    }

    private var isTopLevelPinnedFolder: Bool {
        parentFolderId == nil
    }

    private var folderBodyShouldRender: Bool {
        folder.isOpen || hasCollapsedProjectionForLayout
    }

    private var folderBodyGeometryIsActive: Bool {
        isInteractive && folderBodyShouldRender
    }

    private var folderLayoutAnimation: Animation? {
        isInteractive && !reduceMotion && !sumiSettings.shouldReduceChromeMotion && !dragState.isCompletingDrop
            ? Self.zenFolderContentAnimation
            : nil
    }

    private var folderHasActiveSelection: Bool {
        if let currentShortcutPinId = windowState.currentShortcutPinId,
           descendantShortcutPins.contains(where: { $0.id == currentShortcutPinId }) {
            return true
        }

        guard let currentTabId = windowState.currentTabId else { return false }
        return descendantShortcutPins.contains { pin in
            browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)?.id == currentTabId
        }
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
        let _ = browserManager.tabStructuralRevision

        folderCompositeContent
            .transaction { transaction in
                if dragState.isCompletingDrop {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: targetCollapsedProjectionIDs) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: folder.isOpen) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: windowState.currentTabId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: windowState.currentShortcutPinId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onAppear {
                syncDisplayedCollapsedProjectionIDs(animated: false)
                scheduleProjectionStateRefresh()
            }
    }

    private var folderCompositeContent: some View {
        VStack(spacing: 0) {
            folderHeader
            folderBodyContainer
        }
        .background(alignment: .bottom) {
            folderAfterDropTarget
        }
    }

    @ViewBuilder
    private var folderBodyContainer: some View {
        folderBodyAnimatedContent
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: folderModelChildCount,
                isOpen: folder.isOpen,
                region: .body,
                generation: dragState.sidebarGeometryGeneration,
                isActive: folderBodyGeometryIsActive
            )
    }

    @ViewBuilder
    private var folderBodyAnimatedContent: some View {
        if folderBodyShouldRender {
            folderBodyVisibleContent
                .transition(.opacity)
                .animation(folderLayoutAnimation, value: folder.isOpen)
                .animation(folderLayoutAnimation, value: folderItems)
                .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
                .animation(folderLayoutAnimation, value: targetCollapsedProjectionIDs)
        } else {
            Color.clear
                .frame(height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var folderBodyVisibleContent: some View {
        folderBodyContent(
            items: visibleFolderBodyItems,
            reportsGeometry: true,
            reportsFolderChildGeometry: folder.isOpen
        )
        .allowsHitTesting(folder.isOpen || !visibleCollapsedProjectionIDs.isEmpty)
        .animation(folderLayoutAnimation, value: folder.isOpen)
        .animation(folderLayoutAnimation, value: visibleFolderBodyItems)
        .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
        .animation(folderLayoutAnimation, value: targetCollapsedProjectionIDs)
    }

    @ViewBuilder
    private var folderAfterDropTarget: some View {
        let height = dragState.isDragging ? SidebarRowLayout.rowHeight * 0.45 : 0
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
                childCount: folderModelChildCount,
                isOpen: folder.isOpen,
                region: .after,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive && height > 0
            )
            .allowsHitTesting(false)
    }


    private var folderHeader: some View {
        folderHeaderRow
        .sidebarFolderDropGeometry(
            folderId: folder.id,
            spaceId: space.id,
            parentFolderId: parentFolderId,
            topLevelIndex: resolvedTopLevelPinnedIndex,
            childCount: folderModelChildCount,
            isOpen: folder.isOpen,
            region: .header,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .sidebarAppKitContextMenu(
            isEnabled: true,
            isInteractionEnabled: isInteractive,
            dragSource: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(folderId: folder.id, title: folder.name),
                sourceZone: parentFolderId.map(DropZoneID.folder) ?? .spacePinned(space.id),
                previewKind: .folderRow,
                pinnedConfig: .large,
                folderGlyphPresentation: folderGlyphPresentation,
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
        .accessibilityValue(folder.isOpen ? "expanded" : "collapsed")
    }

    private var folderHeaderRow: some View {
        HStack(spacing: 0) {
            folderHeaderIconSlot
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

    private var folderIconView: some View {
        SumiFolderGlyphView(
            presentation: folderGlyphPresentation,
            palette: folderShellPalette
        )
        .frame(
            width: SidebarRowLayout.folderGlyphSize,
            height: SidebarRowLayout.folderGlyphSize,
            alignment: .center
        )
    }

    /// Full-size Zen glyph; horizontal center matches favicon column, layout width matches tab rows (`folderTitleLeading`).
    private var folderHeaderIconSlot: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
            folderIconView
                .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
        }
        .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)
    }

    private func folderBodyContent(
        items: [FolderListItem],
        reportsGeometry: Bool,
        reportsFolderChildGeometry: Bool
    ) -> some View {
        return LazyVStack(spacing: 0) {
            ForEach(folderDisplayEntries(from: items)) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .folder(let folderId):
                        if let childFolder = childFolders.first(where: { $0.id == folderId }) {
                            nestedFolderView(childFolder, containerIndex: entry.dropIndex)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: childFolder.id,
                                    index: entry.dropIndex,
                                    generation: dragState.sidebarGeometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .shortcut(let pinId):
                        if let pin = shortcutPinsInFolder.first(where: { $0.id == pinId }) {
                            folderShortcutView(pin)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: pin.id,
                                    index: entry.dropIndex,
                                    generation: dragState.sidebarGeometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .splitGroup(let groupId):
                        if let group = browserManager.tabManager.splitGroup(with: groupId) {
                            shortcutHostedSplitGroupView(group)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: group.id,
                                    index: entry.dropIndex,
                                    generation: dragState.sidebarGeometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .restoreGap(let gapId):
                        shortcutRestoreGap(gapId)
                    case .placeholder:
                        folderDropGap
                    }
                }
                .zIndex(folderDisplayEntryZIndex(entry))
            }
        }
        .padding(.leading, Self.folderContentLeadingPadding)
        .padding(.vertical, Self.folderContentVerticalPadding)
        .background(alignment: .leading) {
            folderNestingGuide(isVisible: !items.isEmpty)
        }
        .animation(folderLayoutAnimation, value: items)
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
            shortcutRestoreGapHeights: $shortcutRestoreGapHeights,
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

    private func folderDisplayEntries(from items: [FolderListItem]) -> [FolderDisplayEntry] {
        var childCount = 0
        return items.map { item in
            let entry = FolderDisplayEntry(
                item: item,
                dropIndex: childCount,
                id: folderDisplayID(for: item, placeholderIndex: childCount)
            )
            switch item {
            case .folder, .shortcut, .splitGroup:
                childCount += 1
            case .restoreGap, .placeholder:
                break
            }
            return entry
        }
    }

    private func folderDisplayEntryZIndex(_ entry: FolderDisplayEntry) -> Double {
        SidebarSelectionElevation.zIndex(isElevated: folderListItemIsElevated(entry.item))
    }

    private func folderListItemIsElevated(_ item: FolderListItem) -> Bool {
        switch item {
        case .folder(let folderId):
            return folderContainsElevatedSelection(folderId)
        case .shortcut(let pinId):
            guard let pin = shortcutPinsInFolder.first(where: { $0.id == pinId }) else {
                return false
            }
            if let placeholderGroup = browserManager.tabManager.regularHostedSplitPlaceholderGroup(for: pin) {
                return isFolderSplitPlaceholderSelected(placeholderGroup, pin: pin)
            }
            return shortcutPinIsElevated(pin)
        case .splitGroup(let groupId):
            guard let group = browserManager.tabManager.splitGroup(with: groupId) else {
                return false
            }
            return splitGroupIsElevated(group)
        case .restoreGap, .placeholder:
            return false
        }
    }

    private func shortcutPinIsElevated(_ pin: ShortcutPin) -> Bool {
        browserManager.tabManager.shortcutRuntimeAffordanceState(for: pin, in: windowState).isSelected
    }

    private func splitGroupIsElevated(_ group: SplitGroup) -> Bool {
        SidebarSelectionElevation.splitGroupContainsCurrentTab(
            group,
            currentTabId: windowState.currentTabId
        )
    }

    private func folderContainsElevatedSelection(_ folderId: UUID, visited: Set<UUID> = []) -> Bool {
        SidebarSelectionElevation.folderContainsSelection(
            folderId: folderId,
            visited: visited,
            folderPins: { folderPinsByFolderId[$0] ?? [] },
            childFolders: { childFoldersByParentId[$0] ?? [] },
            splitGroups: {
                browserManager.tabManager.shortcutHostedSplitGroups(
                    for: space.id,
                    inFolder: $0
                )
            },
            isShortcutElevated: shortcutPinIsElevated,
            isSplitGroupElevated: splitGroupIsElevated
        )
    }

    private func folderDisplayID(
        for item: FolderListItem,
        placeholderIndex: Int
    ) -> String {
        switch item {
        case .folder(let id):
            return "folder-\(id.uuidString)"
        case .shortcut(let id):
            return "item-\(id.uuidString)"
        case .splitGroup(let id):
            return "split-group-\(id.uuidString)"
        case .restoreGap(let id):
            if let gap = shortcutRestoreGaps.first(where: { $0.id == id }) {
                return "item-\(gap.pinId.uuidString)"
            }
            return "restore-gap-\(id.uuidString)"
        case .placeholder:
            if let projectionDragItemId = dragState.projectionDragItemId {
                return "item-\(projectionDragItemId.uuidString)"
            }
            return "placeholder-\(placeholderIndex)"
        }
    }

    private var folderDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .accessibilityHidden(true)
    }

    private func shortcutRestoreGap(_ gapId: UUID) -> some View {
        let height = shortcutRestoreGapHeights[gapId] ?? 0
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }),
               let pin = browserManager.tabManager.shortcutPin(by: gap.pinId) {
                folderShortcutView(pin)
                    .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
            }
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(folderLayoutAnimation, value: height)
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
    private func shortcutHostedSplitGroupView(_ group: SplitGroup) -> some View {
        let items = SplitGroupSidebarModel.items(for: group, tabManager: browserManager.tabManager)
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
    private func folderShortcutView(_ pin: ShortcutPin) -> some View {
        if let placeholderGroup = browserManager.tabManager.regularHostedSplitPlaceholderGroup(for: pin) {
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
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
        } else {
            ShortcutSidebarRow(
                pin: pin,
                liveTab: browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id),
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
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
        }
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
            folders: browserManager.tabManager.folders(for: space.id),
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

    private func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
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
        withAnimation(Self.zenFolderContentAnimation) {
            browserManager.tabManager.alphabetizeFolderPins(folder.id, in: space.id)
        }
    }

    private func toggleFolderOpenState() {
        withAnimation(Self.zenFolderContentAnimation) {
            browserManager.tabManager.toggleFolderOpenState(folder.id)
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
    }

    private var folderGlyphPresentation: SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: folder.icon,
            isOpen: folderPreviewIsOpen,
            hasActiveProjection: folderHasProjectedContent
        )
    }

    private var folderHasCustomIcon: Bool {
        folderGlyphPresentation.bundledIconName != nil
    }

    private var folderHasProjectedContent: Bool {
        folderProjectionState.hasActiveProjection || folderHasActiveSelection || hasCollapsedProjectionForLayout
    }

    private func scheduleProjectionStateRefresh() {
        let projectedIDs = collapsedProjectedShortcutPins(
            using: folderProjectionState.projectedChildIDs
        ).map(\.id)
        let newHasActiveProjection = folderHasActiveSelection || !projectedIDs.isEmpty
        windowState.scheduleSidebarFolderProjectionUpdate(
            for: folder.id,
            projectedChildIDs: projectedIDs,
            hasActiveProjection: newHasActiveProjection
        )
    }

    private func syncDisplayedCollapsedProjectionIDs(animated: Bool) {
        let targetIDs = targetCollapsedProjectionIDs
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated && isInteractive && !dragState.isCompletingDrop {
            withAnimation(Self.zenFolderContentAnimation, update)
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

    private func closeShortcutPinIfActive(_ pin: ShortcutPin) {
        guard let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState)
        else { return }
        browserManager.closeTab(current, in: windowState)
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
        descendantShortcutPins.contains { pin in
            browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id) != nil
        }
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
struct SumiFolderGlyphPalette {
    let backFill: Color
    let frontFill: Color
    let stroke: Color
    let iconForeground: Color
    let backOverlayTop: Color
    let backOverlayBottom: Color
    let frontOverlayTop: Color
    let frontOverlayBottom: Color
}

enum SumiFolderGlyphShellState: Equatable {
    case closed
    case open
}

struct SumiFolderGlyphPresentationState: Equatable {
    let shellState: SumiFolderGlyphShellState
    let isActive: Bool
    let bundledIconName: String?

    init(iconValue: String?, isOpen: Bool, hasActiveProjection: Bool) {
        shellState = isOpen ? .open : .closed
        isActive = !isOpen && hasActiveProjection

        switch SumiZenFolderIconCatalog.resolveFolderIcon(iconValue) {
        case .bundled(let name):
            bundledIconName = name
        case .none:
            bundledIconName = nil
        }
    }

    var isOpen: Bool {
        shellState == .open
    }

    var showsDots: Bool {
        isActive
    }

    var showsCustomIcon: Bool {
        bundledIconName != nil && !showsDots
    }
}

struct SumiFolderGlyphView: View {
    private static let shellAnimation = Animation.easeInOut(duration: 0.16)

    let presentation: SumiFolderGlyphPresentationState
    let palette: SumiFolderGlyphPalette

    @State private var renderedShellIsOpen: Bool?

    var body: some View {
        GeometryReader { geometry in
            let shellIsOpen = renderedShellIsOpen ?? presentation.isOpen
            let unitScale = min(
                geometry.size.width / SumiFolderGlyphMetrics.canvasDimension,
                geometry.size.height / SumiFolderGlyphMetrics.canvasDimension
            )
            let canvasSize = SumiFolderGlyphMetrics.canvasDimension * unitScale
            let originX = ((geometry.size.width - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.width * unitScale)
            let originY = ((geometry.size.height - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.height * unitScale)

            ZStack(alignment: .topLeading) {
                canvasLayer(scale: unitScale) {
                    backLayer(scale: unitScale)
                }
                .modifier(backTransform(scale: unitScale, isOpen: shellIsOpen))

                canvasLayer(scale: unitScale) {
                    frontLayer(scale: unitScale)
                }
                .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))

                if presentation.showsCustomIcon {
                    canvasLayer(scale: unitScale) {
                        iconLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }

                if presentation.showsDots {
                    canvasLayer(scale: unitScale) {
                        dotsLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }
            }
            .frame(width: canvasSize, height: canvasSize, alignment: .topLeading)
            .offset(x: originX, y: originY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contrast(1.25)
        .onAppear {
            renderedShellIsOpen = presentation.isOpen
        }
        .onChange(of: presentation.isOpen) { _, isOpen in
            updateRenderedShellState(isOpen)
        }
    }

    private func canvasLayer<Content: View>(
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()
        }
        .frame(
            width: SumiFolderGlyphMetrics.canvasDimension * scale,
            height: SumiFolderGlyphMetrics.canvasDimension * scale,
            alignment: .topLeading
        )
    }

    private func backLayer(scale: CGFloat) -> some View {
        ZStack {
            SumiFolderBackShape()
                .fill(palette.backFill)

            SumiFolderBackShape()
                .fill(
                    LinearGradient(
                        colors: [palette.backOverlayTop, palette.backOverlayBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            SumiFolderBackShape()
                .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
    }

    private func frontLayer(scale: CGFloat) -> some View {
        let size = SumiFolderGlyphMetrics.frontSize.scaled(by: scale)
        let origin = SumiFolderGlyphMetrics.frontOrigin.scaled(by: scale)

        return ZStack {
            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(palette.frontFill)

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [palette.frontOverlayTop, palette.frontOverlayBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: origin.x, y: origin.y)
    }

    private func iconLayer(scale: CGFloat) -> some View {
        let iconSize = SumiFolderGlyphMetrics.iconDimension * scale
        let iconOrigin = SumiFolderGlyphMetrics.iconOrigin.scaled(by: scale)

        return Group {
            if let bundledIconName = presentation.bundledIconName {
                SumiZenBundledIconView(
                    image: SumiZenFolderIconCatalog.bundledFolderImage(named: bundledIconName),
                    size: iconSize,
                    tint: palette.iconForeground.opacity(0.96)
                )
                .frame(width: iconSize, height: iconSize)
                .offset(x: iconOrigin.x, y: iconOrigin.y)
            }
        }
    }

    private func dotsLayer(scale: CGFloat) -> some View {
        let dotSize = SumiFolderGlyphMetrics.dotDiameter * scale

        return ZStack(alignment: .topLeading) {
            ForEach(Array(SumiFolderGlyphMetrics.dotCenters.enumerated()), id: \.offset) { _, center in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .offset(
                        x: (center.x - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale,
                        y: (center.y - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale
                    )
            }
        }
        .foregroundStyle(palette.iconForeground.opacity(0.94))
    }

    private func backTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.backOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func frontTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? -SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.frontOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func updateRenderedShellState(_ isOpen: Bool) {
        let update = {
            renderedShellIsOpen = isOpen
        }

        withAnimation(Self.shellAnimation, update)
    }

    private func elementTransform(
        xDegrees: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        unitScale: CGFloat
    ) -> SumiFolderElementTransform {
        SumiFolderElementTransform(
            xDegrees: xDegrees,
            scale: scale,
            offset: CGSize(width: offset.width * unitScale, height: offset.height * unitScale)
        )
    }
}

private enum SumiFolderGlyphMetrics {
    static let canvasDimension: CGFloat = 27
    static let baseOffset = CGSize(width: -1, height: -1)
    static let openSkewDegrees: CGFloat = 16
    static let openScale: CGFloat = 0.85
    static let backOpenOffset = CGSize(width: -4, height: 2)
    static let frontOpenOffset = CGSize(width: 8, height: 2)
    static let frontOrigin = CGPoint(x: 5.625, y: 9.625)
    static let frontSize = CGSize(width: 16.75, height: 12.75)
    static let frontCornerRadius: CGFloat = 2.375
    static let iconOrigin = CGPoint(x: 8.5, y: 10.5)
    static let iconDimension: CGFloat = 11
    static let dotDiameter: CGFloat = 2.5
    static let dotCenters: [CGPoint] = [
        CGPoint(x: 10, y: 16),
        CGPoint(x: 14, y: 16),
        CGPoint(x: 18, y: 16),
    ]
}

private struct SumiFolderElementTransform: ViewModifier {
    let xDegrees: CGFloat
    let scale: CGFloat
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .modifier(SkewEffect(xDegrees: xDegrees))
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height)
    }
}

private extension CGPoint {
    func scaled(by scale: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}

private struct SumiFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 27
        let sy = rect.height / 27

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }

        var path = Path()
        path.move(to: point(8, 5.625))
        path.addLine(to: point(11.9473, 5.625))
        path.addLine(to: point(13.4316, 6.14551))
        path.addLine(to: point(14.2881, 6.83105))
        path.addLine(to: point(16.5527, 7.625))
        path.addLine(to: point(20, 7.625))
        path.addQuadCurve(to: point(22.375, 10), control: point(22.375, 7.625))
        path.addLine(to: point(22.375, 20))
        path.addQuadCurve(to: point(20, 22.375), control: point(22.375, 22.375))
        path.addLine(to: point(8, 22.375))
        path.addQuadCurve(to: point(5.625, 20), control: point(5.625, 22.375))
        path.addLine(to: point(5.625, 8))
        path.addQuadCurve(to: point(8, 5.625), control: point(5.625, 5.625))
        path.closeSubpath()
        return path
    }
}

private struct SkewEffect: GeometryEffect {
    var xDegrees: CGFloat

    var animatableData: CGFloat {
        get { xDegrees }
        set { xDegrees = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CGAffineTransform.identity
        transform.c = tan(xDegrees * .pi / 180)
        return ProjectionTransform(transform)
    }
}
