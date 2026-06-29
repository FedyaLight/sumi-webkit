//
//  SpacesSideBarView.swift
//  Sumi
//
//

import SwiftUI

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
    @EnvironmentObject private var dragState: SidebarDragState

    @State private var isSidebarHovered: Bool = false
    @State private var transitionState = SpaceSidebarTransitionState()
    @State private var transitionSnapshot: SpaceSidebarTransitionSnapshot?
    @State private var transitionTask: Task<Void, Never>?
    @ObservedObject private var nowPlayingController: SumiNativeNowPlayingController
    @ObservedObject private var updaterService = SumiUpdaterService.shared
    @StateObject private var scrollHoverCoordinator = NativeSurfaceScrollHoverCoordinator()

    init(nowPlayingController: SumiNativeNowPlayingController) {
        self.nowPlayingController = nowPlayingController
    }

    private var sidebarBrowserContext: SidebarBrowserContext {
        SidebarBrowserContext.live(browserManager: browserManager)
    }

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
                scrollHoverCoordinator.reset()
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
                    SidebarGlobalDragOverlay(
                        dropActions: SidebarDropActionContext(performDrop: { pasteboard, resolution, windowState in
                            SidebarDropCoordinator.performDrop(
                                pasteboard: pasteboard,
                                resolution: resolution,
                                browserManager: browserManager,
                                windowState: windowState
                            )
                        })
                    )
                        .allowsHitTesting(allowsSidebarInteractiveWork)
                }
            }
    }

    private var mainSidebarContent: some View {
        _ = browserManager.tabStructuralRevision
        let spaces = availableSpaces
        let visualSpaceId = visualSelectedSpaceId(in: spaces)

        return VStack(spacing: 8) {
            SidebarHeader(browserManager: browserManager)
                .environment(windowState)

            if let creationSession = windowState.activeSpaceCreationSession {
                SidebarSpaceCreationView(
                    session: creationSession,
                    profileContext: SpaceCreationProfileContext(
                        profiles: browserManager.profileManager.profiles,
                        currentProfileID: browserManager.currentProfile?.id
                    ),
                    onCreate: { commitSpaceCreationSession(creationSession) },
                    onCancel: { cancelSpaceCreationSession(creationSession) }
                )
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
                        MediaControlsView(nowPlayingController: nowPlayingController) { mediaStore, windowState in
                            mediaStore.configure(browserManager: browserManager, windowState: windowState)
                        }
                            .environment(windowState)
                    }

                    SidebarBottomBar(
                        browserContext: sidebarBrowserContext,
                        visualSelectedSpaceId: visualSpaceId,
                        onNewSpaceTap: beginSpaceCreationMode,
                        onSelectSpace: { switchSpace(to: $0, spaces: spaces) }
                    )
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
               let destinationSpace = space(for: transitionState.destinationSpaceId, in: spaces) {
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
                      transitionState.destinationSpaceId == nil {
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
           let pageSnapshot = transitionSnapshot?.page(for: space.id) {
            EquatableView(content: SpaceTransitionSnapshotPageView(
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
            ))
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
           let destinationSpace = space(for: destinationSpaceId, in: spaces) {
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
           let destinationSpace = space(for: destinationSpaceId, in: availableSpaces) {
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
                newRSSLiveFolder: newFolderAction.map { _ in
                    { browserManager.createRSSLiveFolderInCurrentSpace(in: windowState) }
                },
                newGitHubPullRequestsLiveFolder: newFolderAction.map { _ in
                    { browserManager.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState) }
                },
                newGitHubIssuesLiveFolder: newFolderAction.map { _ in
                    { browserManager.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState) }
                },
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
            browserContext: sidebarBrowserContext,
            renderMode: renderMode,
            allowsInteraction: allowsInteraction,
            scrollHoverCoordinator: scrollHoverCoordinator,
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
                profileId: profileId,
                browserManager: browserManager
            )
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
            browserContext: sidebarBrowserContext,
            spaceId: spaceId,
            profileId: profileId,
            animateLayout: shouldAnimate,
            reportsGeometry: allowsInteractiveWork,
            isAppKitInteractionEnabled: allowsInteractiveWork
        )
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
