//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import SumiDomain
import SwiftUI

struct SpaceRegularTabsInteractionSession {
    var listAnimation = RegularTabsListAnimationState()
}

struct SpaceRegularDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let splitPairingTarget: SidebarSplitPairingTarget?
    let geometryGeneration: Int

    @MainActor
    init(dragState: SidebarDragState, geometryGeneration: Int) {
        isDragging = dragState.isDragging
        isCompletingDrop = dragState.isCompletingDrop
        activeDragItemID = dragState.activeDragItemId
        splitPairingTarget = dragState.projectionSplitPairingTarget
        self.geometryGeneration = geometryGeneration
    }
}

private struct SpaceRegularDragSnapshotReader<Content: View>: View {
    @ViewBuilder let content: (SpaceRegularDragSnapshot) -> Content

    @EnvironmentObject private var dragState: SidebarDragState
    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    var body: some View {
        content(SpaceRegularDragSnapshot(
            dragState: dragState,
            geometryGeneration: dragGeometry.sidebarGeometryGeneration
        ))
    }
}

/// State/composition root for regular tabs. Row rendering lives in
/// `SpaceRegularTabsListView`; hover state lives with the new-tab control.
struct SpaceRegularTabsView: View {
    let space: Space
    let selection: SidebarWindowSelectionQuery
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    let hasPinnedContent: Bool
    @Binding var isSidebarHovered: Bool

    @State private var interactionSession = SpaceRegularTabsInteractionSession()
    @Environment(BrowserWindowState.self) private var windowState

    private var tabs: [Tab] {
        regularTabCatalog.tabs(in: space, windowState: windowState)
    }

    var body: some View {
        SpaceRegularDragSnapshotReader { dragSnapshot in
            SpaceRegularTabsContentView(
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
                tabs: tabs,
                dragSnapshot: dragSnapshot,
                hasPinnedContent: hasPinnedContent,
                isSidebarHovered: $isSidebarHovered,
                interactionSession: $interactionSession
            )
        }
    }
}

private struct SpaceRegularTabsContentView: View {
    let space: Space
    let selection: SidebarWindowSelectionQuery
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    let tabs: [Tab]
    let dragSnapshot: SpaceRegularDragSnapshot
    let hasPinnedContent: Bool
    @Binding var isSidebarHovered: Bool
    @Binding var interactionSession: SpaceRegularTabsInteractionSession

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var boundaryLayout: SpaceTabSectionBoundaryLayout {
        SpaceTabSectionBoundaryLayout(
            hasPinnedContent: hasPinnedContent,
            regularTabCount: tabs.count
        )
    }

    private var separatorCollapseAnimation: Animation? {
        SidebarMotionPolicy.pinnedSeparatorCollapseAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
            )
        )
    }

    private var showsNewTabButtonInList: Bool {
        sumiSettings.showNewTabButtonInTabList
    }

    private var showsNewTabButtonAtTop: Bool {
        sumiSettings.tabListNewTabButtonPosition == .top
    }

    private var showsBottomNewTabButton: Bool {
        showsNewTabButtonInList && !showsNewTabButtonAtTop
    }

    private var renderedRowCount: Int {
        interactionSession.listAnimation.renderedRows.count
    }

    var body: some View {
        VStack(spacing: 0) {
            SpaceTabSectionBoundary(layout: boundaryLayout) {
                SpaceSeparator(
                    hasTabs: regularTabCatalog.hasPersistedTabs(in: space),
                    isHovering: $isSidebarHovered
                ) {
                    regularTabLifecycleCommands.clearRegularTabs(for: space.id)
                }
                .padding(.horizontal, 8)
            }
            .animation(
                separatorCollapseAnimation,
                value: boundaryLayout.showsSeparator
            )

            contentColumn

            Color.clear.frame(
                height: renderedRowCount == 0 && !interactionSession.listAnimation.hasRemovalInFlight
                    ? 48
                    : 24
            )
        }
        .sidebarSectionGeometry(
            for: .spaceRegular,
            spaceId: space.id,
            generation: dragSnapshot.geometryGeneration,
            isEnabled: isInteractive
        )
    }

    /// Rows + New-Tab button at the uniform `SidebarRowLayout.rowGap` rhythm. Uses
    /// `spacing: 0` with explicit gaps inserted only when regular rows exist, so an
    /// empty list leaves no phantom gap and the New-Tab button sits at the row
    /// rhythm below the boundary.
    @ViewBuilder
    private var contentColumn: some View {
        VStack(spacing: 0) {
            if showsNewTabButtonInList && showsNewTabButtonAtTop {
                newTabRow
                if !tabs.isEmpty {
                    Color.clear.frame(height: SidebarRowLayout.rowGap)
                }
            }

            SpaceRegularTabsListView(
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
                tabs: tabs,
                dragSnapshot: dragSnapshot,
                interactionSession: $interactionSession
            )

            if showsBottomNewTabButton {
                if !tabs.isEmpty {
                    Color.clear.frame(height: SidebarRowLayout.rowGap)
                }
                newTabRow
            }
        }
    }

    private var newTabRow: SpaceRegularNewTabRow {
        SpaceRegularNewTabRow(
            space: space,
            browserContext: browserContext,
            isInteractive: isInteractive
        )
    }
}

private struct SpaceRegularNewTabRow: View {
    let space: Space
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool

    @State private var isHovered = false
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var sourceID: String {
        "space-new-tab-\(space.id.uuidString)"
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var displaysHover: Bool {
        isHovered
    }

    var body: some View {
        Button(action: openNewTab) {
            SidebarNewTabRowLabel(tokens: tokens)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: displaysHover ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displaysHover,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sidebarHover($isHovered, isEnabled: isInteractive)
        .sidebarZenPressEffect(sourceID: sourceID)
        .accessibilityIdentifier(sourceID)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isInteractive,
            sourceID: sourceID,
            action: openNewTab
        )
    }

    private func openNewTab() {
        guard isInteractive else { return }
        browserContext.commandPaletteCommit.openNewTabSurface(in: windowState)
    }
}
