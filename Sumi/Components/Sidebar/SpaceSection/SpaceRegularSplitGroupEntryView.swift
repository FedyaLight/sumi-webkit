//
//  SpaceRegularSplitGroupEntryView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Behavior boundary for one split group hosted by the regular-tab list.
/// The list owns row ordering and animation state; this leaf resolves only the
/// group's segments and routes their exact actions.
struct SpaceRegularSplitGroupEntryView: View {
    let group: SplitGroup
    let space: Space
    let tabByID: [UUID: Tab]
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let contentMutationAnimation: Animation?
    let tabActionOwner: SpaceRegularTabActionOwner
    let onCloseRegularTab: (Tab) -> Void
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession
    @Binding var splitSegmentRemovalIDs: Set<UUID>

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var splitResolver: RegularSplitSegmentResolver {
        RegularSplitSegmentResolver(space: space, isInteractive: isInteractive)
    }

    private var items: [SplitGroupSidebarItem] {
        splitResolver.splitGroupItems(
            for: group,
            tabByID: tabByID,
            regularTab: { regularTabCatalog.tab(for: $0) },
            shortcutLiveTab: { selection.liveTab(for: $0, in: windowState) },
            shortcutPin: { regularTabTargets.shortcutPin(by: $0) }
        )
    }

    var body: some View {
        SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: space.id,
            isAppKitInteractionEnabled: isInteractive,
            faviconImageReader: browserContext.faviconImageReader,
            splitLayout: browserContext.splitLayout,
            emptySplitCreation: browserContext.emptySplitCreation,
            segmentAction: { item in splitResolver.action(for: item, in: group) },
            dragSource: splitSegmentDragSource,
            contextMenuEntries: splitContextMenuEntries,
            onActivateMember: activateMember,
            onSegmentActionAnimationStart: prepareSegmentActionAnimation,
            onSegmentAction: performSegmentAction,
            onSegmentMiddleClick: performSegmentMiddleClick
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: SidebarSelectionElevation.splitGroupIsSelected(
                    group,
                    selectedGroupID: sidebarSelection.splitSelection?.groupID
                )
            )
        )
    }

    private func splitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        splitResolver.dragSource(
            for: item,
            in: group,
            faviconImageReader: browserContext.faviconImageReader,
            shortcutPin: { regularTabTargets.shortcutPin(by: $0) },
            onActivateMember: {
                browserContext.splitFocusCommands.focusGroup(
                    group.id,
                    item.id,
                    windowState.id
                )
            }
        )
    }

    private func splitContextMenuEntries(_ tab: Tab) -> [SidebarContextMenuEntry] {
        tabActionOwner.contextMenuEntries(
            for: tab,
            close: { onCloseRegularTab(tab) }
        )
    }

    private func activateMember(_ memberID: SplitMemberID) {
        browserContext.splitFocusCommands.focusGroup(
            group.id,
            memberID,
            windowState.id
        )
    }

    private func prepareSegmentActionAnimation(_ memberID: SplitMemberID) {
        guard case .shortcutPin = memberID else { return }
        prepareShortcutRestoreGap(memberID: memberID)
    }

    private func performSegmentAction(_ memberID: SplitMemberID) {
        if case .shortcutPin = memberID {
            performShortcutRestoreWithPreparedGap(memberID: memberID) {
                SidebarMotionTransaction.withoutAnimation {
                    browserContext.splitFocusCommands.restoreMember(
                        group.id,
                        memberID,
                        windowState.id
                    )
                }
            }
            return
        }

        guard case .regularTab(let tabID) = memberID else { return }
        SidebarMotionTransaction.withoutAnimation {
            splitSegmentRemovalIDs.insert(tabID)
            browserContext.splitCloseCommand.closeMember(
                group.id,
                memberID,
                windowState.id
            )
        }
    }

    private func performSegmentMiddleClick(_ memberID: SplitMemberID) {
        SidebarMotionTransaction.withoutAnimation {
            if case .regularTab(let tabID) = memberID {
                splitSegmentRemovalIDs.insert(tabID)
            }
            browserContext.splitCloseCommand.closeMember(
                group.id,
                memberID,
                windowState.id
            )
        }
    }

    private func prepareShortcutRestoreGap(memberID: SplitMemberID) {
        let gap = SpaceShortcutRestorePlanner(
            inventory: inventory,
            space: space
        ).shortcutRestoreGap(groupID: group.id, memberID: memberID)
        guard let gap, contentMutationAnimation != nil else { return }
        SpaceShortcutRestoreInteraction.prepare(
            session: $shortcutRestoreSession,
            gap: gap,
            animation: SidebarDropMotion.contentLayout
        )
    }

    private func performShortcutRestoreWithPreparedGap(
        memberID: SplitMemberID,
        update: () -> Void
    ) {
        let gap = SpaceShortcutRestorePlanner(
            inventory: inventory,
            space: space
        ).shortcutRestoreGap(groupID: group.id, memberID: memberID)
        SpaceShortcutRestoreInteraction.perform(
            session: $shortcutRestoreSession,
            gap: gap,
            update: update
        )
    }
}
