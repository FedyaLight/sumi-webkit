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
    let scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @EnvironmentObject var dragState: SidebarDragState
    @EnvironmentObject var locationTracker: SidebarDragLocationTracker
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
    @EnvironmentObject var splitManager: SplitViewManager

    var outerWidth: CGFloat {
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

    var spaceTitleActions: SpaceTitleActions {
        SpaceTitleActions(
            canDeleteSpace: browserManager.tabManager.spaces.count > 1,
            renameSpace: { newName in
                do {
                    try browserManager.tabManager.renameSpace(
                        spaceId: space.id,
                        newName: newName
                    )
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to rename space \(space.id.uuidString):", error)
                }
            },
            updateSpaceIcon: { icon in
                do {
                    try browserManager.tabManager.updateSpaceIcon(spaceId: space.id, icon: icon)
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to update space icon \(space.id.uuidString):", error)
                }
            },
            persistCommittedEmoji: { _ in
                browserManager.tabManager.markAllSpacesStructurallyDirty()
                browserManager.tabManager.scheduleStructuralPersistence()
            },
            editSpace: {
                browserManager.showSpaceEditor(
                    for: space,
                    in: windowState,
                    themeContext: themeContext,
                    source: windowState.resolveSidebarPresentationSource()
                )
            },
            changeTheme: {
                browserManager.showGradientEditor(
                    for: space,
                    source: windowState.resolveSidebarPresentationSource()
                )
            },
            deleteSpace: {
                SpaceDeletionConfirmationPresenter.confirmDelete(
                    space: space,
                    browserManager: browserManager,
                    window: windowState.window
                )
            }
        )
    }

    var isInteractive: Bool {
        renderMode.isInteractive && allowsInteraction
    }

    var body: some View {
        SidebarTabStructuralRevisionReader(browserManager: browserManager) { _ in
            VStack(spacing: 4) {
                SpaceTitle(
                    space: space,
                    actions: spaceTitleActions,
                    isAppKitInteractionEnabled: isInteractive
                )

                mainContentContainer
            }
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

private struct SidebarTabStructuralRevisionReader<Content: View>: View {
    @ObservedObject var browserManager: BrowserManager
    @ViewBuilder let content: (UInt) -> Content

    var body: some View {
        content(browserManager.tabStructuralRevision)
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

        SidebarMotionTransaction.withoutAnimation {
            update()
            shortcutRestoreGaps.removeAll { $0.id == existingGap.id }
            _ = shortcutRestoreAppearingGapIds.remove(existingGap.id)
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

    var elevatedFolderIds: Set<UUID> {
        var elevated = Set<UUID>()
        let tabManager = browserManager.tabManager

        // 1. If a shortcut pin is selected
        if let currentShortcutPinId = windowState.currentShortcutPinId {
            if let pin = tabManager.shortcutPin(by: currentShortcutPinId), pin.spaceId == space.id {
                var currentFolderId = pin.folderId
                while let folderId = currentFolderId {
                    if !elevated.insert(folderId).inserted { break }
                    currentFolderId = tabManager.folder(by: folderId)?.parentFolderId
                }
            }
        }

        // 2. If a regular tab is selected
        if let currentTabId = windowState.currentTabId {
            // Check if it's the live tab of a shortcut pin
            let allPins = tabManager.spacePinnedPins(for: space.id)
            for pin in allPins {
                if tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)?.id == currentTabId {
                    var currentFolderId = pin.folderId
                    while let folderId = currentFolderId {
                        if !elevated.insert(folderId).inserted { break }
                        currentFolderId = tabManager.folder(by: folderId)?.parentFolderId
                    }
                }
            }

            // Check if it's in a hosted split group
            let allSplitGroups = tabManager.shortcutHostedSplitGroups(for: space.id)
            for group in allSplitGroups {
                if group.contains(currentTabId) {
                    if let folderId = tabManager.shortcutHostedSplitGroupFolderId(group, in: space.id) {
                        var currentFolderId: UUID? = folderId
                        while let fid = currentFolderId {
                            if !elevated.insert(fid).inserted { break }
                            currentFolderId = tabManager.folder(by: fid)?.parentFolderId
                        }
                    }
                }
            }
        }

        return elevated
    }
}
