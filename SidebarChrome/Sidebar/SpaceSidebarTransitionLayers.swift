//
//  SpaceSidebarTransitionLayers.swift
//  Sumi
//
//

import SwiftUI

extension SpacesSideBarView {
    @ViewBuilder
    func spaceTransitionContainer(
        spaces: [Space],
        size: CGSize
    ) -> some View {
        let width = max(size.width, 1)
        let travelProgress = transitionState.progress

        ZStack(alignment: .topLeading) {
            if SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: transitionState),
               let sourceSpace = space(for: transitionState.sourceSpaceId, in: spaces),
               let destinationSpace = space(for: transitionState.destinationSpaceId, in: spaces),
               let snapshot = transitionSnapshot,
               snapshot.matches(transitionState) {
                // The snapshot builder already decided whether essentials are
                // shared across the transition (same profile, non-incognito);
                // it exposes that as `stationaryEssentials`. Branch on it here
                // instead of recomputing the profile comparison so the render
                // path can't diverge from the captured snapshot.
                Group {
                    if snapshot.stationaryEssentials != nil {
                        sharedEssentialsTransitionContainer(
                            sourceSpace: sourceSpace,
                            destinationSpace: destinationSpace,
                            snapshot: snapshot,
                            width: width,
                            travelProgress: travelProgress
                        )
                    } else {
                        transitionLayer(
                            for: sourceSpace,
                            snapshot: snapshot,
                            width: width,
                            offsetX: sourceOffsetX(width: width),
                            opacity: sourceOpacity(for: travelProgress),
                            zIndex: 0,
                            includesTopSidebarContent: true
                        )

                        transitionLayer(
                            for: destinationSpace,
                            snapshot: snapshot,
                            width: width,
                            offsetX: destinationOffsetX(width: width),
                            opacity: destinationOpacity(for: travelProgress),
                            zIndex: 1,
                            includesTopSidebarContent: true
                        )
                    }
                }
                // The transition layers just mounted at progress 0; kick off the
                // click slide now that SwiftUI has a committed frame to animate
                // from. No-op for swipe and after the slide has started.
                .onAppear {
                    transitionCoordinator.startPendingClickAnimation(
                        context: makeTransitionContext(spaces: spaces)
                    )
                }
            } else {
                committedSidebarPage(spaces: spaces, width: width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func committedSidebarPage(
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
    func sharedEssentialsTransitionContainer(
        sourceSpace: Space,
        destinationSpace: Space,
        snapshot: SpaceSidebarTransitionSnapshot,
        width: CGFloat,
        travelProgress: Double
    ) -> some View {
        VStack(spacing: 8) {
            if let extensionActions = snapshot.source.extensionActions {
                ExtensionActionSnapshotGrid(
                    snapshot: extensionActions,
                    tokens: themeContext.tokens(settings: sumiSettings)
                )
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
            }

            if let essentials = snapshot.stationaryEssentials {
                EssentialsSnapshotGrid(
                    snapshot: essentials,
                    width: BrowserWindowState.sidebarContentWidth(for: width),
                    tokens: themeContext.tokens(settings: sumiSettings)
                )
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
            }

            ZStack(alignment: .topLeading) {
                transitionLayer(
                    for: sourceSpace,
                    snapshot: snapshot,
                    width: width,
                    offsetX: sourceOffsetX(width: width),
                    opacity: sourceOpacity(for: travelProgress),
                    zIndex: 0,
                    includesTopSidebarContent: false
                )

                transitionLayer(
                    for: destinationSpace,
                    snapshot: snapshot,
                    width: width,
                    offsetX: destinationOffsetX(width: width),
                    opacity: destinationOpacity(for: travelProgress),
                    zIndex: 1,
                    includesTopSidebarContent: false
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    func transitionLayer(
        for space: Space,
        snapshot: SpaceSidebarTransitionSnapshot,
        width: CGFloat,
        offsetX: CGFloat,
        opacity: Double,
        zIndex: Double,
        includesTopSidebarContent: Bool
    ) -> some View {
        transitionLayerContent(
            for: space,
            snapshot: snapshot,
            width: width,
            includesTopSidebarContent: includesTopSidebarContent
        )
            .frame(width: width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .geometryGroup()
            .offset(x: offsetX)
            .opacity(opacity)
            .zIndex(zIndex)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    func transitionLayerContent(
        for space: Space,
        snapshot: SpaceSidebarTransitionSnapshot,
        width: CGFloat,
        includesTopSidebarContent: Bool
    ) -> some View {
        if let pageSnapshot = snapshot.page(for: space.id) {
            // Resolve tokens from the page's own static theme so a sliding page
            // keeps its space's colors instead of freezing an interpolated
            // window theme that snaps at commit.
            let pageThemeContext = SpaceSidebarSnapshotThemeResolver.pageThemeContext(
                for: space,
                baseContext: themeContext,
                settings: sumiSettings,
                isIncognito: windowState.isIncognito
            )
            SpaceTransitionSnapshotPageView(
                snapshot: pageSnapshot,
                includesTopSidebarContent: includesTopSidebarContent,
                width: width,
                tokens: pageThemeContext.tokens(settings: sumiSettings),
                themeContext: pageThemeContext
            )
            .id(pageSnapshot.spaceId)
        }
    }
    func sourceOpacity(for travelProgress: Double) -> Double {
        transitionCoordinator.sourceOpacity(for: travelProgress)
    }

    func destinationOpacity(for travelProgress: Double) -> Double {
        transitionCoordinator.destinationOpacity(for: travelProgress)
    }

    func sourceOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.sourceOffsetX(width: width)
    }

    func destinationOffsetX(width: CGFloat) -> CGFloat {
        transitionCoordinator.destinationOffsetX(width: width)
    }

    func committedSpaceId(in spaces: [Space]) -> UUID? {
        transitionCoordinator.committedSpaceId(in: makeTransitionContext(spaces: spaces))
    }

    func space(for id: UUID?, in spaces: [Space]) -> Space? {
        transitionCoordinator.space(for: id, in: makeTransitionContext(spaces: spaces))
    }

}
