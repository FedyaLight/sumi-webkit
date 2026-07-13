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

struct ShortcutRestoreGap: Identifiable, Hashable {
    enum Container: Hashable {
        case spacePinned(UUID)
        case folder(UUID)
    }

    let id = UUID()
    let pinId: UUID
    let container: Container
    let index: Int
}

struct SpaceView: View {
    let space: Space
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabs: any SidebarRegularTabsControlling
    let renderMode: SpaceViewRenderMode
    let allowsInteraction: Bool
    let scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    @Binding var isSidebarHovered: Bool
    @Environment(BrowserWindowState.self) var windowState
    @Environment(WindowRegistry.self) var windowRegistry
    @Environment(\.sumiSettings) var sumiSettings
    @EnvironmentObject var dragState: SidebarDragState
    @State var isNewTabHovered = false
    @State var regularTabsListAnimation = RegularTabsListAnimationState()
    @State var regularSplitSegmentRemovalIds = Set<UUID>()
    @State var shortcutRestoreGaps: [ShortcutRestoreGap] = []
    @State var shortcutRestoreAppearingGapIds = Set<UUID>()
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    let onScrollViewportChange: (UUID, SpaceSidebarSnapshotViewport) -> Void
    var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserContext.savedSidebarWidth(windowState)
        return max(fallbackWidth, 0)
    }

    var innerWidth: CGFloat {
        SpaceViewLayout.contentWidth(for: outerWidth)
    }

    var spaceTitleActions: SpaceTitleActions {
        SpaceTitleActionOwner(
            browserContext: browserContext,
            spaceLifecycle: spaceLifecycle,
            space: space,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext
        ).actions
    }

    var isInteractive: Bool {
        renderMode.isInteractive && allowsInteraction
    }

    var body: some View {
        VStack(spacing: 4) {
            SpaceTitle(
                space: space,
                actions: spaceTitleActions,
                isAppKitInteractionEnabled: isInteractive
            )

            mainContentContainer
        }
        .padding(.horizontal, SpaceViewLayout.horizontalPadding)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

extension SpaceView {
    func prepareShortcutRestoreGap(
        groupID: UUID,
        memberID: SplitMemberID
    ) {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion,
              let gap = shortcutRestoreGap(
                groupID: groupID,
                memberID: memberID
              ),
              shortcutRestoreGaps.firstIndex(where: { $0.pinId == gap.pinId && $0.container == gap.container }) == nil
        else {
            return
        }

        SidebarRowStagedReveal.insert(gap.id, into: &shortcutRestoreAppearingGapIds) {
            shortcutRestoreGaps.append(gap)
        }

        SidebarRowStagedReveal.reveal(
            [gap.id],
            in: $shortcutRestoreAppearingGapIds,
            animation: SidebarDropMotion.contentLayout
        ) {
            shortcutRestoreGaps.contains(where: { $0.id == gap.id })
        }
    }

    func performShortcutRestoreWithPreparedGap(
        groupID: UUID,
        memberID: SplitMemberID,
        update: @escaping () -> Void
    ) {
        guard let gap = shortcutRestoreGap(
            groupID: groupID,
            memberID: memberID
        ),
              let existingGap = shortcutRestoreGaps.first(where: { $0.pinId == gap.pinId && $0.container == gap.container })
        else {
            update()
            return
        }

        SidebarMotionTransaction.withoutAnimation {
            update()
            shortcutRestoreGaps.removeAll { $0.id == existingGap.id }
            _ = shortcutRestoreAppearingGapIds.remove(existingGap.id)
        }
    }

    private func shortcutRestoreGap(
        groupID: UUID,
        memberID: SplitMemberID
    ) -> ShortcutRestoreGap? {
        SpaceShortcutRestorePlanner(
            inventory: inventory,
            space: space
        ).shortcutRestoreGap(groupID: groupID, memberID: memberID)
    }

    var elevatedFolderIds: Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            selection: selection,
            windowState: windowState
        ).elevatedFolderIds
    }
}
