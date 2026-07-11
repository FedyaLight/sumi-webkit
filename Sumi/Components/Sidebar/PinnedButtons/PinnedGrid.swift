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
    let spaceId: UUID?
    let profileId: UUID?
    let animateLayout: Bool
    let reportsGeometry: Bool
    let isAppKitInteractionEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    init(
        width: CGFloat,
        browserContext: SidebarBrowserContext,
        spaceId: UUID? = nil,
        profileId: UUID? = nil,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isAppKitInteractionEnabled: Bool = true
    ) {
        self.width = width
        self.browserContext = browserContext
        self.spaceId = spaceId
        self.profileId = profileId
        self.animateLayout = animateLayout
        self.reportsGeometry = reportsGeometry
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
    }

    var body: some View {
        let _ = browserContext.tabStructuralRevision()
        let shouldReduceMotion = reduceMotion || sumiSettings.shouldReduceChromeMotion

        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserContext.currentProfile()?.id
        let items: [ShortcutPin] = effectiveProfileId != nil
            ? browserContext.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: effectiveProfileId)
            : []
        let layout = PinnedGridLayoutModel(
            width: width,
            items: items,
            dragState: dragState,
            geometrySpaceId: geometrySpaceId,
            effectiveProfileId: effectiveProfileId,
            animateLayout: animateLayout,
            reportsGeometry: reportsGeometry,
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: browserContext.isTransitioningProfile(),
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
            if items.isEmpty {
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
                                        tileSize: row.tileSize
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
            gridSpacing: PinnedTileMetrics.gridSpacing,
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
        .allowsHitTesting(!browserContext.isTransitioningProfile())
    }

    @ViewBuilder
    private func renderTile(
        for pin: ShortcutPin,
        tileSize: CGSize
    ) -> some View {
        if let placeholderGroup = splitPlaceholderGroup(for: pin) {
            PinnedSplitPlaceholderTile(
                pin: pin,
                faviconPartition: browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                isSelected: isSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "essential-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                onActivate: {
                    browserContext.commands.focusSplitGroup(
                        placeholderGroup.id,
                        .shortcutPin(pin.id),
                        windowState.id
                    )
                }
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
        } else {
            let presentationState = pinPresentationState(pin)
            let liveTab = browserContext.tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: pin.id,
                in: windowState.id
            )
            let contextMenuActions = essentialTileActionOwner.contextMenuActions(for: pin)

            PinnedTile(
                pin: pin,
                faviconPartition: browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                presentationState: presentationState,
                liveTab: liveTab,
                essentialRuntimeState: essentialRuntimeState(pin),
                accessibilityID: "essential-shortcut-\(pin.id.uuidString)",
                onActivate: { activate(pin) },
                onUnload: { essentialTileActionOwner.unload(pin) },
                contextMenuActions: contextMenuActions,
                dragIsEnabled: !browserContext.isTransitioningProfile() && isAppKitInteractionEnabled,
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

    private func pinPresentationState(_ pin: ShortcutPin) -> ShortcutPresentationState {
        browserContext.tabManager.shortcutPresentationOwner.shortcutPresentationState(for: pin, in: windowState)
    }

    private func essentialRuntimeState(_ pin: ShortcutPin) -> SumiEssentialRuntimeState? {
        browserContext.tabManager.shortcutPresentationOwner.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitQuery: browserContext.splitQuery
        )
    }

    private func splitPlaceholderGroup(for pin: ShortcutPin) -> SplitGroup? {
        guard let group = browserContext.tabManager.splitGroupStore.group(
            containing: .shortcutPin(pin.id)
        ), !group.container.isShortcutSidebar else {
            return nil
        }
        return group
    }

    private func isSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        return windowState.splitSelection?.groupID == group.id
            && windowState.splitSelection?.activeMemberID == .shortcutPin(pin.id)
    }

    private func activate(_ pin: ShortcutPin) {
        let tab = browserContext.tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: windowState.currentSpaceId
        )
        browserContext.commands.requestUserTabActivation(
            tab,
            windowState
        )
    }

    private var essentialTileActionOwner: EssentialTileActionOwner {
        EssentialTileActionOwner(
            browserContext: browserContext,
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
              !browserContext.isTransitioningProfile(),
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
