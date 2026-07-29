//
//  SpaceSidebarPageChrome.swift
//  Sumi
//
//

import SwiftUI

struct SidebarPageInventorySnapshot: Equatable {
    let space: SidebarSpaceInventorySnapshot
    let essentialPins: [ShortcutPin]

    static func == (
        lhs: SidebarPageInventorySnapshot,
        rhs: SidebarPageInventorySnapshot
    ) -> Bool {
        lhs.space == rhs.space
            && lhs.essentialPins.count == rhs.essentialPins.count
            && zip(lhs.essentialPins, rhs.essentialPins).allSatisfy {
                $0 === $1
            }
    }
}

private struct SidebarExtensionGridSnapshot: Equatable {
    let enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
    let slotCount: Int
}

extension SpacesSideBarView {
    func spacesPageView(spaces: [Space]) -> some View {
        GeometryReader { geo in
            spaceTransitionContainer(spaces: spaces, size: geo.size)
                .modifier(
                    SpaceTransitionProgressObserver(
                        progress: transitionState.progress,
                        transitionIdentity: transitionState.transitionIdentity
                    ) { progress, transitionIdentity in
                        transitionCoordinator.handleTransitionProgressFrame(
                            progress,
                            transitionIdentity: transitionIdentity,
                            context: makeTransitionContext(spaces: spaces)
                        )
                    }
                )
                .overlay {
                    SidebarSwipeCaptureSurface(
                        isEnabled: allowsSidebarInteractiveWork
                            && spaces.count > 1
                            && (transitionState.phase == .idle || transitionState.phase == .interactive)
                            && sidebarInteractionState.allowsSidebarSwipeCapture,
                        dragAutoscrollRegistry: dragState.dragAutoscrollRegistry
                    ) { event in
                        transitionCoordinator.handleSwipeEvent(
                            event,
                            context: makeTransitionContext(spaces: spaces)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
        .clipped()
        .onAppear {
            transitionCoordinator.handleSpacesCollectionChange(
                makeTransitionContext(spaces: spaces)
            )
            transitionCoordinator.refreshCommittedSidebarDragGeometryIfInteractive(
                context: makeTransitionContext(spaces: spaces)
            )
        }
        .onChange(of: spaces.map(\.id)) { _, _ in
            transitionCoordinator.handleSpacesCollectionChange(
                makeTransitionContext(spaces: spaces)
            )
            transitionCoordinator.refreshCommittedSidebarDragGeometryIfInteractive(
                context: makeTransitionContext(spaces: spaces)
            )
        }
        .onChange(of: transitionCoordinator.committedSpaceId(in: makeTransitionContext(spaces: spaces))) { _, _ in
            transitionCoordinator.handleCommittedSpaceChange(
                makeTransitionContext(spaces: spaces)
            )
        }
        .onChange(of: allowsSidebarInteractiveWork) { _, allowsInteractiveWork in
            if allowsInteractiveWork {
                transitionCoordinator.refreshCommittedSidebarDragGeometry(
                    context: makeTransitionContext(spaces: spaces)
                )
            }
        }
    }
    @ViewBuilder
    func makeSpaceView(
        for space: Space,
        inventory pageInventory: SidebarSpaceInventorySnapshot,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        renderMode: SpaceViewRenderMode,
        allowsInteraction: Bool
    ) -> some View {
        SpaceView(
            space: space,
            browserContext: sidebarBrowserContext,
            inventory: pageInventory,
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
            listDragPresentation: dragState.listPresentation,
            dragAutoscrollRegistry: dragState.dragAutoscrollRegistry,
            renderMode: renderMode,
            allowsInteraction: allowsInteraction,
            restoredScrollViewport: transitionCoordinator.scrollViewport(for: space.id),
            scrollHoverCoordinator: scrollHoverCoordinator,
            persistWindowSession: persistWindowSession,
            isSidebarHovered: $isSidebarHovered,
            onScrollViewportChange: { spaceId, viewport in
                transitionCoordinator.recordScrollViewport(viewport, for: spaceId)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(browserContext.glanceManager)
        .environment(windowState)
        .id(space.id)
    }

    @ViewBuilder
    func makeSidebarPage(
        for space: Space,
        pageRenderMode: SidebarPageRenderMode,
        includesPinnedGrid: Bool = true
    ) -> some View {
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork

        SidebarScopedSnapshotReader(
            current: {
                SidebarProfileRuntimeSnapshot(
                    currentProfileID: browserContext.profileAuthority.currentProfile?.id,
                    isTransitioning: browserContext.profileAuthority.isTransitioning
                )
            },
            changes: profileUpdates.runtime,
            areEquivalent: ==,
            isActive: allowsInteractiveWork
        ) { profileRuntime in
            observedSidebarPage(
                space: space,
                pageRenderMode: pageRenderMode,
                includesPinnedGrid: includesPinnedGrid,
                profileRuntime: profileRuntime,
                allowsInteractiveWork: allowsInteractiveWork
            )
        }
    }

    @ViewBuilder
    private func observedSidebarPage(
        space: Space,
        pageRenderMode: SidebarPageRenderMode,
        includesPinnedGrid: Bool,
        profileRuntime: SidebarProfileRuntimeSnapshot,
        allowsInteractiveWork: Bool
    ) -> some View {
        let pageProfileId = space.profileId
            ?? windowState.currentProfileId
            ?? profileRuntime.currentProfileID
        // Fallback-only identity change for unresolved AppKit owner/input graph recovery.
        let inputRecoveryGeneration = pageRenderMode == .interactive
            ? windowState.sidebarInputRecovery.generation
            : 0

        SidebarScopedSnapshotReader(
            current: {
                sidebarPageInventorySnapshot(
                    space: space,
                    profileID: pageProfileId
                )
            },
            changes: sidebarPageInventoryChanges(
                spaceID: space.id,
                profileID: pageProfileId
            ).map { [inventory, windowState] _ in
                SidebarPageInventorySnapshot(
                    space: windowState.isIncognito
                        ? SidebarSpaceInventorySnapshot.ephemeral(
                            spaceID: space.id,
                            regularTabs: windowState.ephemeralTabs
                        )
                        : inventory.snapshot(for: space.id)
                            ?? SidebarSpaceInventorySnapshot.ephemeral(
                                spaceID: space.id,
                                regularTabs: []
                            ),
                    essentialPins: pageProfileId.map {
                        spaceCatalog.essentialPins(profileID: $0)
                    } ?? []
                )
            }
            .eraseToAnyPublisher(),
            delivery: .mainActorImmediate(
                deferral: presentedDropCompletionDeferral(
                    for: dragState
                )
            ),
            areEquivalent: ==,
            isActive: allowsInteractiveWork
        ) { pageInventory in
            observedSidebarLauncherRuntime(
                space: space,
                pageRenderMode: pageRenderMode,
                pageProfileId: pageProfileId,
                pageInventory: pageInventory,
                includesPinnedGrid: includesPinnedGrid,
                isTransitioningProfile: profileRuntime.isTransitioning,
                allowsInteractiveWork: allowsInteractiveWork
            )
        }
        .id(
            SidebarPageInputGraphIdentity(
                spaceId: space.id,
                profileId: pageProfileId,
                recoveryGeneration: inputRecoveryGeneration
            )
        )
    }

    @ViewBuilder
    private func observedSidebarLauncherRuntime(
        space: Space,
        pageRenderMode: SidebarPageRenderMode,
        pageProfileId: UUID?,
        pageInventory: SidebarPageInventorySnapshot,
        includesPinnedGrid: Bool,
        isTransitioningProfile: Bool,
        allowsInteractiveWork: Bool
    ) -> some View {
        let pinIDs = Set(pageInventory.space.pinsByID.keys)
            .union(pageInventory.essentialPins.map(\.id))
        let current: @MainActor () -> SidebarLauncherRuntimeSnapshot = {
            selection.launcherRuntimeSnapshot(
                pinIDs: pinIDs,
                in: windowState
            )
        }

        SidebarScopedSnapshotReader(
            current: current,
            changes: inventoryUpdates.launcherResidenceChanges(
                windowID: windowState.id,
                spaceID: space.id
            )
            .map { _ in current() }
            .eraseToAnyPublisher(),
            delivery: .mainActorImmediate(
                deferral: presentedDropCompletionDeferral(
                    for: dragState
                )
            ),
            areEquivalent: ==,
            isActive: allowsInteractiveWork
        ) { launcherRuntime in
            sidebarPageContent(
                space: space,
                pageRenderMode: pageRenderMode,
                pageProfileId: pageProfileId,
                pageInventory: pageInventory,
                launcherRuntime: launcherRuntime,
                includesPinnedGrid: includesPinnedGrid,
                isTransitioningProfile: isTransitioningProfile,
                allowsInteractiveWork: allowsInteractiveWork
            )
        }
        .id(pinIDs)
    }

    @ViewBuilder
    private func sidebarPageContent(
        space: Space,
        pageRenderMode: SidebarPageRenderMode,
        pageProfileId: UUID?,
        pageInventory: SidebarPageInventorySnapshot,
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        includesPinnedGrid: Bool,
        isTransitioningProfile: Bool,
        allowsInteractiveWork: Bool
    ) -> some View {
        SidebarWindowSelectionSnapshotScope {
            VStack(spacing: 8) {
                if includesPinnedGrid && !windowState.isIncognito {
                    makeSidebarExtensionGrid(
                        profileId: pageProfileId,
                        pageRenderMode: pageRenderMode
                    )

                    makePinnedGrid(
                        spaceId: space.id,
                        profileId: pageProfileId,
                        inventory: pageInventory.space,
                        items: pageInventory.essentialPins,
                        launcherRuntime: launcherRuntime,
                        isTransitioningProfile: isTransitioningProfile,
                        pageRenderMode: pageRenderMode
                    )
                }

                makeSpaceView(
                    for: space,
                    inventory: pageInventory.space,
                    launcherRuntime: launcherRuntime,
                    renderMode: pageRenderMode.spaceRenderMode,
                    allowsInteraction: pageRenderMode == .interactive && allowsSidebarInteractiveWork
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sidebarPageGeometry(
                spaceId: space.id,
                profileId: pageProfileId,
                renderMode: pageRenderMode.geometryRenderMode,
                generation: dragGeometry.sidebarGeometryGeneration,
                isEnabled: allowsInteractiveWork
            )
        }
    }

    @ViewBuilder
    func makeSidebarExtensionGrid(
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork
        let surfaceStore = browserContext.extensionSurfaceStore

        SidebarScopedSnapshotReader(
            current: {
                sidebarExtensionGridSnapshot(profileID: profileId)
            },
            changes: surfaceStore.toolbarLayoutChanges(for: profileId).map {
                sidebarExtensionGridSnapshot(profileID: profileId)
            }
            .eraseToAnyPublisher(),
            areEquivalent: ==,
            isActive: allowsInteractiveWork
        ) { snapshot in
            SpaceSidebarExtensionGridContent(
                enabledExtensions: snapshot.enabledExtensions,
                slotCount: snapshot.slotCount,
                profileId: profileId,
                browserContext: browserContext,
                allowsInteractiveWork: allowsInteractiveWork
            )
        }
    }

    @ViewBuilder
    func makePinnedGrid(
        spaceId: UUID,
        profileId: UUID?,
        inventory pageInventory: SidebarSpaceInventorySnapshot,
        items: [ShortcutPin],
        launcherRuntime: SidebarLauncherRuntimeSnapshot,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork
        let shouldAnimate = SpaceSidebarChromeBindings.shouldAnimateEssentialsLayout(
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: isTransitioningProfile,
            pageRenderMode: pageRenderMode,
            allowsInteractiveWork: allowsInteractiveWork
        )

        PinnedGrid(
            width: windowState.sidebarContentWidth,
            browserContext: sidebarBrowserContext,
            inventory: pageInventory,
            items: items,
            launcherRuntime: launcherRuntime,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            spaceLifecycle: spaceLifecycle,
            spaceId: spaceId,
            profileId: profileId,
            isTransitioningProfile: isTransitioningProfile,
            dragPresentation: dragState.essentialsPresentation,
            animateLayout: shouldAnimate,
            reportsGeometry: allowsInteractiveWork,
            isAppKitInteractionEnabled: allowsInteractiveWork
        )
        .environment(windowState)
        .padding(.horizontal, 8)
    }

    private func sidebarPageInventorySnapshot(
        space: Space,
        profileID: UUID?
    ) -> SidebarPageInventorySnapshot {
        SidebarPageInventorySnapshot(
            space: windowState.isIncognito
                ? SidebarSpaceInventorySnapshot.ephemeral(
                    spaceID: space.id,
                    regularTabs: windowState.ephemeralTabs
                )
                : inventory.snapshot(for: space.id)
                    ?? SidebarSpaceInventorySnapshot.ephemeral(
                        spaceID: space.id,
                        regularTabs: []
                    ),
            essentialPins: profileID.map {
                spaceCatalog.essentialPins(profileID: $0)
            } ?? []
        )
    }

    private func sidebarExtensionGridSnapshot(
        profileID: UUID?
    ) -> SidebarExtensionGridSnapshot {
        let enabledExtensions = browserContext.extensionSurfaceStore
            .toolbarDisplaySnapshot.enabledExtensions
        return SidebarExtensionGridSnapshot(
            enabledExtensions: enabledExtensions,
            slotCount: browserContext.extensionToolbarActions.orderedPinnedToolbarSlots(
                enabledExtensions: enabledExtensions,
                profileID: profileID
            ).count
        )
    }
}

private struct SpaceSidebarExtensionGridContent: View {
    let enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
    let slotCount: Int
    let profileId: UUID?
    let browserContext: SidebarBrowserContext
    let allowsInteractiveWork: Bool

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        if SpaceSidebarChromeBindings.shouldShowSidebarExtensionGrid(slotCount: slotCount) {
            ExtensionActionView(
                extensions: enabledExtensions,
                layout: .sidebarGrid,
                profileId: profileId,
                browserContext: ExtensionActionBrowserContext(
                    extensionsModule: browserContext.extensionsModule,
                    windowState: windowState,
                    tabs: browserContext.extensionActionTabs,
                    profileAuthority: browserContext.profileAuthority,
                    settingsNavigation: browserContext.extensionSettingsNavigation
                )
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
}
