//
//  SpaceRegularTabsListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Owns regular-tab row projection and the transient insertion/removal lifecycle.
struct SpaceRegularTabsListView: View {
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
    @Binding var interactionSession: SpaceRegularTabsInteractionSession

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    var body: some View {
        let selectionSnapshot = sidebarSelection
        let tabByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let splitGroups = visibleSplitGroups
        let splitGroupsByID = Dictionary(
            uniqueKeysWithValues: splitGroups.map { ($0.id, $0) }
        )
        let regularRun = SidebarVisualSceneProjection.regularRun(
            tabIDs: tabs.map(\.id),
            groups: splitGroups
        )
        let renderedRun = interactionSession.listAnimation.renderedRun

        LazyVStack(alignment: .leading, spacing: SidebarRowLayout.rowGap) {
            ForEach(renderedRun.rows) { row in
                VStack(spacing: 0) {
                    switch row.identity {
                    case .splitGroup(let groupID):
                        if let group = splitGroupsByID[groupID] {
                            SpaceRegularSplitGroupEntryView(
                                group: group,
                                space: space,
                                tabByID: tabByID,
                                selection: selection,
                                regularTabCatalog: regularTabCatalog,
                                regularTabTargets: regularTabTargets,
                                browserContext: browserContext,
                                isInteractive: isInteractive,
                                isDropHighlighted:
                                    isExistingGroupDropTarget(group),
                                tabActionOwner: tabActionOwner
                            )
                            .opacity(
                                dragSnapshot.isDragging && dragSnapshot.activeDragItemID == group.id
                                    ? SidebarDragSourceDim.opacity
                                    : 1
                            )
                        }
                    case .tab(let tabID):
                        if let tab = tabByID[tabID]
                            ?? interactionSession.listAnimation.resolvedTab(
                                for: tabID,
                                liveTab: { regularTabCatalog.tab(for: $0) }
                            ) {
                            animatedTabRow(
                                tab,
                                selectionSnapshot: selectionSnapshot
                            )
                        }
                    }
                }
                .sidebarScrollTarget(scrollTargetID(for: row.identity))
            }
        }
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.gapHeights)
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.disappearingTabIds)
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.appearingTabIds)
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .sidebarRegularListHitGeometry(
            for: space.id,
            rowIdentities: regularRun.rows.map(\.identity),
            splitPairingMemberIDsByRow: regularRun.rows.map {
                $0.tabIDs.map(SplitMemberID.regularTab)
            },
            generation: dragSnapshot.geometryGeneration,
            isEnabled: isInteractive
        )
        .contentShape(Rectangle())
        .onAppear {
            interactionSession.listAnimation.cacheTabs(tabs)
            syncRenderedRowsWithoutAnimation(to: regularRun)
        }
        .onChange(of: regularRun) { oldRun, newRun in
            let oldTabIDs = oldRun.rows.flatMap(\.tabIDs)
            let newTabIDs = newRun.rows.flatMap(\.tabIDs)
            interactionSession.listAnimation.preserveSnapshots(
                from: oldTabIDs,
                to: newTabIDs,
                liveTab: { regularTabCatalog.tab(for: $0) }
            )
            interactionSession.listAnimation.cacheTabs(tabs)
            animateRenderedRowsChange(from: oldRun, to: newRun)
        }
    }

    private func scrollTargetID(
        for identity: SidebarVisualSceneProjection.RegularRow.Identity
    ) -> SidebarScrollTargetID {
        switch identity {
        case .tab(let tabID):
            return .regularTab(tabID)
        case .splitGroup(let groupID):
            return .splitGroup(groupID)
        }
    }

    private var splitResolver: RegularSplitSegmentResolver {
        RegularSplitSegmentResolver(space: space, isInteractive: isInteractive)
    }

    private var visibleSplitGroups: [SplitGroup] {
        splitResolver.visibleSplitGroups(
            currentTabs: tabs,
            splitGroup: { regularTabTargets.splitGroup(containing: $0) }
        )
    }

    private func isExistingGroupDropTarget(_ group: SplitGroup) -> Bool {
        guard let target = dragSnapshot.splitPairingTarget,
              target.presentation == .existingGroupRow
        else {
            return false
        }
        return group.memberIDs.contains(target.memberID)
    }

    private func animatedTabRow(
        _ tab: Tab,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> some View {
        let isCurrentTab = selectionSnapshot.currentTabID == tab.id
        return SpaceRegularTabEntryView(
            tab: tab,
            spaceID: space.id,
            isCurrentTab: isCurrentTab,
            opacity: dragSnapshot.isDragging && dragSnapshot.activeDragItemID == tab.id
                ? SidebarDragSourceDim.opacity
                : 1,
            isInteractive: isInteractive,
            projectedSplitTarget: dragSnapshot.splitPairingTarget?
                .projectedTarget(for: .regularTab(tab.id)),
            actionOwner: tabActionOwner,
            onClose: { closeRegularTab(tab) }
        )
        .sidebarRowAnimatedListSlot(interactionSession.listAnimation.rowMotion(for: tab.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: isCurrentTab)
        )
    }

    private var tabActionOwner: SpaceRegularTabActionOwner {
        SpaceRegularTabActionOwner(
            space: space,
            catalog: regularTabCatalog,
            targets: regularTabTargets,
            lifecycleCommands: regularTabLifecycleCommands,
            shortcutCommands: regularTabShortcutCommands,
            placementCommands: regularTabPlacementCommands,
            browserContext: browserContext,
            windowState: windowState,
            firstTabID: tabs.first?.id,
            lastTabID: tabs.last?.id
        )
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion
        else { return nil }
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        // Drop commit settles rows into place with the short Zen-style slide.
        return dragSnapshot.isCompletingDrop
            ? SidebarMotionPolicy.dropSettleAnimation(for: mode)
            : SidebarMotionPolicy.folderLayoutAnimation(for: mode)
    }

    private func closeRegularTab(_ tab: Tab) {
        guard let animation = contentMutationAnimation else {
            tabActionOwner.close(tab)
            return
        }
        animateRowRemoval(tabID: tab.id, tab: tab, animation: animation) {
            tabActionOwner.close(tab)
        }
    }

    private func syncRenderedRowsWithoutAnimation(
        to run: SidebarVisualSceneProjection.RegularRun
    ) {
        SidebarMotionTransaction.withoutAnimation {
            interactionSession.listAnimation.reset(to: run)
        }
    }

    private func animateRenderedRowsChange(
        from oldRun: SidebarVisualSceneProjection.RegularRun,
        to newRun: SidebarVisualSceneProjection.RegularRun
    ) {
        guard let animation = contentMutationAnimation else {
            syncRenderedRowsWithoutAnimation(to: newRun)
            return
        }

        switch RegularSidebarVisualChange.resolve(
            from: oldRun,
            to: newRun
        ) {
        case .insertion(let insertedIDs):
            animateInsertion(
                insertedIDs: insertedIDs,
                newRun: newRun,
                animation: animation
            )
        case .removal(let removedID):
            if interactionSession.listAnimation.isRemovalInFlight(for: removedID) { return }
            guard interactionSession.listAnimation.containsRenderedTab(removedID),
                  let tab = interactionSession.listAnimation.resolvedTab(
                    for: removedID,
                    liveTab: { regularTabCatalog.tab(for: $0) }
                  ) else {
                syncRenderedRowsWithoutAnimation(to: newRun)
                return
            }
            animateRowRemoval(tabID: removedID, tab: tab, animation: animation)
        case .immediateReplacement:
            syncRenderedRowsWithoutAnimation(to: newRun)
        case .reorder:
            withAnimation(animation) {
                interactionSession.listAnimation.renderedRows = newRun.rows
            }
        case .none:
            break
        }
    }

    private func animateInsertion(
        insertedIDs: Set<UUID>,
        newRun: SidebarVisualSceneProjection.RegularRun,
        animation: Animation
    ) {
        SidebarMotionTransaction.withoutAnimation {
            interactionSession.listAnimation.beginInsertion(insertedIDs) {
                regularTabCatalog.tab(for: $0)
            }
        }
        withAnimation(animation) {
            interactionSession.listAnimation.renderedRows = newRun.rows
        }
        DispatchQueue.main.async {
            withAnimation(animation) {
                interactionSession.listAnimation.revealInserted(insertedIDs)
            }
        }
    }

    private func animateRowRemoval(
        tabID: UUID,
        tab: Tab,
        animation: Animation,
        onComplete: (() -> Void)? = nil
    ) {
        guard let plan = interactionSession.listAnimation.prepareRemoval(tabId: tabID, tab: tab) else {
            onComplete?()
            return
        }
        withAnimation(animation) {
            interactionSession.listAnimation.commitRemovalAppearance(tabId: tabID, mode: plan.mode)
        }
        SidebarMotionTransaction.afterContentLayout {
            guard interactionSession.listAnimation.finishRemoval(
                tabId: tabID,
                generation: plan.generation,
                finalRows: plan.finalRows
            ) else { return }
            onComplete?()
        }
    }
}
