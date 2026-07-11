//
//  SpaceSidebarPageChrome.swift
//  Sumi
//
//

import SwiftUI

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
            onMuteTab: { $0.toggleMute() },
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
        let pageProfileId = resolvedPageProfileId(for: space)
        // Fallback-only identity change for unresolved AppKit owner/input graph recovery.
        let inputRecoveryGeneration = pageRenderMode == .interactive
            ? windowState.sidebarInputRecovery.generation
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
    func makeSidebarExtensionGrid(
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let enabledExtensions = chromeModel.extensionSurfaceStore.enabledExtensions
        let slots = browserContext.extensionToolbarSlots(enabledExtensions, profileId)
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork

        if SpaceSidebarChromeBindings.shouldShowSidebarExtensionGrid(slotCount: slots.count) {
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
    func makePinnedGrid(
        spaceId: UUID,
        profileId: UUID?,
        pageRenderMode: SidebarPageRenderMode
    ) -> some View {
        let allowsInteractiveWork = pageRenderMode == .interactive && allowsSidebarInteractiveWork
        let shouldAnimate = SpaceSidebarChromeBindings.shouldAnimateEssentialsLayout(
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isTransitioningProfile: browserContext.isTransitioningProfile(),
            pageRenderMode: pageRenderMode,
            allowsInteractiveWork: allowsInteractiveWork
        )

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

}
