import Combine
import SumiDomain
import SwiftUI

struct SpaceSidebarListView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let listDragPresentation: SidebarListDragPresentation
    let isInteractive: Bool
    let innerWidth: CGFloat
    let onSetPinnedContentCollapsed: (Bool) -> Void
    @Binding var isSidebarHovered: Bool

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let traversal = SpaceSidebarInventoryTraversal(
            inventory: inventory,
            includesVisibleFolders:
                !windowState.isIncognito
                    && !windowState.sidebarSpacePinnedCollapse
                        .isCollapsed(space.id),
            isLiveFolder: { inventory.foldersByID[$0]?.isLiveFolder == true }
        )
        SpaceSidebarDragSnapshotReader(
            spaceID: space.id,
            listPresentation: listDragPresentation
        ) { dragSnapshots in
            SpaceSidebarLiveFolderReader(
                manager: browserContext.liveFolderManager,
                folderIDs: traversal.visibleFolderIDs,
                isActive: isInteractive
            ) { liveSnapshots in
                SpaceSidebarListContentView(
                    space: space,
                    inventory: inventory,
                    launcherRuntime: launcherRuntime,
                    selection: selection,
                    pinProjection: pinProjection,
                    pinCommands: pinCommands,
                    pinExecution: pinExecution,
                    folderCommands: folderCommands,
                    spaceLifecycle: spaceLifecycle,
                    regularTabCatalog: regularTabCatalog,
                    regularTabTargets: regularTabTargets,
                    regularTabLifecycleCommands: regularTabLifecycleCommands,
                    regularTabShortcutCommands: regularTabShortcutCommands,
                    regularTabPlacementCommands: regularTabPlacementCommands,
                    browserContext: browserContext,
                    isInteractive: isInteractive,
                    innerWidth: innerWidth,
                    // Both halves of the scene must come from the same
                    // snapshot: a live regular read would land one run loop
                    // ahead of the deferred inventory publish and split one
                    // container transfer into two structural transitions.
                    tabs: inventory.regularTabs,
                    inventoryTraversal: traversal,
                    liveSnapshots: liveSnapshots,
                    dragSnapshots: dragSnapshots,
                    onSetPinnedContentCollapsed:
                        onSetPinnedContentCollapsed,
                    isSidebarHovered: $isSidebarHovered
                )
            }
        }
    }
}

private struct SpaceSidebarListContentView: View {
    private static let folderIndent: CGFloat = 14

    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    let tabs: [Tab]
    let inventoryTraversal: SpaceSidebarInventoryTraversal
    let liveSnapshots: [UUID: SidebarLiveFolderSnapshot]
    let dragSnapshots: SpaceSidebarDragSnapshots
    let onSetPinnedContentCollapsed: (Bool) -> Void
    @Binding var isSidebarHovered: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var hasPinnedContent: Bool {
        !windowState.isIncognito && !inventory.topLevelItems.isEmpty
    }

    private var isPinnedCollapsed: Bool {
        hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var hasStalePinnedCollapseState: Bool {
        !hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var elevatedFolderIDs: Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: sidebarSelection
        ).elevatedFolderIds
    }

    private var spaceStickyOwner: SidebarSpacePinnedStickyProjectionOwner {
        SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion
        else { return nil }
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        return SidebarMotionPolicy.contentLayoutAnimation(for: mode)
    }

    private var isCompletingDrop: Bool {
        dragSnapshots.pinned.isCompletingDrop
            || dragSnapshots.regular.isCompletingDrop
    }

    /// A committed drop moves the dragged row between the pinned and regular
    /// sections. Naming the retired row keeps an unrelated coincident change
    /// from being mistaken for that move.
    private var identityTransfer:
        SidebarListIdentityTransfer<SpaceSidebarListElementID>? {
        guard isCompletingDrop,
              let draggedItemID = dragSnapshots.pinned.activeDragItemID
                  ?? dragSnapshots.regular.activeDragItemID
        else { return nil }

        return SidebarListIdentityTransfer(
            isSource: { $0.transferableItemID == draggedItemID },
            isTransferable: { $0.transferableItemID != nil }
        )
    }

    private var topLevelActionOwner: SpacePinnedActionOwner {
        SpacePinnedActionOwner(
            space: space,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            contentMutationAnimation: contentMutationAnimation
        )
    }

    private var regularTabActionOwner: SpaceRegularTabActionOwner {
        SpaceRegularTabActionOwner(
            space: space,
            catalog: regularTabCatalog,
            targets: regularTabTargets,
            lifecycleCommands: regularTabLifecycleCommands,
            shortcutCommands: regularTabShortcutCommands,
            placementCommands: regularTabPlacementCommands,
            browserContext: browserContext,
            windowState: windowState,
            firstTabID: tabs.first?.id,
            lastTabID: tabs.last?.id
        )
    }

    var body: some View {
        let output = SpaceSidebarSceneBuilder(
            space: space,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            tabs: tabs,
            inventoryTraversal: inventoryTraversal,
            windowState: windowState,
            hasPersistedTabs: regularTabCatalog.hasPersistedTabs(in: space),
            showsNewTab: sumiSettings.showNewTabButtonInTabList,
            newTabAtTop:
                sumiSettings.tabListNewTabButtonPosition == .top,
            selectionSnapshot: sidebarSelection,
            liveSnapshots: liveSnapshots,
            dragSnapshots: dragSnapshots,
            isInteractive: isInteractive,
            hasPinnedContent: hasPinnedContent,
            isPinnedCollapsed: isPinnedCollapsed,
            pinnedStickyItemIDs: spaceStickyOwner.visibleStickyItemIDs
        ).build()
        SidebarListSurface(
            scene: output.scene,
            animation: contentMutationAnimation,
            identityTransfer: identityTransfer,
            presentedSpaceID: space.id,
            geometryGeneration: dragSnapshots.pinned.geometryGeneration,
            autofocusTarget: autofocusTarget(for:)
        ) { payload, _ in
            elementView(payload)
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onAppear {
            spaceStickyOwner.reconcileOnAppear()
            if hasStalePinnedCollapseState {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            spaceStickyOwner.handleSelectionChange()
        }
        .onChange(of: output.structuralItemIDs) { oldIDs, newIDs in
            spaceStickyOwner.handleMembershipChange()
            guard isPinnedCollapsed else { return }
            if newIDs.isEmpty || !Set(newIDs).subtracting(oldIDs).isEmpty {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: dragSnapshots.pinned.isCompletingDrop) { _, isCompletingDrop in
            if isCompletingDrop,
               isPinnedCollapsed,
               dragSnapshots.pinned.isHoveringEmptySection {
                onSetPinnedContentCollapsed(false)
            }
        }
    }
}

@MainActor
private extension SpaceSidebarListContentView {
    private func autofocusTarget(
        for elementID: SpaceSidebarListElementID
    ) -> SidebarScrollTargetID? {
        switch elementID {
        case .folderHeader(let folderID):
            .folder(folderID)
        case .shortcut(let itemID):
            .launcher(itemID)
        case .splitGroup(let groupID):
            .splitGroup(groupID)
        case .liveItem(let folderID, let itemID):
            .liveFolderItem(folderID: folderID, itemID: itemID)
        case .regularTab(let tabID):
            .regularTab(tabID)
        case .pinnedTop, .folderBodyTop, .folderBodyBottom, .boundary,
                .regularRunStart, .regularRunEnd, .newTabGap, .newTab:
            nil
        }
    }

    @ViewBuilder
    private func elementView(
        _ payload: SpaceSidebarListElementPayload
    ) -> some View {
        switch payload {
        case .pinnedTop, .folderBodyTop, .folderBodyBottom,
                .regularRunStart, .regularRunEnd, .newTabGap:
            Color.clear
        case .folder(let folder):
            folderHeader(folder)
        case .topLevelShortcut(let row):
            topLevelShortcut(row)
        case .folderShortcut(let row):
            folderShortcut(row)
        case .collapsedNestedSticky(let itemID):
            SpaceNestedPinnedStickyEntryView(
                space: space,
                inventory: inventory,
                selection: selection,
                launcherRuntime: launcherRuntime,
                pinProjection: pinProjection,
                pinCommands: pinCommands,
                pinExecution: pinExecution,
                folderCommands: folderCommands,
                spaceLifecycle: spaceLifecycle,
                browserContext: browserContext,
                isInteractive: isInteractive,
                itemID: itemID,
                dragSnapshot: dragSnapshots.pinned,
                contentMutationAnimation: contentMutationAnimation
            )
        case .topLevelSplitGroup(let row):
            topLevelSplitGroup(row)
        case .folderSplitGroup(let row):
            folderSplitGroup(row)
        case .liveItem(let row):
            liveFolderItem(row)
        case .boundary(let boundary):
            SpaceSidebarBoundaryView(
                boundary: boundary,
                space: space,
                regularTabLifecycleCommands: regularTabLifecycleCommands,
                isSidebarHovered: $isSidebarHovered
            )
        case .regularTab(let tab):
            regularTab(tab)
        case .regularSplitGroup(let row):
            regularSplitGroup(row)
        case .newTab:
            SpaceRegularNewTabRow(
                space: space,
                browserContext: browserContext,
                isInteractive: isInteractive
            )
        }
    }

    private func folderHeader(
        _ row: SpaceSidebarListElementPayload.Folder
    ) -> some View {
        let projectionState = windowState.sidebarFolderProjections
            .pendingOrCurrentProjection(for: row.model.id)
        let hasLiveSelection =
            row.projection.isLiveFolder
            && row.projection.liveFolderItems.contains {
                row.projection.isLiveFolderItemSelected($0)
            }
        let mutationActions = folderMutationActions
        let contextOwner = folderContextOwner(
            row.model,
            mutationActions: mutationActions
        )
        return SpaceFlatFolderHeaderView(
            folder: row,
            space: space,
            inventory: inventory,
            selection: selection,
            launcherRuntime: launcherRuntime,
            pinProjection: pinProjection,
            browserContext: browserContext,
            isInteractive: isInteractive,
            elevatedFolderIDs: elevatedFolderIDs,
            hasLiveSelection: hasLiveSelection,
            hasActiveProjection: projectionState.hasActiveProjection,
            dragSnapshot: dragSnapshots.pinned.folderSnapshot,
            mutationActions: mutationActions,
            contextOwner: contextOwner
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .sidebarDropContainmentBackdrop(
            isVisible: dragSnapshots.pinned.folderSnapshot
                .isContainTargeted(folderID: row.model.id)
        )
        .opacity(itemOpacity(row.model.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: elevatedFolderIDs.contains(row.model.id)
            )
        )
    }

    private func topLevelShortcut(
        _ row: SpaceSidebarListElementPayload.TopLevelShortcut
    ) -> some View {
        let pin = row.pin
        return SpacePinnedShortcutEntryView(
            pin: pin,
            liveTab: row.liveTab,
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: row.runtimeAffordance,
            spaceID: space.id,
            isInteractive: isInteractive,
            opacity: itemOpacity(pin.id),
            projectedSplitTarget: dragSnapshots.pinned.splitPairingTarget?
                .projectedTarget(for: .shortcutPin(pin.id)),
            actionOwner: topLevelActionOwner
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isShortcutSelected(
                    pin,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
    }

    private func folderShortcut(
        _ row: SpaceSidebarListElementPayload.FolderShortcut
    ) -> some View {
        let mutationActions = folderMutationActions
        let contextOwner = folderContextOwner(
            row.folder,
            mutationActions: mutationActions
        )
        let presentationOwner = TabFolderShortcutPresentationOwner(
            pinProjection: pinProjection,
            selection: selection,
            launcherRuntime: launcherRuntime,
            windowState: windowState,
            selectionSnapshot: sidebarSelection
        )
        return TabFolderShortcutEntryView(
            pin: row.pin,
            liveTab: row.projection.liveTab(for: row.pin.id),
            faviconPartition: presentationOwner.faviconPartition(for: row.pin),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: presentationOwner.runtimeAffordance(for: row.pin),
            folderID: row.folder.id,
            isInteractive: isInteractive,
            opacity: dragSnapshots.pinned.folderSnapshot.childOpacity(
                itemID: row.pin.id
            ),
            projectedSplitTarget:
                dragSnapshots.pinned.splitPairingTarget?
                    .projectedTarget(for: .shortcutPin(row.pin.id)),
            contextMenuActionOwner: contextOwner,
            mutationActions: mutationActions
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: row.projection.isShortcutSelected(row.pin)
            )
        )
    }

    private func topLevelSplitGroup(
        _ row: SpaceSidebarListElementPayload.TopLevelSplitGroup
    ) -> some View {
        SpacePinnedSplitGroupEntryView(
            group: row.group,
            items: row.items,
            space: space,
            browserContext: browserContext,
            pinProjection: pinProjection,
            isInteractive: isInteractive,
            dragSnapshot: dragSnapshots.pinned.folderSnapshot
        )
        .opacity(itemOpacity(row.group.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isSplitGroupSelected(
                    row.group,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
    }

    private func folderSplitGroup(
        _ row: SpaceSidebarListElementPayload.FolderSplitGroup
    ) -> some View {
        TabFolderSplitGroupEntryView(
            group: row.group,
            items: row.items,
            space: space,
            browserContext: browserContext,
            pinProjection: pinProjection,
            isInteractive: isInteractive
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .sidebarDropContainmentBackdrop(
            isVisible: dragSnapshots.pinned.folderSnapshot
                .isExistingSplitGroupTargeted(
                    memberIDs: row.group.memberIDs
                )
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isSplitGroupSelected(
                    row.group,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
    }

    private func liveFolderItem(
        _ row: SpaceSidebarListElementPayload.LiveItem
    ) -> some View {
        let mutationActions = folderMutationActions
        let shortcutPin = row.item.shortcutPinId.flatMap(inventory.pin(id:))
        return TabFolderLiveItemEntryView(
            item: row.item,
            shortcutPin: shortcutPin,
            faviconPartition: shortcutPin.map {
                pinProjection.faviconPartition(
                    for: $0,
                    currentSpaceID: windowState.currentSpaceId
                )
            },
            faviconImageReader: browserContext.faviconImageReader,
            folderID: row.folder.id,
            isSelected: row.isSelected,
            isInteractive: isInteractive,
            actionOwner: folderContextOwner(
                row.folder,
                mutationActions: mutationActions
            )
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: row.isSelected)
        )
    }

    private func regularTab(_ tab: Tab) -> some View {
        let isCurrent = sidebarSelection.currentTabID == tab.id
        return SpaceRegularTabEntryView(
            tab: tab,
            spaceID: space.id,
            isCurrentTab: isCurrent,
            opacity:
                dragSnapshots.regular.isDragging
                    && dragSnapshots.regular.activeDragItemID == tab.id
                ? SidebarDragSourceDim.opacity
                : 1,
            isInteractive: isInteractive,
            projectedSplitTarget:
                dragSnapshots.regular.splitPairingTarget?
                    .projectedTarget(for: .regularTab(tab.id)),
            actionOwner: regularTabActionOwner,
            onClose: { regularTabActionOwner.close(tab) }
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: isCurrent)
        )
    }

    private func regularSplitGroup(
        _ row: SpaceSidebarListElementPayload.RegularSplitGroup
    ) -> some View {
        let isDropTarget: Bool
        if let target = dragSnapshots.regular.splitPairingTarget,
           target.presentation == .existingGroupRow {
            isDropTarget = row.group.memberIDs.contains(target.memberID)
        } else {
            isDropTarget = false
        }
        return SpaceRegularSplitGroupEntryView(
            group: row.group,
            space: space,
            tabByID: row.tabByID,
            selection: selection,
            launcherRuntime: launcherRuntime,
            regularTabCatalog: regularTabCatalog,
            regularTabTargets: regularTabTargets,
            browserContext: browserContext,
            isInteractive: isInteractive,
            isDropHighlighted: isDropTarget,
            tabActionOwner: regularTabActionOwner
        )
        .opacity(
            dragSnapshots.regular.isDragging
                && dragSnapshots.regular.activeDragItemID == row.group.id
                ? SidebarDragSourceDim.opacity
                : 1
        )
    }

    private var folderMutationActions: TabFolderMutationActions {
        TabFolderMutationActions(
            browserContext: browserContext,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext,
            space: space,
            folderLayoutAnimation: contentMutationAnimation
        )
    }

    private func folderContextOwner(
        _ folder: TabFolder,
        mutationActions: TabFolderMutationActions
    ) -> TabFolderContextMenuActionOwner {
        TabFolderContextMenuActionOwner(
            folder: folder,
            space: space,
            childFoldersByParentId: inventory.childFoldersByParentID,
            folderPinsByFolderId: inventory.folderPinsByFolderID,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            folderLayoutAnimation: contentMutationAnimation,
            mutationActions: mutationActions
        )
    }

    private func itemOpacity(_ itemID: UUID) -> Double {
        dragSnapshots.pinned.isDragging
            && dragSnapshots.pinned.activeDragItemID == itemID
            ? SidebarDragSourceDim.opacity
            : 1
    }
}

private struct SpaceFlatFolderHeaderView: View {
    let folder: SpaceSidebarListElementPayload.Folder
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let pinProjection: SidebarPinFolderProjection
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let elevatedFolderIDs: Set<UUID>
    let hasLiveSelection: Bool
    let hasActiveProjection: Bool
    let dragSnapshot: SidebarFolderDragSnapshot
    let mutationActions: TabFolderMutationActions
    let contextOwner: TabFolderContextMenuActionOwner

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var stickyOwner: SidebarFolderStickyProjectionOwner {
        SidebarFolderStickyProjectionOwner(
            folder: folder.model,
            presentation: folder.presentation,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    var body: some View {
        TabFolderHeaderView(
            folder: folder.model,
            presentation: folder.presentation,
            space: space,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            parentFolderId: folder.parentFolderID,
            contentProjection: folder.contentProjection,
            isInteractive: isInteractive,
            folderPreviewIsOpen: dragSnapshot.isFolderPreviewOpen(
                folderID: folder.model.id,
                isOpen: folder.presentation.isExpanded
            ),
            hasActiveSelection:
                hasLiveSelection
                || elevatedFolderIDs.contains(folder.model.id),
            hasActiveProjection: hasActiveProjection,
            isDragging: dragSnapshot.isDragging,
            contextMenuEntries: {
                contextOwner.folderHeaderContextMenuEntries()
            },
            onToggle: {
                mutationActions.toggleFolderOpenState(folder.model.id)
            },
            onActivateShortcutPin: mutationActions.activateShortcutPin,
            onResetProjection: resetProjectionAction,
            resetProjectionErrorTitle: liveFolderErrorTitle
        )
        .onAppear {
            stickyOwner.reconcileOnAppear()
            refreshLiveFolderIfNeeded()
        }
        .onChange(of: folder.presentation.expansionRevision) { _, _ in
            if folder.presentation.isExpanded {
                stickyOwner.handleExpand()
            } else {
                stickyOwner.handleCollapse()
            }
            stickyOwner.prunePublish()
            refreshLiveFolderIfNeeded()
        }
        .onChange(of: sidebarSelection) { _, _ in
            stickyOwner.handleSelectionChange()
        }
        .onChange(of: folder.orderedDescendantItemIDs) { _, _ in
            stickyOwner.handleMembershipChange()
        }
        .onChange(
            of: folder.contentProjection.targetCollapsedProjectionIDs
        ) { _, _ in
            stickyOwner.prunePublish()
        }
    }

    private var resetProjectionAction: (() -> Void)? {
        guard !folder.presentation.isExpanded else { return nil }
        if browserContext.liveFolderManager.source(for: folder.model.id)?
            .lastErrorKind != nil {
            return {
                browserContext.liveFolderManager.refresh(folderId: folder.model.id)
            }
        }
        guard !folder.contentProjection.visibleCollapsedProjectionIDs.isEmpty else {
            return nil
        }
        return {
            mutationActions.resetCollapsedProjection(
                folder.model,
                inventory: inventory
            )
        }
    }

    private var liveFolderErrorTitle: String? {
        browserContext.liveFolderManager.source(for: folder.model.id)?
            .lastErrorKind?
            .displayTitle
    }

    private func refreshLiveFolderIfNeeded() {
        guard folder.presentation.isExpanded else { return }
        browserContext.liveFolderManager.refreshIfStale(
            folderId: folder.model.id
        )
    }
}

private struct SpaceSidebarBoundaryView: View {
    let boundary: SpaceSidebarListElementPayload.Boundary
    let space: Space
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    @Binding var isSidebarHovered: Bool

    var body: some View {
        SpaceTabSectionBoundary(layout: boundary.layout) {
            SpaceSeparator(
                hasTabs: boundary.hasPersistedTabs,
                isHovering: $isSidebarHovered
            ) {
                regularTabLifecycleCommands.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)
        }
    }
}
