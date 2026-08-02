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
    let width: CGFloat
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let items: [ShortcutPin]
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
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
    @ObservedObject private var dragPresentation:
        SidebarEssentialsDragPresentation

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    init(
        width: CGFloat,
        browserContext: SidebarBrowserContext,
        inventory: SidebarSpaceInventorySnapshot,
        items: [ShortcutPin],
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinCommands,
        pinExecution: SidebarPinExecutionCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        spaceId: UUID? = nil,
        profileId: UUID? = nil,
        isTransitioningProfile: Bool,
        dragPresentation: SidebarEssentialsDragPresentation,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isAppKitInteractionEnabled: Bool = true
    ) {
        self.width = width
        self.browserContext = browserContext
        self.inventory = inventory
        self.items = items
        self.launcherRuntime = launcherRuntime
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.pinExecution = pinExecution
        self.spaceLifecycle = spaceLifecycle
        self.spaceId = spaceId
        self.profileId = profileId
        self.isTransitioningProfile = isTransitioningProfile
        self._dragPresentation = ObservedObject(
            wrappedValue: dragPresentation
        )
        self.animateLayout = animateLayout
        self.reportsGeometry = reportsGeometry
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
    }

    var body: some View {
        let shouldReduceMotion = reduceMotion || sumiSettings.shouldReduceChromeMotion
        let motionMode = SidebarMotionPolicy.currentMode(
            reduceMotion: shouldReduceMotion
        )
        let selectionSnapshot = sidebarSelection
        let dragFrame = dragPresentation.frame

        // Use profile-filtered essentials
        let effectiveProfileId = resolvedProfileId
        let visualItems = SidebarEssentialVisualProjection.make(
            pins: items,
            splitGroups: Array(inventory.splitGroupsByID.values),
            profileID: effectiveProfileId
        )
        let layout = PinnedGridLayoutModel(
            width: width,
            items: visualItems,
            dragPresentation: dragFrame,
            dragGeometry: dragGeometry,
            geometrySpaceId: geometrySpaceId,
            effectiveProfileId: effectiveProfileId,
            showsHint: sumiSettings.showsEssentialsPlaceholder(
                profileId: effectiveProfileId
            ),
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
        let emptyPresentation = layout.emptyPresentation
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
                renderEmptyZone(
                    presentation: emptyPresentation,
                    isDismissible: layout.showsHint,
                    revealHeight: revealHeight,
                    animatesReveal: shouldAnimateDropLayout
                )
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
                .animation(shouldAnimateContentLayout ? SidebarMotionPolicy.contentLayoutAnimation(for: motionMode) : nil, value: visualItems.map(\.id))
                .animation(shouldAnimateContentLayout ? SidebarMotionPolicy.contentLayoutAnimation(for: motionMode) : nil, value: projectedLayout.visualColumnSignature)
                .animation(shouldAnimateContentLayout ? SidebarMotionPolicy.contentLayoutAnimation(for: motionMode) : nil, value: projectedLayout.projectedItemCount)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: previewState?.expandedDropRowCount)
                .animation(shouldAnimateDropLayout ? SidebarMotionPolicy.dragGapAnimation(for: motionMode) : nil, value: displayLayoutSignature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: visualItems.isEmpty ? revealHeight : 0, alignment: .top)
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
            if dragFrame.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .allowsHitTesting(!isTransitioningProfile)
    }

    @ViewBuilder
    private func renderEmptyZone(
        presentation: PinnedGridLayoutModel.EmptyPresentation,
        isDismissible: Bool,
        revealHeight: CGFloat,
        animatesReveal: Bool
    ) -> some View {
        let dismiss: (() -> Void)? = isDismissible ? { dismissPlaceholder() } : nil

        VStack(spacing: 0) {
            switch presentation {
            case .placeholder:
                EssentialsPlaceholderView(
                    tokens: tokens,
                    cornerRadius: sumiSettings.resolvedCornerRadius(
                        PinnedTileMetrics.cornerRadius
                    ),
                    onDismiss: dismiss,
                    isInteractionEnabled: isAppKitInteractionEnabled
                )
            case .collapsed:
                Color.clear
                    .frame(height: PinnedTileMetrics.collapsedEssentialsRevealHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: revealHeight, alignment: .top)
        .animation(
            animatesReveal
                ? .easeInOut(duration: EssentialsPlaceholderMetrics.revealAnimationDuration)
                : nil,
            value: presentation
        )
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
            launcherRuntime: launcherRuntime,
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
            dragPresentation.frame.isDragging
                && dragPresentation.frame.projectionDragItemID == group.id
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
        let liveTab = launcherRuntime.liveTab(for: pin.id)
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
            dragPresentation.frame.isDragging
                && dragPresentation.frame.projectionDragItemID == pin.id
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

    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    private func pinPresentationState(
        _ pin: ShortcutPin,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> ShortcutPresentationState {
        selection.presentationState(
            for: pin,
            liveTab: launcherRuntime.liveTab(for: pin.id),
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
            liveTab: launcherRuntime.liveTab(for: pin.id),
            in: windowState,
            selection: selectionSnapshot
        )
    }

    /// Essentials are profile-scoped, so every profile-keyed read in this view
    /// resolves through the same explicit → window → authority fallback.
    private var resolvedProfileId: UUID? {
        profileId
            ?? windowState.currentProfileId
            ?? browserContext.profileAuthority.currentProfile?.id
    }

    private func dismissPlaceholder() {
        guard let resolvedProfileId else { return }

        mutateContentLayout {
            sumiSettings.dismissEssentialsPlaceholder(profileId: resolvedProfileId)
        }
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
              !dragPresentation.frame.isCompletingDrop else {
            update()
            return
        }

        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        withAnimation(
            SidebarMotionPolicy.contentLayoutAnimation(for: mode),
            update
        )
    }

    private var geometrySpaceId: UUID {
        PinnedGridContextResolver.geometrySpaceId(
            explicitSpaceId: spaceId,
            windowSpaceId: windowState.currentSpaceId
        )
    }
}
