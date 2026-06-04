//
//  SpaceView.swift
//  Sumi
//

import SwiftUI

enum SpaceViewRenderMode {
    case interactive
    case transitionSnapshot

    var isInteractive: Bool {
        self == .interactive
    }

}

enum RegularTabRenderedItem: Hashable {
    case tab(UUID)
    case gap(UUID)
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
    let renderMode: SpaceViewRenderMode
    let allowsInteraction: Bool
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @ObservedObject var dragState = SidebarDragState.shared
    @State var isNewTabHovered = false
    @State var regularRenderedTabItems: [RegularTabRenderedItem] = []
    @State var regularGapHeights: [UUID: CGFloat] = [:]
    @State var regularInsertedTabHeights: [UUID: CGFloat] = [:]
    @State var regularDeferredRemovalGapIdsByTabId: [UUID: UUID] = [:]
    @State var regularSplitSegmentRemovalIds = Set<UUID>()
    @State var shortcutRestoreGaps: [ShortcutRestoreGap] = []
    @State var shortcutRestoreGapHeights: [UUID: CGFloat] = [:]
    @State var regularLayoutAnimationGeneration = 0
    @State var tabListVerticalScrollOffset: CGFloat = 0
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    @EnvironmentObject var splitManager: SplitViewManager

    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserManager.getSavedSidebarWidth(for: windowState)
        return max(fallbackWidth, 0)
    }

    var innerWidth: CGFloat {
        max(outerWidth - 16, 0)
    }

    var isInteractive: Bool {
        renderMode.isInteractive && allowsInteraction
    }


    var body: some View {
        let _ = browserManager.tabStructuralRevision

        VStack(spacing: 4) {
            SpaceTitle(space: space, isAppKitInteractionEnabled: isInteractive)

            mainContentContainer
        }
        .padding(.horizontal, 8)
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
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion,
              let gap = shortcutRestoreGap(for: item, in: group),
              shortcutRestoreGaps.firstIndex(where: { $0.pinId == gap.pinId && $0.container == gap.container }) == nil
        else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            shortcutRestoreGaps.append(gap)
            shortcutRestoreGapHeights[gap.id] = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.shortcutRestoreRevealStartDelay) {
            guard shortcutRestoreGaps.contains(where: { $0.id == gap.id }) else { return }
            withAnimation(SidebarDropMotion.contentLayout) {
                shortcutRestoreGapHeights[gap.id] = SidebarRowLayout.rowHeight
            }
        }
    }

    func performShortcutRestoreWithPreparedGap(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup,
        update: @escaping () -> Void
    ) {
        guard let gap = shortcutRestoreGap(for: item, in: group),
              let existingGap = shortcutRestoreGaps.first(where: { $0.pinId == gap.pinId && $0.container == gap.container })
        else {
            update()
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            update()
            shortcutRestoreGaps.removeAll { $0.id == existingGap.id }
            shortcutRestoreGapHeights.removeValue(forKey: existingGap.id)
        }
    }

    private func shortcutRestoreGap(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> ShortcutRestoreGap? {
        guard let member = shortcutRestoreMember(for: item, in: group),
              member.isShortcutBacked,
              let pinId = member.pinId,
              browserManager.tabManager.shortcutPin(by: pinId) != nil
        else {
            return nil
        }

        switch member.origin {
        case .spacePinned(let spaceId, let folderId, let index):
            guard spaceId == space.id else { return nil }
            if let folderId {
                guard browserManager.tabManager.folderSpaceId(for: folderId) == spaceId,
                      browserManager.tabManager.folder(by: folderId)?.isOpen == true
                else {
                    return nil
                }
                return ShortcutRestoreGap(
                    pinId: pinId,
                    container: .folder(folderId),
                    index: index
                )
            }
            return ShortcutRestoreGap(
                pinId: pinId,
                container: .spacePinned(spaceId),
                index: index
            )

        case .generatedSpacePinnedFromRegular(let spaceId, _):
            guard spaceId == space.id else { return nil }
            return ShortcutRestoreGap(
                pinId: pinId,
                container: .spacePinned(spaceId),
                index: browserManager.tabManager.topLevelSpacePinnedItems(for: spaceId).count
            )

        case .essential, .regular:
            return nil
        }
    }

    private func shortcutRestoreMember(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupMember? {
        if let pin = item.pin {
            return group.member(forPinId: pin.id) ?? group.member(for: pin.id)
        }
        if let tab = item.tab {
            if let pinId = tab.shortcutPinId {
                return group.member(forPinId: pinId) ?? group.member(for: tab.id)
            }
            return group.member(for: tab.id)
        }
        return nil
    }
}
