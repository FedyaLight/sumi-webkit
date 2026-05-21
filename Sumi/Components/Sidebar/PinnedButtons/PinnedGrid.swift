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
    case gap(Int)
    case spacer(Int)

    var stableID: String {
        switch self {
        case .pin(let pin):
            return "pin-\(pin.id.uuidString)"
        case .gap(let slot):
            return "gap-\(slot)"
        case .spacer(let id):
            return "spacer-\(id)"
        }
    }
}

private struct SidebarEssentialsDisplayRow {
    let cells: [SidebarEssentialsDisplayCell]
    let tileSize: CGSize
    let startSlot: Int

    var stableID: Int {
        startSlot
    }

    var layoutSignature: [String] {
        cells.map(\.stableID)
    }
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

        let isDraggingExistingEssential = dragState.projectionDragItemId.map { itemIDs.contains($0) } ?? false
        let isHoveringEssentials = {
            guard dragState.isDropProjectionActive,
                  case .essentials = dragState.projectionHoveredSlot else {
                return false
            }
            return true
        }()

        let emptyStorePlaceholderActive = dragState.isDropProjectionActive
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
        guard let projectionDragItemId = dragState.projectionDragItemId else {
            return items.map { Optional($0) }
        }

        let isDraggingExistingEssential: Bool = {
            guard dragState.isDropProjectionActive,
                  dragState.projectionDragScope?.sourceContainer == .essentials else {
                return false
            }
            return items.contains { $0.id == projectionDragItemId }
        }()

        return items.compactMap { item -> ShortcutPin? in
            if item.id == projectionDragItemId, isDraggingExistingEssential {
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

        guard dragState.isDropProjectionActive, canAcceptDrop else {
            return layoutItems
        }

        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .essentials,
                targetAlreadyContainsDraggedItem: items.contains { $0?.id == projectionDragItemId }
           ) {
            return layoutItems
        }

        if essentialsStoreIsEmpty {
            if layoutItems.isEmpty {
                return [nil]
            }
            return layoutItems
        }

        guard case .essentials(let slot) = dragState.projectionHoveredSlot else {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
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
        let shouldAnimateDropLayout = animateLayout
            && (windowRegistry.activeWindow?.id == windowState.id)
            && !browserManager.isTransitioningProfile
            && !reduceMotion
            && dragState.shouldAnimateDropLayout
        let shouldAnimateContentLayout = animateLayout
            && (windowRegistry.activeWindow?.id == windowState.id)
            && !browserManager.isTransitioningProfile
            && !reduceMotion

        let showsRevealGap = items.isEmpty
            && dragState.isDragging
            && projectedLayout.canAcceptDrop
        let revealTileSize = projectedLayout.rows.first?.tileSize ?? projectedLayout.tileSize
        let revealHeight = showsRevealGap
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
        let displayLayoutSignature = displayRows.flatMap { $0.layoutSignature }
        let dropSlotFrames = resolvedDropSlotFrames(
            for: projectedLayout,
            revealTileSize: revealTileSize,
            maxDropRowCount: maxDropRowCount,
            configuration: pinnedTabsConfiguration
        )

        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                VStack(spacing: 0) {
                    if showsRevealGap {
                        SidebarEssentialsEmptyDropDashPlaceholder(size: revealTileSize)
                    } else {
                        Color.clear
                            .frame(height: Self.collapsedRevealHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: revealHeight, alignment: .top)
            } else {
                VStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                    ForEach(displayRows, id: \.stableID) { row in
                        HStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                            ForEach(row.cells, id: \.stableID) { cell in
                                switch cell {
                                case .pin(let pin):
                                    renderTile(
                                        for: pin,
                                        configuration: pinnedTabsConfiguration,
                                        tileSize: row.tileSize
                                    )
                                case .gap:
                                    renderDropGap(
                                        tileSize: row.tileSize
                                    )
                                case .spacer(_):
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
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: items.map(\.id))
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.visualColumnSignature)
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.projectedItemCount)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: previewState?.expandedDropRowCount)
                .animation(shouldAnimateDropLayout ? SidebarDropMotion.gap : nil, value: displayLayoutSignature)
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
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .allowsHitTesting(!browserManager.isTransitioningProfile)
    }

    @ViewBuilder
    private func renderTile(
        for pin: ShortcutPin,
        configuration: PinnedTabsConfiguration,
        tileSize: CGSize
    ) -> some View {
        if let placeholderGroup = splitPlaceholderGroup(for: pin) {
            PinnedSplitPlaceholderTile(
                pin: pin,
                isSelected: isSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "essential-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                onActivate: {
                    browserManager.focusSplitGroup(placeholderGroup, in: windowState)
                }
            )
            .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .environmentObject(browserManager)
            .transition(
                reduceMotion
                    ? .identity
                    : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
            )
        } else {
            let presentationState = pinPresentationState(pin)
            let liveTab = browserManager.tabManager.shortcutLiveTab(
                for: pin.id,
                in: windowState.id
            )
            let contextMenuActions = essentialContextMenuActions(for: pin)

            PinnedTile(
                pin: pin,
                presentationState: presentationState,
                liveTab: liveTab,
                essentialRuntimeState: essentialRuntimeState(pin),
                accessibilityID: "essential-shortcut-\(pin.id.uuidString)",
                onActivate: { activate(pin) },
                onClose: { closeIfActive(pin) },
                onUnload: { unload(pin) },
                contextMenuActions: contextMenuActions,
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
            .transition(
                reduceMotion
                    ? .identity
                    : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
            )
        }
    }

    @ViewBuilder
    private func renderDropGap(
        tileSize: CGSize
    ) -> some View {
        Color.clear
        .frame(width: tileSize.width, height: tileSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    private func splitPlaceholderGroup(for pin: ShortcutPin) -> SplitGroup? {
        browserManager.tabManager.splitGroup(containingPinId: pin.id)
    }

    private func isSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        guard let currentTabId = windowState.currentTabId else {
            return false
        }
        return group.contains(currentTabId)
            || group.member(forPinId: pin.id)?.tabId == currentTabId
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

    private func duplicateAsRegularTab(_ pin: ShortcutPin) {
        _ = browserManager.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: windowState.currentSpaceId
            )
        )
    }

    private func essentialContextMenuActions(for pin: ShortcutPin) -> EssentialTileContextMenuActions {
        EssentialTileContextMenuActions(makeEntries: {
            let savedURLDriftActions: SidebarSavedURLDriftActions? =
                browserManager.tabManager.shortcutHasDrifted(pin, in: windowState)
                    ? .init(
                        onBackToSavedURL: { resetShortcutPin(pin) },
                        onUseCurrentPageAsSavedURL: { _ = browserManager.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                    )
                    : nil
            let unloadAction: (() -> Void)? = pinPresentationState(pin).isOpenLive
                ? { unload(pin) }
                : nil
            let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
                moveEssential(pin, toSpace: targetSpaceId)
            }
            let spaceChoices = essentialSpaceChoices

            return makeSidebarTabContextMenuEntries(
                role: .essential,
                actions: .init(
                    duplicate: { duplicateAsRegularTab(pin) },
                    copyLink: { copyLink(pin.launchURL) },
                    share: {
                        presentSharePicker(
                            for: pin.launchURL,
                            source: windowState.resolveSidebarPresentationSource()
                        )
                    },
                    edit: { presentShortcutLinkEditor(for: pin) },
                    folderTarget: .init(
                        choices: essentialFolderChoices,
                        onSelect: { folderId in moveEssential(pin, toFolder: folderId) }
                    ),
                    moveToSpace: .init(
                        choices: spaceChoices,
                        onSelect: moveToSpaceAction,
                        presentPicker: {
                            MainActor.assumeIsolated {
                                presentSidebarSpaceDestinationPicker(
                                    choices: spaceChoices,
                                    browserManager: browserManager,
                                    settings: sumiSettings,
                                    themeContext: themeContext,
                                    source: windowState.resolveSidebarPresentationSource(),
                                    onSelect: moveToSpaceAction
                                )
                            }
                        }
                    ),
                    profileTarget: .init(
                        choices: profileChoices(for: pin),
                        onSelect: { profileId in
                            browserManager.tabManager.assign(
                                shortcutPin: pin,
                                toExecutionProfile: profileId
                            )
                        }
                    ),
                    savedURLDrift: savedURLDriftActions,
                    unload: unloadAction,
                    deleteSavedTab: { confirmDeleteEssential(pin) }
                )
            )
        })
    }

    private var contextMenuSpace: Space? {
        let targetSpaceId = windowState.currentSpaceId
            ?? spaceId
            ?? browserManager.tabManager.currentSpace?.id
        guard let targetSpaceId else { return nil }
        return browserManager.tabManager.spaces.first { $0.id == targetSpaceId }
    }

    private var essentialFolderChoices: [SidebarContextMenuChoice] {
        guard let contextMenuSpace else { return [] }
        return makeSidebarContextMenuFolderChoices(
            folders: browserManager.tabManager.folders(for: contextMenuSpace.id)
        )
    }

    private var essentialSpaceChoices: [SidebarContextMenuChoice] {
        makeSidebarContextMenuSpaceChoices(
            spaces: browserManager.tabManager.spaces
        )
    }

    private func profileChoices(for pin: ShortcutPin) -> [SidebarContextMenuChoice] {
        return makeSidebarContextMenuProfileChoices(
            profiles: browserManager.profileManager.profiles,
            selectedProfileId: browserManager.tabManager.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: contextMenuSpace?.id
            )
        )
    }

    private func moveEssential(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserManager.tabManager.folder(by: folderId) else { return }
        let targetIndex = browserManager.tabManager.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutateContentLayout {
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

    private func moveEssential(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserManager.tabManager.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutateContentLayout {
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

    private func removeFromEssentials(_ pin: ShortcutPin) {
        mutateContentLayout {
            browserManager.tabManager.removeFromEssentials(pin)
        }
    }

    private func confirmDeleteEssential(_ pin: ShortcutPin) {
        let manager = browserManager
        let settings = sumiSettings
        let theme = themeContext
        let source = windowState.resolveSidebarPresentationSource()
        DispatchQueue.main.async {
            manager.showDialog(
                SavedTabDeleteConfirmationDialog(
                    kind: .essential,
                    displayName: pin.preferredDisplayTitle,
                    url: pin.launchURL,
                    onDelete: {
                        manager.closeDialog()
                        removeFromEssentials(pin)
                    },
                    onCancel: { manager.closeDialog() }
                )
                .environment(\.sumiSettings, settings)
                .environment(\.resolvedThemeContext, theme),
                source: source
            )
        }
    }

    private func presentShortcutLinkEditor(for pin: ShortcutPin) {
        browserManager.showShortcutEditor(
            for: pin,
            in: windowState,
            source: windowState.resolveSidebarPresentationSource()
        )
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

    private func mutateContentLayout(_ update: () -> Void) {
        guard animateLayout,
              windowRegistry.activeWindow?.id == windowState.id,
              !browserManager.isTransitioningProfile,
              !reduceMotion,
              !dragState.isCompletingDrop else {
            update()
            return
        }

        withAnimation(SidebarDropMotion.contentLayout, update)
    }

    private var geometrySpaceId: UUID {
        spaceId
            ?? windowState.currentSpaceId
            ?? browserManager.tabManager.currentSpace?.id
            ?? browserManager.tabManager.spaces.first?.id
            ?? UUID()
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
            gapSlot: previewState.gapSlot
        )
    }

    private func resolvedDisplayRows(
        for layout: SidebarEssentialsProjectedLayout,
        previewState: SidebarEssentialsPreviewState?,
        maxDropRowCount: Int,
        configuration: PinnedTabsConfiguration
    ) -> [SidebarEssentialsDisplayRow] {
        var rows = layout.rows.map { row in
            let cells = row.items.enumerated().map { offset, item in
                if let item {
                    return SidebarEssentialsDisplayCell.pin(item)
                }
                return .gap(row.startSlot + offset)
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
            var cells = [SidebarEssentialsDisplayCell.spacer(rowStart)]
            var visualColumnCount = 1

            if let gapSlot = previewState.gapSlot,
               gapSlot >= rowStart,
               gapSlot < rowEnd {
                let localSlot = gapSlot - rowStart
                visualColumnCount = max(1, min(localSlot + 1, columns))
                cells = (0..<visualColumnCount).map { SidebarEssentialsDisplayCell.spacer(rowStart + $0) }
                cells[localSlot] = .gap(gapSlot)
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

private struct PinnedSplitPlaceholderTile: View {
    @ObservedObject var pin: ShortcutPin
    let isSelected: Bool
    let accessibilityID: String
    let isAppKitInteractionEnabled: Bool
    let onActivate: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isTileHovered = false
    @State private var faviconCacheRefreshID = UUID()
    @State private var loadedStoredFaviconURL: URL?
    @State private var loadedStoredFavicon: Image?

    var body: some View {
        let _ = faviconCacheRefreshID
        let configuration = PinnedTabsConfiguration.large
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFavicon
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? pin.storedChromeTemplateSystemImageName
            : nil

        PinnedTileVisual(
            tabIcon: resolvedFavicon,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: isSelected ? .visuallySelected : .liveBackgrounded,
            isHovered: displayIsHovered,
            showsSplitGroupOutline: true,
            faviconOpacity: 1,
            configuration: configuration
        )
        .frame(maxWidth: .infinity)
        .frame(height: configuration.height)
        .frame(minWidth: configuration.minWidth)
        .contentShape(
            RoundedRectangle(
                cornerRadius: sumiSettings.resolvedCornerRadius(configuration.cornerRadius),
                style: .continuous
            )
        )
        .onTapGesture(perform: onActivate)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "split placeholder")
        .sidebarDDGHover($isTileHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isAppKitInteractionEnabled,
            sourceID: accessibilityID,
            action: onActivate
        )
        .shadow(
            color: isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: isSelected ? 2 : 0,
            y: isSelected ? 1 : 0
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { _ in
            loadedStoredFaviconURL = nil
            loadedStoredFavicon = nil
            faviconCacheRefreshID = UUID()
        }
    }

    private var displayIsHovered: Bool {
        SidebarHoverChrome.displayHover(
            isTileHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var currentLoadedStoredFavicon: Image? {
        loadedStoredFaviconURL == pin.launchURL ? loadedStoredFavicon : nil
    }

    private var storedFaviconLoadKey: String {
        "\(pin.launchURL.absoluteString)|\(faviconCacheRefreshID.uuidString)"
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    @MainActor
    private func loadStoredFavicon() async {
        let launchURL = pin.launchURL
        guard let image = await TabFaviconStore.loadCachedLauncherImage(forDocumentURL: launchURL),
              !Task.isCancelled,
              launchURL == pin.launchURL
        else { return }

        loadedStoredFaviconURL = launchURL
        loadedStoredFavicon = Image(nsImage: image)
    }
}

private extension ShortcutPin {
    var glyphText: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) else {
            return nil
        }
        return iconAsset
    }

    var chromeTemplateSystemImageName: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) == false else {
            return nil
        }
        return SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset)
    }
}

private struct EssentialTileContextMenuActions {
    let makeEntries: () -> [SidebarContextMenuEntry]

    func entries() -> [SidebarContextMenuEntry] {
        makeEntries()
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
    let contextMenuActions: EssentialTileContextMenuActions
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
                    contextMenuActions: contextMenuActions,
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
                    contextMenuActions: contextMenuActions,
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
    let contextMenuActions: EssentialTileContextMenuActions
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        let resolvedTitle = pin.resolvedDisplayTitle(liveTab: liveTab)
        let glyphText = pin.glyphText
        let chromeTemplateSystemImageName = pin.chromeTemplateSystemImageName
            ?? Self.chromeTemplateSystemImageName(for: liveTab)
        PinnedTabView(
            tabIcon: liveTab.favicon,
            glyphText: glyphText,
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
            showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload
        )
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
    let contextMenuActions: EssentialTileContextMenuActions
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool
    @State private var faviconCacheRefreshID = UUID()
    @State private var loadedStoredFaviconURL: URL?
    @State private var loadedStoredFavicon: Image?

    var body: some View {
        let _ = faviconCacheRefreshID
        let resolvedTitle = pin.preferredDisplayTitle
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFavicon
        let glyphText = pin.glyphText
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? (pin.chromeTemplateSystemImageName ?? pin.storedChromeTemplateSystemImageName)
            : nil
        PinnedTabView(
            tabIcon: resolvedFavicon,
            glyphText: glyphText,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: nil,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: resolvedFavicon,
                chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                pinnedConfiguration: dragPinnedConfiguration,
                exclusionZones: dragExclusionZones,
                onActivate: onActivate,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { _ in
            loadedStoredFaviconURL = nil
            loadedStoredFavicon = nil
            faviconCacheRefreshID = UUID()
        }
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] { [] }

    private var currentLoadedStoredFavicon: Image? {
        loadedStoredFaviconURL == pin.launchURL ? loadedStoredFavicon : nil
    }

    private var storedFaviconLoadKey: String {
        "\(pin.launchURL.absoluteString)|\(faviconCacheRefreshID.uuidString)"
    }

    @MainActor
    private func loadStoredFavicon() async {
        let launchURL = pin.launchURL
        guard let image = await TabFaviconStore.loadCachedLauncherImage(forDocumentURL: launchURL),
              !Task.isCancelled,
              launchURL == pin.launchURL
        else { return }

        loadedStoredFaviconURL = launchURL
        loadedStoredFavicon = Image(nsImage: image)
    }
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
