//
//  SpaceView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

enum SpaceViewRenderMode {
    case interactive
    case transitionSnapshot

    var isInteractive: Bool {
        self == .interactive
    }

    func resolvesInteraction(allowsInteraction: Bool) -> Bool {
        isInteractive && allowsInteraction
    }
}

enum SpaceViewLayout {
    static let horizontalPadding: CGFloat = ChromeLayoutTokens.sidebarContentHorizontalPadding
    static let horizontalPaddingTotal: CGFloat = horizontalPadding * 2
    static let scrollIndicatorBoundaryInset: CGFloat = 3
    static let scrollIndicatorTrailingProjection: CGFloat = horizontalPadding - scrollIndicatorBoundaryInset

    static func contentWidth(for outerWidth: CGFloat) -> CGFloat {
        max(outerWidth - horizontalPaddingTotal, 0)
    }
}

struct SpaceView: View {
    let space: Space
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let pinnedDragPresentation: SidebarPinnedDragPresentation
    let renderMode: SpaceViewRenderMode
    let allowsInteraction: Bool
    let restoredScrollViewport: SpaceSidebarSnapshotViewport?
    let scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    let persistWindowSession: (BrowserWindowState) -> Void
    @Binding var isSidebarHovered: Bool
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection
    @Environment(\.sumiSettings) private var sumiSettings

    let onScrollViewportChange: (UUID, SpaceSidebarSnapshotViewport) -> Void
    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserContext.sidebarPresentation.savedSidebarWidth(
            for: windowState
        )
        return max(fallbackWidth, 0)
    }

    private var innerWidth: CGFloat {
        SpaceViewLayout.contentWidth(for: outerWidth)
    }

    private var spaceTitleActions: SpaceTitleActions {
        SpaceTitleActionOwner(
            browserContext: browserContext,
            spaceLifecycle: spaceLifecycle,
            space: space,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext
        ).actions
    }

    private var isInteractive: Bool {
        renderMode.resolvesInteraction(allowsInteraction: allowsInteraction)
    }

    private var pinnedSection: SpacePinnedSectionView {
        SpacePinnedSectionView(
            space: space,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            browserContext: browserContext,
            dragPresentation: pinnedDragPresentation,
            isInteractive: isInteractive,
            onSetPinnedContentCollapsed: setPinnedContentCollapsed
        )
    }

    private var hasPinnedContent: Bool {
        !windowState.isIncognito && !inventory.topLevelItems.isEmpty
    }

    private var isPinnedContentCollapsed: Bool {
        hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var pinnedStickyOwner: SidebarSpacePinnedStickyProjectionOwner {
        SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: inventory,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    private var regularTabsSection: SpaceRegularTabsView {
        SpaceRegularTabsView(
            space: space,
            selection: selection,
            regularTabCatalog: regularTabCatalog,
            regularTabTargets: regularTabTargets,
            regularTabLifecycleCommands: regularTabLifecycleCommands,
            regularTabShortcutCommands: regularTabShortcutCommands,
            regularTabPlacementCommands: regularTabPlacementCommands,
            browserContext: browserContext,
            isInteractive: isInteractive,
            innerWidth: innerWidth,
            hasPinnedContent: hasPinnedContent,
            isSidebarHovered: $isSidebarHovered
        )
    }

    private var selectedItemRevealPath: SidebarSelectedItemRevealPath? {
        SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        ).selectedItemRevealPath
    }

    // Drop commits are no longer suppressed at the surface level: the list
    // sections settle rows into place (SidebarMotionPolicy.dropSettleAnimation)
    // while the essentials grid keeps its own commit suppression in PinnedGrid.
    var body: some View {
        VStack(spacing: 4) {
            SpaceTitle(
                space: space,
                actions: spaceTitleActions,
                hasPinnedContent: hasPinnedContent,
                isPinnedContentCollapsed: isPinnedContentCollapsed,
                onTogglePinnedContent: {
                    setPinnedContentCollapsed(!isPinnedContentCollapsed)
                },
                isAppKitInteractionEnabled: isInteractive
            )

            SpaceScrollChromeSurface(
                isInteractive: isInteractive,
                spaceId: space.id,
                selectedItemRevealPath: selectedItemRevealPath,
                selection: sidebarSelection,
                selectedItemRevealMode: SidebarMotionPolicy.currentMode(
                    reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
                ),
                restoredViewport: restoredScrollViewport,
                scrollHoverCoordinator: scrollHoverCoordinator,
                outerWidth: outerWidth,
                onViewportChange: { viewport in
                    onScrollViewportChange(space.id, viewport)
                }
            ) {
                SpaceSectionsView(
                    pinnedSection: pinnedSection,
                    regularTabsSection: regularTabsSection
                )
            }
        }
        .padding(.horizontal, SpaceViewLayout.horizontalPadding)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
    }

    private func setPinnedContentCollapsed(_ isCollapsed: Bool) {
        guard !isCollapsed || hasPinnedContent else { return }
        let collapseState = windowState.sidebarSpacePinnedCollapse
        guard collapseState.isCollapsed(space.id) != isCollapsed else { return }

        if isCollapsed {
            _ = collapseState.setCollapsed(true, for: space.id)
            pinnedStickyOwner.handleCollapse()
        } else {
            pinnedStickyOwner.handleExpand()
            _ = collapseState.setCollapsed(false, for: space.id)
        }
        persistWindowSession(windowState)
    }
}
