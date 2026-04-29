//
//  SpacesSideBarView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

enum SidebarPageRenderMode: Equatable {
    case interactive
    case transitionSnapshot

    var spaceRenderMode: SpaceViewRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }

    var debugDescription: String {
        switch self {
        case .interactive:
            return "interactive"
        case .transitionSnapshot:
            return "transitionSnapshot"
        }
    }

    var animatesEssentialsLayout: Bool {
        self == .interactive
    }
}

private extension SidebarPageRenderMode {
    var geometryRenderMode: SidebarPageGeometryRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }
}

enum SpaceSidebarRenderPolicy {
    static let completionDelay = SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration

    static func pageRenderMode(for role: Role) -> SidebarPageRenderMode {
        switch role {
        case .committed:
            return .interactive
        case .transitionLayer:
            return .transitionSnapshot
        }
    }

    static func shouldUseTransitionLayers(for state: SpaceSidebarTransitionState) -> Bool {
        state.hasDestination
    }

    static func shouldBeginSwipeTransition(for event: SpaceSwipeGestureEvent) -> Bool {
        event.phase == .changed && event.direction != nil
    }

    enum Role {
        case committed
        case transitionLayer
    }
}

@MainActor
enum SpaceSidebarChromePreviewPolicy {
    static func shouldAnimateEssentialsLayout(
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode
    ) -> Bool {
        isActiveWindow
            && !isTransitioningProfile
            && pageRenderMode.animatesEssentialsLayout
    }
}

enum SpaceSidebarEssentialsPlacementPolicy {
    static func usesSharedPinnedGrid(
        sourceProfileId: UUID?,
        destinationProfileId: UUID?
    ) -> Bool {
        sourceProfileId == destinationProfileId
    }
}

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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(CommandPalette.self) var commandPalette

    @State private var isSidebarHovered: Bool = false
    @State private var transitionState = SpaceSidebarTransitionState()
    @State private var transitionTask: Task<Void, Never>?
    @ObservedObject private var dragState = SidebarDragState.shared


    var body: some View {
        sidebarContent
            .contentShape(Rectangle())
            .onAppear {
                recordUITestSidebarState(reason: "appear")
            }
            .onChange(of: availableSpaces.map(\.id)) { _, _ in
                recordUITestSidebarState(reason: "spacesChanged")
            }
            .onChange(of: windowState.currentSpaceId) { _, _ in
                recordUITestSidebarState(reason: "currentSpaceChanged")
            }
            .onChange(of: windowState.isSidebarVisible) { _, _ in
                recordUITestSidebarState(reason: "sidebarVisibilityChanged")
            }
            .onChange(of: transitionState) { _, _ in
                recordUITestSidebarState(reason: "transitionStateChanged")
            }
            .onDisappear {
                cancelLocalSpaceTransitionIfNeeded(cancelTheme: true)
            }
            .onHover { state in
                isSidebarHovered = state
            }
    }

    // MARK: - Main Content

    private var sidebarContent: some View {
        mainSidebarContent
            .overlay {
                ZStack {
                    SidebarGlobalDragOverlay()
                        .allowsHitTesting(true)
                }
            }
    }

    private func recordUITestSidebarState(reason: String) {
        SidebarUITestDragMarker.recordEvent(
            "startupSidebarView",
            dragItemID: nil,
            ownerDescription: "SpacesSideBarView",
            details: "reason=\(reason) spaces=\(availableSpaces.count) currentSpace=\(windowState.currentSpaceId?.uuidString ?? "nil") currentTab=\(windowState.currentTabId?.uuidString ?? "nil") currentShortcutPin=\(windowState.currentShortcutPinId?.uuidString ?? "nil") sidebarVisible=\(windowState.isSidebarVisible) presentationMode=\(String(describing: sidebarPresentationContext.mode)) transitionPhase=\(transitionState.phase) transitionTrigger=\(transitionState.trigger.map(String.init(describing:)) ?? "nil") transitionSource=\(transitionState.sourceSpaceId?.uuidString ?? "nil") transitionDestination=\(transitionState.destinationSpaceId?.uuidString ?? "nil") transitionProgress=\(String(format: "%.3f", transitionState.progress))"
        )
    }

    private func recordSidebarPageRenderMode(
        reason: String,
        space: Space,
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode,
        inputRecoveryGeneration: UInt64
    ) {
        SidebarUITestDragMarker.recordEvent(
            "sidebarPageRenderMode",
            dragItemID: nil,
            ownerDescription: "SpacesSideBarView",
            details: "reason=\(reason) space=\(space.id.uuidString) profile=\(profileId?.uuidString ?? "nil") pageRenderMode=\(pageRenderMode.debugDescription) inputRecoveryGeneration=\(inputRecoveryGeneration) transitionPhase=\(transitionState.phase) transitionTrigger=\(transitionState.trigger.map(String.init(describing:)) ?? "nil") transitionSource=\(transitionState.sourceSpaceId?.uuidString ?? "nil") transitionDestination=\(transitionState.destinationSpaceId?.uuidString ?? "nil") transitionProgress=\(String(format: "%.3f", transitionState.progress)) currentSpace=\(windowState.currentSpaceId?.uuidString ?? "nil") currentTab=\(windowState.currentTabId?.uuidString ?? "nil") currentShortcutPin=\(windowState.currentShortcutPinId?.uuidString ?? "nil")"
        )
    }

    private var mainSidebarContent: some View {
        _ = browserManager.tabStructuralRevision
        let spaces = availableSpaces
        let visualSpaceId = visualSelectedSpaceId(in: spaces)

        return VStack(spacing: 8) {
            SidebarHeader()
                .environmentObject(browserManager)
                .environment(windowState)

            spacesPageView(spaces: spaces)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                MediaControlsView()
                    .environmentObject(browserManager)
                    .environment(windowState)

                SidebarBottomBar(
                    visualSelectedSpaceId: visualSpaceId,
                    onNewSpaceTap: showSpaceCreationDialog,
                    onSelectSpace: { switchSpace(to: $0, spaces: spaces) }
                )
                .environmentObject(browserManager)
                .environment(windowState)
            }
            .padding(.bottom, 8)
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
                                isEnabled: spaces.count > 1
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
                    refreshCommittedSidebarDragGeometry(spaces: spaces)
                }
                .onChange(of: spaces.map(\.id)) { _, _ in
                    handleSpacesCollectionChange(spaces)
                    refreshCommittedSidebarDragGeometry(spaces: spaces)
                }
                .onChange(of: committedSpaceId(in: spaces)) { _, _ in
                    refreshCommittedSidebarDragGeometry(spaces: spaces)
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
               let destinationSpace = space(for: transitionState.destinationSpaceId, in: spaces)
            {
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
                      transitionState.destinationSpaceId == nil
            {
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
                makePinnedGrid(
                    spaceId: sourceSpace.id,
                    profileId: resolvedPageProfileId(for: sourceSpace),
                    pageRenderMode: pageRenderMode
                )
                .allowsHitTesting(false)
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
        makeSidebarPage(
            for: space,
            pageRenderMode: pageRenderMode,
            includesPinnedGrid: includesPinnedGrid
        )
            .frame(width: width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: offsetX)
            .opacity(opacity)
            .zIndex(zIndex)
            .allowsHitTesting(false)
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
                let didBegin = transitionState.beginSwipeGesture(
                    from: committedSpaceId(in: spaces),
                    orderedSpaceIds: orderedSpaceIds
                )
                if didBegin {
                    beginSidebarDragGeometryTransition()
                }
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
                return
            }
            settleInteractiveSpaceTransition(commit: transitionState.shouldCommitSwipeOnEnd)

        case .cancelled:
            guard transitionState.trigger == .swipe else { return }
            if transitionState.destinationSpaceId == nil && transitionState.progress < 0.001 {
                cancelInteractiveThemeTransitionIfNeeded()
                transitionState.reset()
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
        beginSidebarDragGeometryTransition()
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
        refreshCommittedSidebarDragGeometry(spaces: availableSpaces)
    }

    private func spaceSwitchAnimation() -> Animation {
        .timingCurve(
            0.16,
            1.0,
            0.3,
            1.0,
            duration: SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration
        )
    }

    private var hasActiveThemeTransition: Bool {
        transitionState.hasDestination || windowState.isInteractiveSpaceTransition
    }

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
           let destinationSpace = space(for: destinationSpaceId, in: spaces)
        {
            if previousDestinationSpaceId != destinationSpaceId || !windowState.isInteractiveSpaceTransition {
                cancelPendingSpaceTransition()
                startInteractiveThemeTransition(from: sourceSpace, to: destinationSpace)
            }

            updateInteractiveThemeTransitionProgress(transitionState.progress)
            return
        }

        if previousDestinationSpaceId != nil || hadThemeTransition {
            cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: true)
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
           let destinationSpace = space(for: destinationSpaceId, in: availableSpaces)
        {
            browserManager.setActiveSpace(destinationSpace, in: windowState)
        } else {
            cancelInteractiveThemeTransitionIfNeeded(hadThemeTransition: hadThemeTransition)
        }

        refreshCommittedSidebarDragGeometry(spaces: availableSpaces)
        transitionTask = nil
    }

    private func beginSidebarDragGeometryTransition() {
        dragState.beginPendingGeometryEpoch(
            expectedSpaceId: nil,
            profileId: nil
        )
    }

    private func refreshCommittedSidebarDragGeometry(spaces: [Space]) {
        guard transitionState.phase == .idle,
              let committedSpace = space(for: committedSpaceId(in: spaces), in: spaces) else {
            return
        }

        dragState.beginPendingGeometryEpoch(
            expectedSpaceId: committedSpace.id,
            profileId: resolvedPageProfileId(for: committedSpace)
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
            Button(action: showSpaceCreationDialog) {
                Label("Create Space", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Context Menu

    private func sidebarContextMenuEntries() -> [SidebarContextMenuEntry] {
        let hasSelectedTab = browserManager.currentTab(for: windowState) != nil

        return makeSidebarShellContextMenuEntries(
            hasSelectedTab: hasSelectedTab,
            isCompactModeEnabled: sumiSettings.sidebarCompactSpaces,
            callbacks: .init(
                onCreateSpace: showSpaceCreationDialog,
                onCreateFolder: {
                    if let currentSpace = resolveCurrentSpace() {
                        _ = browserManager.tabManager.createFolder(for: currentSpace.id)
                    }
                },
                onNewSplit: {
                    if let current = browserManager.currentTab(for: windowState) {
                        browserManager.splitManager.enterSplit(with: current, placeOn: .right, in: windowState)
                    } else {
                        browserManager.createNewTab(in: windowState)
                    }
                },
                onNewTab: {
                    browserManager.createNewTab(in: windowState)
                },
                onReloadSelectedTab: {
                    browserManager.currentTab(for: windowState)?.refresh()
                },
                onBookmarkSelectedTab: {
                    if let current = browserManager.currentTab(for: windowState) {
                        browserManager.tabManager.pinTab(
                            current,
                            context: .init(windowState: windowState, spaceId: windowState.currentSpaceId)
                        )
                    }
                },
                onReopenClosedTab: {
                    browserManager.undoCloseTab()
                },
                onToggleCompactMode: {
                    sumiSettings.sidebarCompactSpaces.toggle()
                },
                onEditTheme: {
                    browserManager.showGradientEditor(
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onOpenLayout: {
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
        renderMode: SpaceViewRenderMode
    ) -> some View {
        SpaceView(
            space: space,
            renderMode: renderMode,
            isSidebarHovered: $isSidebarHovered,
            onActivateTab: {
                browserManager.requestUserTabActivation(
                    $0,
                    in: windowState
                )
            },
            onCloseTab: { browserManager.closeTab($0, in: windowState) },
            onPinTab: {
                browserManager.tabManager.pinTab(
                    $0,
                    context: .init(windowState: windowState, spaceId: space.id)
                )
            },
            onMoveTabUp: { browserManager.tabManager.moveTabUp($0.id) },
            onMoveTabDown: { browserManager.tabManager.moveTabDown($0.id) },
            onMuteTab: { $0.toggleMute() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(browserManager)
        .environment(windowState)
        .environment(commandPalette)
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
        let inputRecoveryGeneration = pageRenderMode == .interactive
            ? windowState.sidebarInputRecoveryGeneration
            : 0

        VStack(spacing: 8) {
            if includesPinnedGrid && !windowState.isIncognito {
                makePinnedGrid(
                    spaceId: space.id,
                    profileId: pageProfileId,
                    pageRenderMode: pageRenderMode
                )
            }

            makeSpaceView(
                for: space,
                renderMode: pageRenderMode.spaceRenderMode
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sidebarPageGeometry(
            spaceId: space.id,
            profileId: pageProfileId,
            renderMode: pageRenderMode.geometryRenderMode,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: pageRenderMode == .interactive
        )
        .id(
            SidebarPageInputGraphIdentity(
                spaceId: space.id,
                profileId: pageProfileId,
                recoveryGeneration: inputRecoveryGeneration
            )
        )
        .onAppear {
            recordSidebarPageRenderMode(
                reason: "appear",
                space: space,
                profileId: pageProfileId,
                pageRenderMode: pageRenderMode,
                inputRecoveryGeneration: inputRecoveryGeneration
            )
        }
        .onChange(of: windowState.sidebarInputRecoveryGeneration) { _, _ in
            recordSidebarPageRenderMode(
                reason: "inputRecoveryGenerationChanged",
                space: space,
                profileId: pageProfileId,
                pageRenderMode: pageRenderMode,
                inputRecoveryGeneration: inputRecoveryGeneration
            )
        }
    }

    @ViewBuilder
    private func makePinnedGrid(
        spaceId: UUID,
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let shouldAnimate = SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: browserManager.isTransitioningProfile,
            pageRenderMode: pageRenderMode
        )

        PinnedGrid(
            width: windowState.sidebarContentWidth,
            spaceId: spaceId,
            profileId: profileId,
            animateLayout: shouldAnimate,
            reportsGeometry: pageRenderMode == .interactive,
            isAppKitInteractionEnabled: pageRenderMode == .interactive
        )
        .environmentObject(browserManager)
        .environment(windowState)
        .padding(.horizontal, 8)
    }

    private func resolvedPageProfileId(for space: Space?) -> UUID? {
        space?.profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
    }

    // MARK: - Dialogs

    private func showSpaceCreationDialog() {
        let source = windowState.resolveSidebarPresentationSource()
        browserManager.showDialog(
            SpaceCreationDialog(
                onCreate: { name, icon, profileId in
                    let finalName = name.isEmpty ? "New Space" : name
                    let finalIcon = icon.isEmpty ? "✨" : icon
                    DispatchQueue.main.async {
                        let newSpace = browserManager.tabManager.createSpace(
                            name: finalName,
                            icon: finalIcon,
                            profileId: profileId
                        )
                        guard let resolvedSpace = browserManager.tabManager.spaces.first(where: { $0.id == newSpace.id })
                        else { return }
                        browserManager.setActiveSpace(resolvedSpace, in: windowState)
                    }
                    browserManager.closeDialog()
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            ),
            source: source
        )
    }

    private func resolveCurrentSpace() -> Space? {
        if windowState.isIncognito {
            if let currentId = windowState.currentSpaceId {
                return windowState.ephemeralSpaces.first { $0.id == currentId }
            }
            return windowState.ephemeralSpaces.first
        }

        if let currentId = windowState.currentSpaceId {
            return browserManager.tabManager.spaces.first { $0.id == currentId }
        }
        if let current = browserManager.tabManager.currentSpace {
            return current
        }
        return browserManager.tabManager.spaces.first
    }

    // MARK: - Computed Properties
}
