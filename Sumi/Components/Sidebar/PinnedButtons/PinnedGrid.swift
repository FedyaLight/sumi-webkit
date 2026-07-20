//
//      PinnedGrid.swift
//      Sumi
//
//
import SumiDomain
import SwiftUI

enum PinnedGridContextResolver {
    static let unresolvedGeometrySpaceId: UUID = {
        guard let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            preconditionFailure("Invalid unresolved pinned-grid geometry space id")
        }
        return id
    }()

    static func contextMenuSpaceId(
        explicitSpaceId: UUID?,
        windowSpaceId: UUID?
    ) -> UUID? {
        explicitSpaceId ?? windowSpaceId
    }

    static func geometrySpaceId(
        explicitSpaceId: UUID?,
        windowSpaceId: UUID?
    ) -> UUID {
        explicitSpaceId ?? windowSpaceId ?? unresolvedGeometrySpaceId
    }
}

struct PinnedGrid: View {
    private static let collapsedRevealHeight: CGFloat = 6

    let width: CGFloat
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let items: [ShortcutPin]
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let spaceId: UUID?
    let profileId: UUID?
    let isTransitioningProfile: Bool
    let animateLayout: Bool
    let reportsGeometry: Bool
    let isAppKitInteractionEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection
    init(
        width: CGFloat,
        browserContext: SidebarBrowserContext,
        inventory: SidebarSpaceInventorySnapshot,
        items: [ShortcutPin],
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinCommands,
        pinExecution: SidebarPinExecutionCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        spaceId: UUID? = nil,
        profileId: UUID? = nil,
        isTransitioningProfile: Bool,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isAppKitInteractionEnabled: Bool = true
    ) {
        self.width = width
        self.browserContext = browserContext
        self.inventory = inventory
        self.items = items
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.pinExecution = pinExecution
        self.spaceLifecycle = spaceLifecycle
        self.spaceId = spaceId
        self.profileId = profileId
        self.isTransitioningProfile = isTransitioningProfile
        self.animateLayout = animateLayout
        self.reportsGeometry = reportsGeometry
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
    }

    var body: some View {
        let shouldReduceMotion = reduceMotion || sumiSettings.shouldReduceChromeMotion
        let selectionSnapshot = sidebarSelection

        // Use profile-filtered essentials
        let effectiveProfileId = profileId
            ?? windowState.currentProfileId
            ?? browserContext.profileAuthority.currentProfile?.id
        let visualItems = SidebarEssentialVisualProjection.make(
            pins: items,
            splitGroups: Array(inventory.splitGroupsByID.values),
            profileID: effectiveProfileId
        )
        let layout = PinnedGridLayoutModel(
            width: width,
            items: visualItems,
            dragState: dragState,
            dragGeometry: dragGeometry,
            geometrySpaceId: geometrySpaceId,
            effectiveProfileId: effectiveProfileId,
            animateLayout: animateLayout,
            reportsGeometry: reportsGeometry,
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: isTransitioningProfile,
            shouldReduceMotion: shouldReduceMotion
        )
        let projectedLayout = layout.projectedLayout
        let reportsDetailedGeometry = layout.reportsDetailedGeometry
        let shouldAnimateDropLayout = layout.shouldAnimateDropLayout
        let shouldAnimateContentLayout = layout.shouldAnimateContentLayout
        let showsRevealGap = layout.showsRevealGap
        let revealTileSize = layout.revealTileSize
        let revealHeight = layout.revealHeight
        let visibleRowCount = layout.visibleRowCount
        let maxDropRowCount = layout.maxDropRowCount
        let dropFrame = layout.dropFrame
        let previewState = layout.previewState
        let displayRows = layout.displayRows
        let displayLayoutSignature = layout.displayLayoutSignature
        let dropSlotFrames = layout.dropSlotFrames

        ZStack(alignment: .topLeading) {
            if visualItems.isEmpty {
                VStack(spacing: 0) {
                    if showsRevealGap {
                        Color.clear
                            .frame(width: revealTileSize.width, height: revealTileSize.height)
                    } else {
                        Color.clear
                            .frame(height: Self.collapsedRevealHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: revealHeight, alignment: .top)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: showsRevealGap)
            } else {
                LazyVStack(spacing: PinnedTileMetrics.gridSpacing) {
                    ForEach(displayRows, id: \.stableID) { row in
                        HStack(spacing: PinnedTileMetrics.gridSpacing) {
                            ForEach(row.cells, id: \.stableID) { cell in
                                switch cell {
                                case .pin(let pin):
                                    renderTile(
                                        for: pin,
                                        tileSize: row.tileSize,
                                        selectionSnapshot: selectionSnapshot
                                    )
                                case .splitGroup(let group):
                                    renderSplitTile(
                                        group,
                                        tileSize: row.tileSize,
                                        selectionSnapshot: selectionSnapshot
                                    )
                                case .gap:
                                    renderDropGap(
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
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: visualItems.map(\.id))
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.visualColumnSignature)
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.projectedItemCount)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: previewState?.expandedDropRowCount)
                .animation(shouldAnimateDropLayout ? SidebarDropMotion.gap : nil, value: displayLayoutSignature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: visualItems.isEmpty ? revealHeight : 0, alignment: .top)
        .sidebarSectionGeometry(
            for: .essentials,
            spaceId: geometrySpaceId,
            generation: dragGeometry.sidebarGeometryGeneration,
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
            gridSpacing: PinnedTileMetrics.gridSpacing,
            canAcceptDrop: projectedLayout.canAcceptDrop,
            generation: dragGeometry.sidebarGeometryGeneration,
            isEnabled: reportsDetailedGeometry
        )
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .allowsHitTesting(!isTransitioningProfile)
    }

    @ViewBuilder
    private func renderSplitTile(
        _ group: SplitGroup,
        tileSize: CGSize,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> some View {
        EssentialSplitGroupTile(
            group: group,
            pinsByID: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }),
            selection: selection,
            selectionSnapshot: selectionSnapshot,
            faviconImageReader: browserContext.faviconImageReader,
            essentialBackdropReader: browserContext.essentialBackdropReader,
            splitLayout: browserContext.splitLayout,
            emptySplitCreation: browserContext.emptySplitCreation,
            groupEditor: browserContext.splitGroupEditor,
            groupContextMenuActions: browserContext.splitGroupLifecycle
                .contextMenuActions(for: group, in: windowState),
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            onActivateMember: { memberID in
                browserContext.splitFocusCommands.focusGroup(
                    group.id,
                    memberID,
                    windowState.id
                )
            },
            onUnloadGroup: {
                browserContext.splitGroupLifecycle.unload(
                    group,
                    in: windowState
                )
            }
        )
        .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == group.id
                ? 0.001
                : 1
        )
        .transition(
            reduceMotion
                ? .identity
                : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func renderTile(
        for pin: ShortcutPin,
        tileSize: CGSize,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> some View {
        let presentationState = pinPresentationState(
            pin,
            selectionSnapshot: selectionSnapshot
        )
        let liveTab = selection.liveTab(for: pin.id, in: windowState)
        let contextMenuActions = essentialTileActionOwner.contextMenuActions(for: pin)

        PinnedTile(
            pin: pin,
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            essentialBackdropReader: browserContext.essentialBackdropReader,
            presentationState: presentationState,
            liveTab: liveTab,
            essentialRuntimeState: essentialRuntimeState(
                pin,
                selectionSnapshot: selectionSnapshot
            ),
            accessibilityID: "essential-shortcut-\(pin.id.uuidString)",
            onActivate: { activate(pin) },
            onUnload: { essentialTileActionOwner.unload(pin) },
            contextMenuActions: contextMenuActions,
            dragIsEnabled: !isTransitioningProfile && isAppKitInteractionEnabled,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled
        )
        .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == pin.id
                ? 0.001
                : 1
        )
        .transition(
            reduceMotion
                ? .identity
                : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
        )
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

    @EnvironmentObject private var dragState: SidebarDragState
    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    private func pinPresentationState(
        _ pin: ShortcutPin,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> ShortcutPresentationState {
        selection.presentationState(
            for: pin,
            in: windowState,
            selection: selectionSnapshot
        )
    }

    private func essentialRuntimeState(
        _ pin: ShortcutPin,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> SumiEssentialRuntimeState? {
        selection.essentialRuntimeState(
            for: pin,
            in: windowState,
            selection: selectionSnapshot
        )
    }

    private func activate(_ pin: ShortcutPin) {
        guard let tab = pinExecution.materialize(
            pin,
            in: windowState,
            currentSpaceID: windowState.currentSpaceId
        ) else { return }
        browserContext.tabSelection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }

    private var essentialTileActionOwner: EssentialTileActionOwner {
        EssentialTileActionOwner(
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            contextMenuSpaceId: PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: spaceId,
                windowSpaceId: windowState.currentSpaceId
            ),
            mutateContentLayout: mutateContentLayout
        )
    }

    private func mutateContentLayout(_ update: @escaping () -> Void) {
        guard animateLayout,
              windowRegistry.activeWindow?.id == windowState.id,
              !isTransitioningProfile,
              !reduceMotion,
              !dragState.isCompletingDrop else {
            update()
            return
        }

        withAnimation(SidebarDropMotion.contentLayout, update)
    }

    private var geometrySpaceId: UUID {
        PinnedGridContextResolver.geometrySpaceId(
            explicitSpaceId: spaceId,
            windowSpaceId: windowState.currentSpaceId
        )
    }
}
