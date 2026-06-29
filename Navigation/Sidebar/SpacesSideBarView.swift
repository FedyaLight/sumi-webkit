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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @EnvironmentObject private var dragState: SidebarDragState

    @State private var isSidebarHovered: Bool = false
    @State private var transitionCoordinator = SpaceSidebarTransitionCoordinator()
    @ObservedObject private var nowPlayingController: SumiNativeNowPlayingController
    @ObservedObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @ObservedObject private var updaterService = SumiUpdaterService.shared
    @StateObject private var scrollHoverCoordinator = NativeSurfaceScrollHoverCoordinator()
    let browserContext: SidebarBrowserContext

    init(
        browserContext: SidebarBrowserContext,
        nowPlayingController: SumiNativeNowPlayingController
    ) {
        self.browserContext = browserContext
        self.nowPlayingController = nowPlayingController
        self._extensionSurfaceStore = ObservedObject(
            wrappedValue: browserContext.extensionSurfaceStore
        )
    }

    private var sidebarBrowserContext: SidebarBrowserContext {
        browserContext
    }

    private var shouldMountMiniPlayer: Bool {
        guard sumiSettings.sidebarMiniPlayerEnabled else { return false }
        return SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
            globalState: nowPlayingController.cardState,
            in: windowState
        )
    }

    private var transitionState: SpaceSidebarTransitionState {
        transitionCoordinator.transitionState
    }

    private var transitionSnapshot: SpaceSidebarTransitionSnapshot? {
        transitionCoordinator.transitionSnapshot
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
                            browserContext.performDrop(pasteboard, resolution, windowState)
                        })
                    )
                        .allowsHitTesting(allowsSidebarInteractiveWork)
                }
            }
    }

    private var mainSidebarContent: some View {
        _ = browserContext.tabStructuralRevision()
        let spaces = availableSpaces
        let visualSpaceId = visualSelectedSpaceId(in: spaces)

        return VStack(spacing: 8) {
            SidebarHeader(browserContext: browserContext.headerContext(windowState))
                .environment(windowState)

            if let creationSession = windowState.activeSpaceCreationSession {
                SidebarSpaceCreationView(
                    session: creationSession,
                    profileContext: SpaceCreationProfileContext(
                        profiles: browserContext.profileManager.profiles,
                        currentProfileID: browserContext.currentProfile()?.id
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
                            browserContext.configureMediaStore(mediaStore, windowState)
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
                            SpaceTransitionProgressObserver(
                                progress: transitionState.progress,
                                transitionIdentity: transitionState.transitionIdentity
                            ) { progress, transitionIdentity in
                                handleTransitionProgressFrame(
                                    progress,
                                    transitionIdentity: transitionIdentity,
                                    spaces: spaces
                                )
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
                    handleCommittedSpaceChange(spaces)
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
            : browserContext.tabManager.spaces
    }

    private var sidebarInteractionState: SidebarInteractionState {
        windowState.sidebarInteractionState
    }

    private var allowsSidebarInteractiveWork: Bool {
        sidebarPresentationContext.allowsInteractiveWork
    }

    private func transitionContext(spaces: [Space]) -> SpaceSidebarTransitionCoordinator.Context {
        let windowState = windowState
        let browserContext = browserContext
        return SpaceSidebarTransitionCoordinator.Context(
            spaces: spaces,
            currentSpaces: {
                windowState.isIncognito
                    ? windowState.ephemeralSpaces
                    : browserContext.tabManager.spaces
            },
            windowState: windowState,
            browserContext: browserContext,
            dragState: dragState,
            settings: sumiSettings,
            allowsInteractiveWork: allowsSidebarInteractiveWork,
            reduceMotion: reduceMotion
        )
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
        transitionCoordinator.sourceOpacity(for: travelProgress)
    }

    private func destinationOpacity(for travelProgress: Double) -> Double {
        transitionCoordinator.destinationOpacity(for: travelProgress)
    }

    private func sourceOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.sourceOffsetX(width: width)
    }

    private func destinationOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.destinationOffsetX(width: width)
    }

    private func committedSpaceId(in spaces: [Space]) -> UUID? {
        transitionCoordinator.committedSpaceId(in: transitionContext(spaces: spaces))
    }

    private func visualSelectedSpaceId(in spaces: [Space]) -> UUID? {
        transitionCoordinator.visualSelectedSpaceId(in: transitionContext(spaces: spaces))
    }

    private func usesSharedPinnedGrid(
        sourceSpace: Space,
        destinationSpace: Space
    ) -> Bool {
        transitionCoordinator.usesSharedPinnedGrid(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            context: transitionContext(spaces: availableSpaces)
        )
    }

    private func space(for id: UUID?, in spaces: [Space]) -> Space? {
        transitionCoordinator.space(for: id, in: transitionContext(spaces: spaces))
    }

    private func handlePendingSplitGroupFocusRequest(
        _ request: SplitGroupFocusRequest?,
        spaces: [Space]
    ) {
        guard let request else { return }

        if windowState.currentSpaceId == request.targetSpaceId {
            browserContext.spaceTransitions.completePendingSplitGroupFocusIfReady(
                windowState,
                request.targetSpaceId
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
        transitionCoordinator.handleSpacesCollectionChange(transitionContext(spaces: spaces))
    }

    private func handleCommittedSpaceChange(_ spaces: [Space]) {
        transitionCoordinator.handleCommittedSpaceChange(transitionContext(spaces: spaces))
    }

    private func handleTransitionProgressFrame(
        _ progress: Double,
        transitionIdentity: SpaceTransitionIdentity?,
        spaces: [Space]
    ) {
        transitionCoordinator.handleTransitionProgressFrame(
            progress,
            transitionIdentity: transitionIdentity,
            context: transitionContext(spaces: spaces)
        )
    }

    private func handleSwipeEvent(
        _ event: SpaceSwipeGestureEvent,
        spaces: [Space]
    ) {
        transitionCoordinator.handleSwipeEvent(
            event,
            context: transitionContext(spaces: spaces)
        )
    }

    private func settleInteractiveSpaceTransition(commit: Bool) {
        transitionCoordinator.settleInteractiveSpaceTransition(
            commit: commit,
            context: transitionContext(spaces: availableSpaces)
        )
    }

    private func switchSpace(
        to targetSpace: Space,
        spaces: [Space]
    ) {
        transitionCoordinator.switchSpace(
            to: targetSpace,
            context: transitionContext(spaces: spaces)
        )
    }

    private func cancelPendingSpaceTransition() {
        transitionCoordinator.cancelPendingSpaceTransition()
    }

    private func cancelLocalSpaceTransitionIfNeeded(cancelTheme: Bool) {
        transitionCoordinator.cancelLocalSpaceTransitionIfNeeded(
            context: transitionContext(spaces: availableSpaces),
            cancelTheme: cancelTheme
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func refreshCommittedSidebarDragGeometryIfInteractive(spaces: [Space]) {
        transitionCoordinator.refreshCommittedSidebarDragGeometryIfInteractive(
            context: transitionContext(spaces: spaces)
        )
    }

    private func refreshCommittedSidebarDragGeometry(spaces: [Space]) {
        transitionCoordinator.refreshCommittedSidebarDragGeometry(
            context: transitionContext(spaces: spaces)
        )
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
        let newFolderAction: (() -> Void)? = browserContext.commands.canCreateFolderInCurrentSpace(windowState) == false
            ? nil
            : {
                browserContext.commands.createFolderInCurrentSpace(windowState)
            }
        let changeThemeAction: (() -> Void)? = browserContext.tabManager.currentSpace == nil
            ? nil
            : {
                browserContext.commands.showGradientEditor(windowState.resolveSidebarPresentationSource())
            }

        return makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: !windowState.isSidebarVisible,
            actions: .init(
                newTab: {
                    browserContext.commands.openNewTabOrFloatingBar(windowState)
                },
                newFolder: newFolderAction,
                newRSSLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createRSSLiveFolderInCurrentSpace(windowState) }
                },
                newGitHubPullRequestsLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createGitHubPullRequestsLiveFolderInCurrentSpace(windowState) }
                },
                newGitHubIssuesLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createGitHubIssuesLiveFolderInCurrentSpace(windowState) }
                },
                changeTheme: changeThemeAction,
                toggleCompactMode: {
                    browserContext.commands.toggleSidebar(windowState)
                },
                openSettings: {
                    browserContext.commands.openAppearanceSettings(windowState)
                }
            )
        )
    }

    // MARK: - Helper Functions

    private func handleSidebarContextMenuVisibility(_ presented: Bool) {
        if presented {
            browserContext.commands.closeDownloadsPopover(windowState)
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
                browserContext.commands.requestUserTabActivation($0, windowState)
            },
            onCloseTab: { browserContext.commands.closeTab($0, windowState) },
            onMoveTabUp: { browserContext.commands.moveTabUp($0.id) },
            onMoveTabDown: { browserContext.commands.moveTabDown($0.id) },
            onMuteTab: { $0.toggleMute() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(browserContext.glanceManager)
        .environment(windowState)
        .environmentObject(browserContext.splitManager)
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
        let enabledExtensions = extensionSurfaceStore.enabledExtensions
        let slots = browserContext.extensionToolbarSlots(enabledExtensions, profileId)
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork

        if ExtensionActionPlacement.resolve(totalActions: slots.count) == .sidebarGrid {
            ExtensionActionView(
                extensions: enabledExtensions,
                layout: .sidebarGrid,
                profileId: profileId,
                browserContext: browserContext.extensionActionBrowserContext(windowState)
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
            isTransitioningProfile: browserContext.isTransitioningProfile(),
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
        transitionCoordinator.resolvedPageProfileId(
            for: space,
            context: transitionContext(spaces: availableSpaces)
        )
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
            ?? browserContext.currentProfile()?.id
            ?? browserContext.profileManager.profiles.first?.id

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
            let createdProfile = browserContext.profileManager.createProfile(
                name: session.trimmedNewProfileName,
                icon: session.resolvedNewProfileIcon
            )
            profileId = createdProfile.id
        } else {
            profileId = session.profileID
        }

        let newSpace = browserContext.tabManager.createSpace(
            name: session.trimmedName,
            icon: session.resolvedIcon,
            profileId: profileId
        )
        if let resolvedSpace = browserContext.tabManager.spaces.first(where: { $0.id == newSpace.id }) {
            browserContext.spaceTransitions.setActiveSpace(resolvedSpace, windowState)
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
        return !browserContext.profileManager.profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    // MARK: - Computed Properties
}
