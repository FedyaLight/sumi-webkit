//
//  SpaceSidebarPageChrome.swift
//  Sumi
//
//

import SwiftUI

struct SidebarPageInventorySnapshot {
    let space: SidebarSpaceInventorySnapshot
    let essentialPins: [ShortcutPin]
}

private struct SidebarExtensionGridSnapshot {
    let enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
    let slotCount: Int
}

extension SpacesSideBarView {
    func spacesPageView(spaces: [Space]) -> some View {
        Group {
            if spaces.isEmpty {
                SpaceSidebarEmptySpacesView(onCreateSpace: beginSpaceCreationMode)
            } else {
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
        }
    }
    @ViewBuilder
    func makeSpaceView(
        for space: Space,
        inventory pageInventory: SidebarSpaceInventorySnapshot,
        renderMode: SpaceViewRenderMode,
        allowsInteraction: Bool
    ) -> some View {
        SpaceView(
            space: space,
            browserContext: sidebarBrowserContext,
            inventory: pageInventory,
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
            renderMode: renderMode,
            allowsInteraction: allowsInteraction,
            scrollHoverCoordinator: scrollHoverCoordinator,
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
            isActive: allowsInteractiveWork
        ) { pageInventory in
            sidebarPageContent(
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
    private func sidebarPageContent(
        space: Space,
        pageRenderMode: SidebarPageRenderMode,
        pageProfileId: UUID?,
        pageInventory: SidebarPageInventorySnapshot,
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
                        isTransitioningProfile: isTransitioningProfile,
                        pageRenderMode: pageRenderMode
                    )
                }

                makeSpaceView(
                    for: space,
                    inventory: pageInventory.space,
                    renderMode: pageRenderMode.spaceRenderMode,
                    allowsInteraction: pageRenderMode == .interactive && allowsSidebarInteractiveWork
                )
            }
            .animation(
                allowsInteractiveWork ? .easeInOut(duration: 0.18) : nil,
                value: dragState.hoveredSlot
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sidebarPageGeometry(
                spaceId: space.id,
                profileId: pageProfileId,
                renderMode: pageRenderMode.geometryRenderMode,
                generation: dragState.sidebarGeometryGeneration,
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
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            spaceLifecycle: spaceLifecycle,
            spaceId: spaceId,
            profileId: profileId,
            isTransitioningProfile: isTransitioningProfile,
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
