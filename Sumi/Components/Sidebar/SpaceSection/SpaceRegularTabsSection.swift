//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import SumiDomain
import SwiftUI

enum SpaceRegularExternalDropGapPlacement: Equatable {
    case top
    case bottom
}

let regularDragProjectionGapID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

struct SpaceRegularTabsListProjection {
    struct DragSnapshot {
        let isDropProjectionActive: Bool
        let sourceContainer: TabDragManager.DragContainer?
        let dragItemID: UUID?
        let hoveredSlot: DropZoneSlot?
        let externalDropGap: SidebarRegularExternalDropGap?
        let isCompletingDrop: Bool
        let hidesCommittedCrossContainerPlaceholder: Bool
    }

    let spaceID: UUID
    let tabIDs: [UUID]
    let showsBottomNewTabButton: Bool
    let drag: DragSnapshot

    var sourceID: UUID? {
        guard drag.isDropProjectionActive,
              drag.sourceContainer == .spaceRegular(spaceID),
              let dragItemID = drag.dragItemID,
              tabIDs.contains(dragItemID)
        else { return nil }
        return dragItemID
    }

    var externalDropGapPlacement: SpaceRegularExternalDropGapPlacement? {
        guard let gap = drag.externalDropGap, gap.spaceId == spaceID else { return nil }
        switch gap.edge {
        case .top: return .top
        case .bottom: return showsBottomNewTabButton ? .bottom : nil
        }
    }

    var insertionIndex: Int? {
        guard drag.isDropProjectionActive,
              case .spaceRegular(let hoveredSpaceID, let slot) = drag.hoveredSlot,
              hoveredSpaceID == spaceID,
              externalDropGapPlacement == nil
        else { return nil }

        if SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
            isCompletingDrop: drag.isCompletingDrop,
            sourceContainer: drag.sourceContainer,
            targetContainer: .spaceRegular(spaceID)
        ) {
            return nil
        }
        guard !drag.hidesCommittedCrossContainerPlaceholder else { return nil }
        return slot
    }

    var projectedItems: [ProjectedItem<UUID>] {
        SidebarDropProjection.projectedItems(
            itemIDs: tabIDs,
            removesSourceID: sourceID,
            insertsPlaceholderAt: insertionIndex
        )
    }

    var usesProjectedDropLayout: Bool {
        sourceID != nil || insertionIndex != nil
    }

    func displayItems(fallback: [RegularTabRenderedItem]) -> [RegularTabRenderedItem] {
        guard usesProjectedDropLayout else { return fallback }
        return projectedItems.map { item in
            switch item {
            case .item(let tabID): return .tab(tabID)
            case .placeholder: return .gap(regularDragProjectionGapID)
            }
        }
    }
}

struct SpaceRegularTabsInteractionSession {
    var listAnimation = RegularTabsListAnimationState()
}

struct SpaceRegularDragSnapshot {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let geometryGeneration: Int
    let shouldAnimateDropLayout: Bool
    let projection: SpaceRegularTabsListProjection.DragSnapshot

    @MainActor
    init(dragState: SidebarDragState, spaceID: UUID, tabs: [Tab]) {
        let dragItemID = dragState.projectionDragItemId
        let targetContainsDraggedItem = dragItemID.map { id in
            tabs.contains { $0.id == id }
        } ?? false

        isDragging = dragState.isDragging
        isCompletingDrop = dragState.isCompletingDrop
        activeDragItemID = dragState.activeDragItemId
        geometryGeneration = dragState.sidebarGeometryGeneration
        shouldAnimateDropLayout = dragState.shouldAnimateDropLayout
        projection = .init(
            isDropProjectionActive: dragState.isDropProjectionActive,
            sourceContainer: dragState.projectionDragScope?.sourceContainer,
            dragItemID: dragItemID,
            hoveredSlot: dragState.projectionHoveredSlot,
            externalDropGap: dragState.regularExternalDropGap,
            isCompletingDrop: dragState.isCompletingDrop,
            hidesCommittedCrossContainerPlaceholder: dragItemID != nil
                && dragState.shouldHideCommittedCrossContainerPlaceholder(
                    into: .spaceRegular(spaceID),
                    targetAlreadyContainsDraggedItem: targetContainsDraggedItem
                )
        )
    }
}

private struct SpaceRegularDragSnapshotReader<Content: View>: View {
    let spaceID: UUID
    let tabs: [Tab]
    @ViewBuilder let content: (SpaceRegularDragSnapshot) -> Content

    @EnvironmentObject private var dragState: SidebarDragState

    var body: some View {
        content(SpaceRegularDragSnapshot(dragState: dragState, spaceID: spaceID, tabs: tabs))
    }
}

/// State/composition root for regular tabs. Row rendering lives in
/// `SpaceRegularTabsListView`; hover state lives with the new-tab control.
struct SpaceRegularTabsView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    @Binding var isSidebarHovered: Bool

    @State private var interactionSession = SpaceRegularTabsInteractionSession()
    @Environment(BrowserWindowState.self) private var windowState

    private var tabs: [Tab] {
        regularTabCatalog.tabs(in: space, windowState: windowState)
    }

    var body: some View {
        SpaceRegularDragSnapshotReader(spaceID: space.id, tabs: tabs) { dragSnapshot in
            SpaceRegularTabsContentView(
                space: space,
                inventory: inventory,
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
                isSidebarHovered: $isSidebarHovered,
                interactionSession: $interactionSession
            )
        }
    }
}

private struct SpaceRegularTabsContentView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
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
    @Binding var isSidebarHovered: Bool
    @Binding var interactionSession: SpaceRegularTabsInteractionSession

    @Environment(\.sumiSettings) private var sumiSettings

    private var showsNewTabButtonInList: Bool {
        sumiSettings.showNewTabButtonInTabList
    }

    private var showsNewTabButtonAtTop: Bool {
        sumiSettings.tabListNewTabButtonPosition == .top
    }

    private var showsBottomNewTabButton: Bool {
        showsNewTabButtonInList && !showsNewTabButtonAtTop
    }

    private var projection: SpaceRegularTabsListProjection {
        SpaceRegularTabsListProjection(
            spaceID: space.id,
            tabIDs: tabs.map(\.id),
            showsBottomNewTabButton: showsBottomNewTabButton,
            drag: dragSnapshot.projection
        )
    }

    private var renderedRowCount: Int {
        projection.displayItems(fallback: interactionSession.listAnimation.renderedItems).count
    }

    var body: some View {
        VStack(spacing: 0) {
            if projection.externalDropGapPlacement == .top {
                dropGap
            }

            SpaceSeparator(
                hasTabs: regularTabCatalog.hasPersistedTabs(in: space),
                isHovering: $isSidebarHovered
            ) {
                regularTabLifecycleCommands.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                if showsNewTabButtonInList && showsNewTabButtonAtTop {
                    SpaceRegularNewTabRow(
                        space: space,
                        browserContext: browserContext,
                        isInteractive: isInteractive
                    )
                    .padding(.top, 4)
                }

                SpaceRegularTabsListView(
                    space: space,
                    inventory: inventory,
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
                    projection: projection,
                    dragSnapshot: dragSnapshot,
                    interactionSession: $interactionSession
                )
                .sidebarRegularListHitGeometry(
                    for: space.id,
                    itemCount: renderedRowCount,
                    generation: dragSnapshot.geometryGeneration,
                    isEnabled: isInteractive
                )

                if projection.externalDropGapPlacement == .bottom {
                    dropGap
                }

                if showsBottomNewTabButton {
                    SpaceRegularNewTabRow(
                        space: space,
                        browserContext: browserContext,
                        isInteractive: isInteractive
                    )
                }
            }
            .padding(.top, 8)

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
        .animation(
            isInteractive && dragSnapshot.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projection.externalDropGapPlacement
        )
        .transaction { transaction in
            if dragSnapshot.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var dropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
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
        SidebarHoverChrome.displayHover(
            isHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    var body: some View {
        Button(action: openNewTab) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("New Tab")
                Spacer()
            }
            .foregroundStyle(tokens.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: displaysHover ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displaysHover,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sidebarDDGHover($isHovered, isEnabled: isInteractive)
        .sidebarZenPressEffect(sourceID: sourceID, isEnabled: isInteractive)
        .accessibilityIdentifier(sourceID)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isInteractive,
            sourceID: sourceID,
            action: openNewTab
        )
    }

    private func openNewTab() {
        guard isInteractive else { return }
        browserContext.floatingBarCommit.openNewTabSurface(in: windowState)
    }
}
