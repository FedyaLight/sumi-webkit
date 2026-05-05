//
//      PinnedGrid.swift
//      Sumi
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SidebarEssentialsProjectedRow {
    let items: [ShortcutPin?]
    let startSlot: Int
    let visualColumnCount: Int
    let tileSize: CGSize
}

struct SidebarEssentialsProjectedLayout {
    let layoutItems: [ShortcutPin?]
    let visibleItems: [ShortcutPin?]
    let capacityColumnCount: Int
    let tileSize: CGSize
    let rows: [SidebarEssentialsProjectedRow]
    let visibleRows: [SidebarEssentialsProjectedRow]
    let canAcceptDrop: Bool

    var columnCount: Int {
        capacityColumnCount
    }

    var projectedItemCount: Int {
        layoutItems.count
    }

    var visibleItemCount: Int {
        visibleItems.count
    }

    var visibleRowCount: Int {
        visibleRows.count
    }

    var visualColumnSignature: [Int] {
        rows.map(\.visualColumnCount)
    }
}

private enum SidebarEssentialsDisplayCell {
    case pin(ShortcutPin)
    case ghost
    case spacer
}

private struct SidebarEssentialsDisplayRow {
    let cells: [SidebarEssentialsDisplayCell]
    let tileSize: CGSize
    let startSlot: Int
}

@MainActor
enum SidebarEssentialsProjectionPolicy {
    static let maxColumns = TabManager.EssentialsCapacityPolicy.maxColumns
    static let maxRows = TabManager.EssentialsCapacityPolicy.maxRows
    static let maxItems = maxColumns * maxRows

    static func make(
        items: [ShortcutPin],
        width: CGFloat,
        configuration: PinnedTabsConfiguration,
        dragState: SidebarDragState
    ) -> SidebarEssentialsProjectedLayout {
        let baseVisibleItems = resolvedVisibleItems(
            from: items,
            dragState: dragState
        )
        let canAcceptDrop = baseVisibleItems.count < maxItems
        let layoutItems = resolvedLayoutItems(
            from: baseVisibleItems,
            dragState: dragState,
            canAcceptDrop: canAcceptDrop,
            essentialsStoreIsEmpty: items.isEmpty
        )
        let capacityColumnCount = resolvedCapacityColumnCount(
            for: width,
            configuration: configuration
        )
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: capacityColumnCount,
            configuration: configuration
        )
        let tileSize = CGSize(width: tileWidth, height: configuration.height)

        return SidebarEssentialsProjectedLayout(
            layoutItems: layoutItems,
            visibleItems: baseVisibleItems,
            capacityColumnCount: capacityColumnCount,
            tileSize: tileSize,
            rows: projectedRows(
                from: layoutItems,
                capacityColumnCount: capacityColumnCount,
                width: width,
                configuration: configuration
            ),
            visibleRows: projectedRows(
                from: baseVisibleItems,
                capacityColumnCount: capacityColumnCount,
                width: width,
                configuration: configuration
            ),
            canAcceptDrop: canAcceptDrop
        )
    }

    static func projectedCountAfterDrop(
        itemIDs: [UUID],
        visibleItemCount: Int,
        layoutItemCount: Int,
        canAcceptDrop: Bool,
        dragState: SidebarDragState
    ) -> Int {
        let safeVisibleItemCount = max(visibleItemCount, 0)
        guard canAcceptDrop else { return min(safeVisibleItemCount, maxItems) }

        let isDraggingExistingEssential = dragState.activeDragItemId.map { itemIDs.contains($0) } ?? false
        let isHoveringEssentials = {
            guard dragState.isDragging,
                  case .essentials = dragState.hoveredSlot,
                  dragState.previewAssets[.essentialsTile] != nil else {
                return false
            }
            return true
        }()

        let emptyStorePlaceholderActive = dragState.isDragging
            && canAcceptDrop
            && itemIDs.isEmpty
            && safeVisibleItemCount == 0

        if isHoveringEssentials || emptyStorePlaceholderActive {
            let floorCount = emptyStorePlaceholderActive ? 1 : 0
            return min(max(max(layoutItemCount, safeVisibleItemCount), floorCount), maxItems)
        }

        if isDraggingExistingEssential {
            return min(safeVisibleItemCount, maxItems)
        }

        return min(safeVisibleItemCount + 1, maxItems)
    }

    static func neededRowCountAfterDrop(
        itemIDs: [UUID],
        visibleItemCount: Int,
        layoutItemCount: Int,
        columnCount: Int,
        canAcceptDrop: Bool,
        dragState: SidebarDragState
    ) -> Int {
        let projectedCount = projectedCountAfterDrop(
            itemIDs: itemIDs,
            visibleItemCount: visibleItemCount,
            layoutItemCount: layoutItemCount,
            canAcceptDrop: canAcceptDrop,
            dragState: dragState
        )
        let safeColumnCount = max(columnCount, 1)
        return min(
            maxRows,
            max(1, Int(ceil(Double(max(projectedCount, 1)) / Double(safeColumnCount))))
        )
    }

    private static func resolvedVisibleItems(
        from items: [ShortcutPin],
        dragState: SidebarDragState
    ) -> [ShortcutPin?] {
        guard let activeDragItemId = dragState.activeDragItemId else {
            return items.map { Optional($0) }
        }

        let isReorderingInsideEssentials: Bool = {
            guard dragState.isDragging,
                  case .essentials = dragState.hoveredSlot,
                  dragState.previewAssets[.essentialsTile] != nil else {
                return false
            }
            return true
        }()

        return items.compactMap { item -> ShortcutPin? in
            if item.id == activeDragItemId, isReorderingInsideEssentials {
                return nil
            }
            return item
        }
    }

    private static func resolvedLayoutItems(
        from items: [ShortcutPin?],
        dragState: SidebarDragState,
        canAcceptDrop: Bool,
        essentialsStoreIsEmpty: Bool
    ) -> [ShortcutPin?] {
        var layoutItems = items

        guard dragState.isDragging, canAcceptDrop else {
            return layoutItems
        }

        if essentialsStoreIsEmpty {
            if layoutItems.isEmpty {
                return [nil]
            }
            return layoutItems
        }

        guard case .essentials(let slot) = dragState.hoveredSlot,
              dragState.previewAssets[.essentialsTile] != nil else {
            return layoutItems
        }

        let safeSlot = max(0, min(slot, layoutItems.count))
        layoutItems.insert(nil, at: safeSlot)
        return layoutItems
    }

    private static func resolvedCapacityColumnCount(
        for width: CGFloat,
        configuration: PinnedTabsConfiguration
    ) -> Int {
        guard width > 0 else { return 1 }

        var columns = maxColumns
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

    static func visualTileSize(
        width: CGFloat,
        visualColumnCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> CGSize {
        let tileWidth = resolvedTileWidth(
            width: width,
            columnCount: visualColumnCount,
            configuration: configuration
        )
        return CGSize(width: tileWidth, height: configuration.height)
    }

    private static func resolvedTileWidth(
        width: CGFloat,
        columnCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> CGFloat {
        let columns = max(columnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * configuration.gridSpacing), 0)
        return max(availableWidth / CGFloat(columns), configuration.minWidth)
    }

    static func projectedRows(
        from items: [ShortcutPin?],
        capacityColumnCount: Int,
        width: CGFloat,
        configuration: PinnedTabsConfiguration
    ) -> [SidebarEssentialsProjectedRow] {
        guard !items.isEmpty else { return [] }
        let safeCapacityColumnCount = max(capacityColumnCount, 1)

        return stride(from: 0, to: items.count, by: safeCapacityColumnCount).map { index in
            let rowItems = Array(items[index..<min(index + safeCapacityColumnCount, items.count)])
            let visualColumnCount = max(1, min(rowItems.count, safeCapacityColumnCount))
            let tileSize = visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount,
                configuration: configuration
            )

            return SidebarEssentialsProjectedRow(
                items: rowItems,
                startSlot: index,
                visualColumnCount: visualColumnCount,
                tileSize: tileSize
            )
        }
    }
}

struct PinnedGrid: View {
    private static let collapsedRevealHeight: CGFloat = 6

    let width: CGFloat
    let spaceId: UUID?
    let profileId: UUID?
    let animateLayout: Bool
    let reportsGeometry: Bool
    let isAppKitInteractionEnabled: Bool


    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    init(
        width: CGFloat,
        spaceId: UUID? = nil,
        profileId: UUID? = nil,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isAppKitInteractionEnabled: Bool = true
    ) {
        self.width = width
        self.spaceId = spaceId
        self.profileId = profileId
        self.animateLayout = animateLayout
        self.reportsGeometry = reportsGeometry
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
    }

    var body: some View {
        let _ = browserManager.tabStructuralRevision

        let pinnedTabsConfiguration: PinnedTabsConfiguration = .large
        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
        let items: [ShortcutPin] = effectiveProfileId != nil
            ? browserManager.tabManager.essentialPins(for: effectiveProfileId)
            : []
        let projectedLayout = SidebarEssentialsProjectionPolicy.make(
            items: items,
            width: width,
            configuration: pinnedTabsConfiguration,
            dragState: dragState
        )
        let rawPreviewState = dragState.essentialsPreviewState(for: geometrySpaceId)
        let reportsDetailedGeometry = reportsGeometry
            && dragState.shouldCollectDetailedGeometry(
                spaceId: geometrySpaceId,
                profileId: effectiveProfileId
            )
        let shouldAnimate = animateLayout
            && (windowRegistry.activeWindow?.id == windowState.id)
            && !browserManager.isTransitioningProfile

        let showsRevealGhost = items.isEmpty
            && dragState.isDragging
            && projectedLayout.canAcceptDrop
        let revealTileSize = projectedLayout.rows.first?.tileSize ?? projectedLayout.tileSize
        let revealHeight = showsRevealGhost
            ? revealTileSize.height
            : Self.collapsedRevealHeight
        let visibleRowCount = max(projectedLayout.visibleRowCount, items.isEmpty ? 0 : 1)
        let maxDropRowCount = items.isEmpty
            ? 1
            : SidebarEssentialsProjectionPolicy.neededRowCountAfterDrop(
                itemIDs: items.map(\.id),
                visibleItemCount: projectedLayout.visibleItemCount,
                layoutItemCount: projectedLayout.projectedItemCount,
                columnCount: projectedLayout.columnCount,
                canAcceptDrop: projectedLayout.canAcceptDrop,
                dragState: dragState
            )
        let dropFrame = items.isEmpty
            ? CGRect(x: 0, y: 0, width: width, height: revealHeight)
            : resolvedDropFrame(
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                tileSize: projectedLayout.tileSize,
                gridSpacing: pinnedTabsConfiguration.gridSpacing,
                visibleHeight: projectedContentHeight(for: projectedLayout, configuration: pinnedTabsConfiguration)
            )
        let previewState = rawPreviewState.flatMap {
            resolvedPreviewState(
                $0,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount
            )
        }
        let displayRows = resolvedDisplayRows(
            for: projectedLayout,
            previewState: previewState,
            maxDropRowCount: maxDropRowCount,
            configuration: pinnedTabsConfiguration
        )
        let dropSlotFrames = resolvedDropSlotFrames(
            for: projectedLayout,
            revealTileSize: revealTileSize,
            maxDropRowCount: maxDropRowCount,
            configuration: pinnedTabsConfiguration
        )

        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                VStack(spacing: 0) {
                    if showsRevealGhost {
                        Group {
                            if essentialsEmptyDropShowsLivePreview {
                                renderGhostPlaceholder(
                                    tileSize: revealTileSize
                                )
                            } else {
                                SidebarEssentialsEmptyDropDashPlaceholder(size: revealTileSize)
                            }
                        }
                        .animation(
                            shouldAnimate ? .easeInOut(duration: 0.2) : nil,
                            value: essentialsEmptyDropShowsLivePreview
                        )
                    } else {
                        Color.clear
                            .frame(height: Self.collapsedRevealHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: revealHeight, alignment: .top)
            } else {
                VStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                    ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                switch cell {
                                case .pin(let pin):
                                    renderTile(
                                        for: pin,
                                        configuration: pinnedTabsConfiguration,
                                        tileSize: row.tileSize
                                    )
                                case .ghost:
                                    renderGhostPlaceholder(
                                        tileSize: row.tileSize
                                    )
                                case .spacer:
                                    Color.clear
                                        .frame(width: row.tileSize.width, height: row.tileSize.height)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
                .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: projectedLayout.visualColumnSignature)
                .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: projectedLayout.projectedItemCount)
                .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: previewState?.expandedDropRowCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: items.isEmpty ? revealHeight : 0, alignment: .top)
        .sidebarSectionGeometry(
            for: .essentials,
            spaceId: geometrySpaceId,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: reportsGeometry
        )
        .sidebarEssentialsLayoutGeometry(
            spaceId: geometrySpaceId,
            profileId: effectiveProfileId,
            itemCount: projectedLayout.projectedItemCount,
            columnCount: projectedLayout.columnCount,
            firstSyntheticRowSlot: max(visibleRowCount, 1) * max(projectedLayout.capacityColumnCount, 1),
            rowCount: max(displayRows.count, 1),
            visibleItemCount: projectedLayout.visibleItemCount,
            visibleRowCount: visibleRowCount,
            maxDropRowCount: maxDropRowCount,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemSize: projectedLayout.tileSize,
            gridSpacing: pinnedTabsConfiguration.gridSpacing,
            canAcceptDrop: projectedLayout.canAcceptDrop,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: reportsDetailedGeometry
        )
        .allowsHitTesting(!browserManager.isTransitioningProfile)
    }

    @ViewBuilder
    private func renderTile(
        for pin: ShortcutPin,
        configuration: PinnedTabsConfiguration,
        tileSize: CGSize
    ) -> some View {
        let presentationState = pinPresentationState(pin)
        let liveTab = browserManager.tabManager.shortcutLiveTab(
            for: pin.id,
            in: windowState.id
        )

        PinnedTile(
            pin: pin,
            presentationState: presentationState,
            liveTab: liveTab,
            essentialRuntimeState: essentialRuntimeState(pin),
            accessibilityID: "essential-shortcut-\(pin.id.uuidString)",
            onActivate: { activate(pin) },
            onClose: { closeIfActive(pin) },
            onUnload: { unload(pin) },
            onRemovePin: { browserManager.tabManager.removeFromEssentials(pin) },
            onUnpinToRegular: { moveToRegularTabs(pin) },
            onSplitRight: { openInSplit(pin, side: .right) },
            onSplitLeft: { openInSplit(pin, side: .left) },
            showsCloseAction: presentationState.isSelected,
            dragPinnedConfiguration: configuration,
            dragIsEnabled: !browserManager.isTransitioningProfile && isAppKitInteractionEnabled,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled
        )
        .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == pin.id
                ? 0.001
                : 1
        )
        .environmentObject(browserManager)
    }

    @ViewBuilder
    private func renderGhostPlaceholder(
        tileSize: CGSize
    ) -> some View {
        Group {
            if let draggedId = dragState.activeDragItemId,
               let proxyTab = browserManager.tabManager.resolveDragTab(for: draggedId) {
                PinnedTabView(
                    tabIcon: proxyTab.favicon,
                    presentationState: .launcherOnly,
                    liveTab: nil,
                    dragSourceConfiguration: SidebarDragSourceConfiguration(
                        item: SumiDragItem(
                            tabId: proxyTab.id,
                            title: proxyTab.name,
                            urlString: proxyTab.url.absoluteString
                        ),
                        sourceZone: .essentials,
                        previewKind: .essentialsTile,
                        previewIcon: proxyTab.favicon,
                        isEnabled: false
                    ),
                    accessibilityID: "ghost-placeholder",
                    isAppKitInteractionEnabled: false,
                    contextMenuEntries: [],
                    action: {},
                    onUnload: {}
                )
                .opacity(0.8)
                .scaleEffect(0.98)
                .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
        .frame(width: tileSize.width, height: tileSize.height)
    }

    @ObservedObject private var dragState = SidebarDragState.shared

    private func pinPresentationState(_ pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func essentialRuntimeState(_ pin: ShortcutPin) -> SumiEssentialRuntimeState? {
        browserManager.tabManager.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitManager: browserManager.splitManager
        )
    }

    private func activate(_ pin: ShortcutPin) {
        let tab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: windowState.currentSpaceId
        )
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func closeIfActive(_ pin: ShortcutPin) {
        guard let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState)
        else { return }
        browserManager.closeTab(current, in: windowState)
    }

    private func unload(_ pin: ShortcutPin) {
        if let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserManager.closeTab(current, in: windowState)
            return
        }

        browserManager.tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    private func openInSplit(_ pin: ShortcutPin, side: SplitViewManager.Side) {
        let tab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: windowState.currentSpaceId
        )
        browserManager.splitManager.enterSplit(with: tab, placeOn: side, in: windowState)
    }

    private func moveToRegularTabs(_ pin: ShortcutPin) {
        guard let targetSpace =
            windowState.currentSpaceId.flatMap({ id in browserManager.tabManager.spaces.first(where: { $0.id == id }) })
            ?? browserManager.tabManager.currentSpace
        else { return }
        browserManager.tabManager.convertShortcutPinToRegularTab(pin, in: targetSpace.id)
    }

    private var geometrySpaceId: UUID {
        spaceId
            ?? windowState.currentSpaceId
            ?? browserManager.tabManager.currentSpace?.id
            ?? browserManager.tabManager.spaces.first?.id
            ?? UUID()
    }

    /// True when the drag cursor is over this page’s Essentials drop target.
    private var isActiveEssentialsHoverForThisGrid: Bool {
        guard dragState.isDragging,
              let location = dragState.dragLocation,
              let page = dragState.hoveredInteractivePage(at: location),
              page.spaceId == geometrySpaceId
        else { return false }
        if case .essentials = dragState.hoveredSlot { return true }
        return false
    }

    private var essentialsEmptyGhostHasRenderableContent: Bool {
        guard let draggedId = dragState.activeDragItemId else { return false }
        return browserManager.tabManager.resolveDragTab(for: draggedId) != nil
    }

    /// Dash placeholder until hover; then show the real tile ghost when a tab preview exists.
    private var essentialsEmptyDropShowsLivePreview: Bool {
        isActiveEssentialsHoverForThisGrid && essentialsEmptyGhostHasRenderableContent
    }

    private func projectedContentHeight(
        for layout: SidebarEssentialsProjectedLayout,
        configuration: PinnedTabsConfiguration
    ) -> CGFloat {
        let rows = max(layout.visibleRowCount, 1)
        return CGFloat(rows) * layout.tileSize.height
            + CGFloat(max(rows - 1, 0)) * configuration.gridSpacing
    }

    private func resolvedDropFrame(
        visibleRowCount: Int,
        maxDropRowCount: Int,
        tileSize: CGSize,
        gridSpacing: CGFloat,
        visibleHeight: CGFloat
    ) -> CGRect {
        let safeVisibleRowCount = max(visibleRowCount, 1)
        let extraRows = max(0, maxDropRowCount - safeVisibleRowCount)
        let extraHeight = CGFloat(extraRows) * (tileSize.height + gridSpacing)
        return CGRect(
            x: 0,
            y: 0,
            width: width,
            height: visibleHeight + extraHeight
        )
    }

    private func resolvedPreviewState(
        _ previewState: SidebarEssentialsPreviewState,
        visibleRowCount: Int,
        maxDropRowCount: Int
    ) -> SidebarEssentialsPreviewState? {
        guard maxDropRowCount > visibleRowCount,
              previewState.expandedDropRowCount > visibleRowCount else {
            return nil
        }
        return SidebarEssentialsPreviewState(
            expandedDropRowCount: min(previewState.expandedDropRowCount, maxDropRowCount),
            ghostSlot: previewState.ghostSlot
        )
    }

    private func resolvedDisplayRows(
        for layout: SidebarEssentialsProjectedLayout,
        previewState: SidebarEssentialsPreviewState?,
        maxDropRowCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> [SidebarEssentialsDisplayRow] {
        var rows = layout.rows.map { row in
            let cells = row.items.map { item in
                if let item {
                    return SidebarEssentialsDisplayCell.pin(item)
                }
                return .ghost
            }

            return SidebarEssentialsDisplayRow(
                cells: cells,
                tileSize: row.tileSize,
                startSlot: row.startSlot
            )
        }

        guard let previewState else { return rows }

        let columns = max(layout.capacityColumnCount, 1)
        let targetRowCount = min(
            max(previewState.expandedDropRowCount, rows.count),
            maxDropRowCount
        )
        guard targetRowCount > rows.count else { return rows }

        while rows.count < targetRowCount {
            let rowIndex = rows.count
            let rowStart = rowIndex * columns
            let rowEnd = rowStart + columns
            var cells = [SidebarEssentialsDisplayCell.spacer]
            var visualColumnCount = 1

            if let ghostSlot = previewState.ghostSlot,
               ghostSlot >= rowStart,
               ghostSlot < rowEnd {
                let localSlot = ghostSlot - rowStart
                visualColumnCount = max(1, min(localSlot + 1, columns))
                cells = Array(
                    repeating: SidebarEssentialsDisplayCell.spacer,
                    count: visualColumnCount
                )
                cells[localSlot] = .ghost
            }

            let tileSize = SidebarEssentialsProjectionPolicy.visualTileSize(
                width: width,
                visualColumnCount: visualColumnCount,
                configuration: configuration
            )
            rows.append(
                SidebarEssentialsDisplayRow(
                    cells: cells,
                    tileSize: tileSize,
                    startSlot: rowStart
                )
            )
        }

        return rows
    }

    private func resolvedDropSlotFrames(
        for layout: SidebarEssentialsProjectedLayout,
        revealTileSize: CGSize,
        maxDropRowCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> [SidebarEssentialsDropSlotMetrics] {
        guard layout.visibleItemCount > 0 else {
            return [
                SidebarEssentialsDropSlotMetrics(
                    slot: 0,
                    frame: CGRect(origin: .zero, size: revealTileSize)
                )
            ]
        }

        let maxSlot = min(layout.visibleItemCount, SidebarEssentialsProjectionPolicy.maxItems)
        return (0...maxSlot).compactMap { slot in
            var items = layout.visibleItems
            let safeSlot = max(0, min(slot, items.count))
            items.insert(nil, at: safeSlot)

            let rows = SidebarEssentialsProjectionPolicy.projectedRows(
                from: items,
                capacityColumnCount: layout.capacityColumnCount,
                width: width,
                configuration: configuration
            )
            guard let rowIndex = rows.firstIndex(where: { row in
                row.items.contains { item in
                    if case .none = item { return true }
                    return false
                }
            }),
                  rowIndex < max(maxDropRowCount, 1)
            else { return nil }

            let row = rows[rowIndex]
            guard let columnIndex = row.items.firstIndex(where: { item in
                if case .none = item { return true }
                return false
            }) else {
                return nil
            }

            return SidebarEssentialsDropSlotMetrics(
                slot: safeSlot,
                frame: CGRect(
                    x: CGFloat(columnIndex) * (row.tileSize.width + configuration.gridSpacing),
                    y: CGFloat(rowIndex) * (row.tileSize.height + configuration.gridSpacing),
                    width: row.tileSize.width,
                    height: row.tileSize.height
                )
            )
        }
    }

}

private struct PinnedTile: View {
    @ObservedObject var pin: ShortcutPin
    let presentationState: ShortcutPresentationState
    let liveTab: Tab?
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onClose: () -> Void
    let onUnload: () -> Void
    let onRemovePin: () -> Void
    let onUnpinToRegular: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let showsCloseAction: Bool
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        Group {
            if let liveTab {
                LivePinnedTileContent(
                    pin: pin,
                    liveTab: liveTab,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onClose: onClose,
                    onUnload: onUnload,
                    onRemovePin: onRemovePin,
                    onUnpinToRegular: onUnpinToRegular,
                    onSplitRight: onSplitRight,
                    onSplitLeft: onSplitLeft,
                    showsCloseAction: showsCloseAction,
                    dragPinnedConfiguration: dragPinnedConfiguration,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            } else {
                StoredPinnedTileContent(
                    pin: pin,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onClose: onClose,
                    onUnload: onUnload,
                    onRemovePin: onRemovePin,
                    onUnpinToRegular: onUnpinToRegular,
                    onSplitRight: onSplitRight,
                    onSplitLeft: onSplitLeft,
                    showsCloseAction: showsCloseAction,
                    dragPinnedConfiguration: dragPinnedConfiguration,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LivePinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    @ObservedObject var liveTab: Tab
    let presentationState: ShortcutPresentationState
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onClose: () -> Void
    let onUnload: () -> Void
    let onRemovePin: () -> Void
    let onUnpinToRegular: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let showsCloseAction: Bool
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        let resolvedTitle = pin.resolvedDisplayTitle(liveTab: liveTab)
        let chromeTemplateSystemImageName = Self.chromeTemplateSystemImageName(for: liveTab)
        PinnedTabView(
            tabIcon: liveTab.favicon,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: liveTab,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: liveTab.favicon,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                pinnedConfiguration: dragPinnedConfiguration,
                exclusionZones: dragExclusionZones,
                onActivate: onActivate,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            supportsMiddleClickUnload: true,
            contextMenuEntries: makeEssentialsContextMenuEntries(
                showsCloseCurrentPage: showsCloseAction,
                callbacks: .init(
                    onOpen: onActivate,
                    onSplitRight: onSplitRight,
                    onSplitLeft: onSplitLeft,
                    onCloseCurrentPage: onClose,
                    onRemoveFromEssentials: onRemovePin,
                    onMoveToRegularTabs: onUnpinToRegular
                )
            ),
            action: onActivate,
            onUnload: onUnload
        )
        .overlay(alignment: .bottomTrailing) {
            if essentialRuntimeState?.showsSplitProxyBadge == true {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        essentialRuntimeState?.isSelected == true ? Color.accentColor : Color.secondary
                    )
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private static func chromeTemplateSystemImageName(for liveTab: Tab) -> String? {
        if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if liveTab.faviconIsTemplateGlobePlaceholder {
            return SumiPersistentGlyph.launcherSystemImageFallback
        }
        return nil
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] {
        var zones: [SidebarDragSourceExclusionZone] = []

        if liveTab.audioState.showsTabAudioButton {
            zones.append(.topLeadingSquare(size: 22, inset: 6))
        }

        return zones
    }
}

private struct StoredPinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let presentationState: ShortcutPresentationState
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onClose: () -> Void
    let onUnload: () -> Void
    let onRemovePin: () -> Void
    let onUnpinToRegular: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let showsCloseAction: Bool
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool
    @State private var faviconCacheRefreshID = UUID()

    var body: some View {
        let _ = faviconCacheRefreshID
        let resolvedTitle = pin.preferredDisplayTitle
        PinnedTabView(
            tabIcon: pin.storedFavicon,
            chromeTemplateSystemImageName: pin.storedChromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: nil,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: pin.storedFavicon,
                chromeTemplateSystemImageName: pin.storedChromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                pinnedConfiguration: dragPinnedConfiguration,
                exclusionZones: dragExclusionZones,
                onActivate: onActivate,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            supportsMiddleClickUnload: true,
            contextMenuEntries: makeEssentialsContextMenuEntries(
                showsCloseCurrentPage: showsCloseAction,
                callbacks: .init(
                    onOpen: onActivate,
                    onSplitRight: onSplitRight,
                    onSplitLeft: onSplitLeft,
                    onCloseCurrentPage: onClose,
                    onRemoveFromEssentials: onRemovePin,
                    onMoveToRegularTabs: onUnpinToRegular
                )
            ),
            action: onActivate,
            onUnload: onUnload
        )
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { _ in
            faviconCacheRefreshID = UUID()
        }
        .overlay(alignment: .bottomTrailing) {
            if essentialRuntimeState?.showsSplitProxyBadge == true {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        essentialRuntimeState?.isSelected == true ? Color.accentColor : Color.secondary
                    )
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] { [] }
}

@MainActor
func makePinnedTileDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    previewIcon: Image?,
    chromeTemplateSystemImageName: String? = nil,
    previewPresentationState: ShortcutPresentationState? = nil,
    pinnedConfiguration: PinnedTabsConfiguration,
    exclusionZones: [SidebarDragSourceExclusionZone],
    onActivate: (() -> Void)? = nil,
    isEnabled: Bool = true
) -> SidebarDragSourceConfiguration {
    SidebarDragSourceConfiguration(
        item: SumiDragItem(
            tabId: pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: .essentials,
        previewKind: .essentialsTile,
        previewIcon: previewIcon,
        chromeTemplateSystemImageName: chromeTemplateSystemImageName,
        pinnedConfig: pinnedConfiguration,
        previewPresentationState: previewPresentationState,
        exclusionZones: exclusionZones,
        onActivate: onActivate,
        isEnabled: isEnabled
    )
}

// MARK: - Preference Keys
// no-op
