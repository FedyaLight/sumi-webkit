//
//  SpaceRegularTabsListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Owns regular-tab row projection and the transient insertion/removal lifecycle.
struct SpaceRegularTabsListView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let regularTabs: any SidebarRegularTabsControlling
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    let tabs: [Tab]
    let projection: SpaceRegularTabsListProjection
    let dragSnapshot: SpaceRegularDragSnapshot
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession
    @Binding var interactionSession: SpaceRegularTabsInteractionSession

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tabByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let splitGroups = visibleSplitGroups
        let groupedTabIDs = Set(splitGroups.flatMap { group in
            group.memberIDs.compactMap { memberID -> UUID? in
                guard case .regularTab(let tabID) = memberID else { return nil }
                return tabID
            }
        })
        let splitGroupByFirstTabID = Dictionary(
            uniqueKeysWithValues: splitGroups.compactMap { group -> (UUID, SplitGroup)? in
                guard let first = tabs.first(where: { group.contains(.regularTab($0.id)) })?.id else {
                    return nil
                }
                return (first, group)
            }
        )

        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(projection.displayItems(fallback: interactionSession.listAnimation.renderedItems)) { item in
                VStack(spacing: 0) {
                    switch item {
                    case .tab(let tabID):
                        if let group = splitGroupByFirstTabID[tabID] {
                            SpaceRegularSplitGroupEntryView(
                                group: group,
                                space: space,
                                tabByID: tabByID,
                                inventory: inventory,
                                selection: selection,
                                regularTabs: regularTabs,
                                browserContext: browserContext,
                                isInteractive: isInteractive,
                                contentMutationAnimation: contentMutationAnimation,
                                tabActionOwner: tabActionOwner,
                                onCloseRegularTab: closeRegularTab,
                                shortcutRestoreSession: $shortcutRestoreSession,
                                splitSegmentRemovalIDs: $interactionSession.splitSegmentRemovalIDs
                            )
                        } else if groupedTabIDs.contains(tabID) {
                            EmptyView()
                        } else if let tab = tabByID[tabID]
                            ?? interactionSession.listAnimation.resolvedTab(
                                for: tabID,
                                liveTab: { regularTabs.tab(for: $0) }
                            ) {
                            animatedTabRow(tab)
                        }
                    case .gap(let gapID):
                        Color.clear.sidebarRowLayoutGap(
                            height: interactionSession.listAnimation.gapHeights[gapID]
                                ?? SidebarRowLayout.rowHeight
                        )
                    }
                }
            }
        }
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.gapHeights)
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.disappearingTabIds)
        .animation(contentMutationAnimation, value: interactionSession.listAnimation.appearingTabIds)
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            .contentShape(Rectangle())
            .animation(
                isInteractive && dragSnapshot.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
                value: projection.projectedItems
            )
            .onAppear {
                interactionSession.listAnimation.cacheTabs(tabs)
                syncRenderedTabsWithoutAnimation(to: tabs.map(\.id))
            }
            .onChange(of: tabs.map(\.id)) { oldValue, newValue in
                interactionSession.listAnimation.preserveSnapshots(
                    from: oldValue,
                    to: newValue,
                    liveTab: { regularTabs.tab(for: $0) }
                )
                interactionSession.listAnimation.cacheTabs(tabs)
                animateRenderedTabsChange(from: oldValue, to: newValue)
            }
    }

    private var splitResolver: RegularSplitSegmentResolver {
        RegularSplitSegmentResolver(space: space, isInteractive: isInteractive)
    }

    private var visibleSplitGroups: [SplitGroup] {
        splitResolver.visibleSplitGroups(
            currentTabs: tabs,
            isDragging: dragSnapshot.isDragging,
            splitGroup: { regularTabs.splitGroup(containing: $0) }
        )
    }

    private func animatedTabRow(_ tab: Tab) -> some View {
        SpaceRegularTabEntryView(
            tab: tab,
            spaceID: space.id,
            isCurrentTab: windowState.currentTabId == tab.id,
            opacity: dragSnapshot.isDragging && dragSnapshot.activeDragItemID == tab.id ? 0.001 : 1,
            isInteractive: isInteractive,
            actionOwner: tabActionOwner,
            onClose: { closeRegularTab(tab) }
        )
        .sidebarRowAnimatedListSlot(interactionSession.listAnimation.rowMotion(for: tab.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: windowState.currentTabId == tab.id)
        )
    }

    private var tabActionOwner: SpaceRegularTabActionOwner {
        SpaceRegularTabActionOwner(
            space: space,
            regularTabs: regularTabs,
            browserContext: browserContext,
            windowState: windowState,
            firstTabID: tabs.first?.id,
            lastTabID: tabs.last?.id
        )
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion,
              !dragSnapshot.isCompletingDrop
        else { return nil }
        return SidebarMotionPolicy.folderLayoutAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
            )
        )
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

    private func syncRenderedTabsWithoutAnimation(to tabIDs: [UUID]) {
        SidebarMotionTransaction.withoutAnimation {
            interactionSession.listAnimation.reset(to: tabIDs)
        }
    }

    private func animateRenderedTabsChange(from oldIDs: [UUID], to newIDs: [UUID]) {
        guard let animation = contentMutationAnimation else {
            syncRenderedTabsWithoutAnimation(to: newIDs)
            return
        }

        let insertedIDs = Set(newIDs.filter { !oldIDs.contains($0) })
        if !insertedIDs.isEmpty {
            animateInsertion(insertedIDs: insertedIDs, newIDs: newIDs, animation: animation)
            return
        }

        if let removedID = oldIDs.first(where: { !newIDs.contains($0) }) {
            if interactionSession.splitSegmentRemovalIDs.remove(removedID) != nil {
                syncRenderedTabsWithoutAnimation(to: newIDs)
                return
            }
            if interactionSession.listAnimation.isRemovalInFlight(for: removedID) { return }
            guard interactionSession.listAnimation.containsRenderedTab(removedID),
                  let tab = interactionSession.listAnimation.resolvedTab(
                    for: removedID,
                    liveTab: { regularTabs.tab(for: $0) }
                  ) else {
                syncRenderedTabsWithoutAnimation(to: newIDs)
                return
            }
            animateRowRemoval(tabID: removedID, tab: tab, animation: animation)
            return
        }

        guard oldIDs != newIDs else { return }
        withAnimation(animation) {
            interactionSession.listAnimation.renderedItems = newIDs.map(RegularTabRenderedItem.tab)
        }
    }

    private func animateInsertion(
        insertedIDs: Set<UUID>,
        newIDs: [UUID],
        animation: Animation
    ) {
        SidebarMotionTransaction.withoutAnimation {
            interactionSession.listAnimation.beginInsertion(insertedIDs) {
                regularTabs.tab(for: $0)
            }
        }
        withAnimation(animation) {
            interactionSession.listAnimation.renderedItems = newIDs.map(RegularTabRenderedItem.tab)
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
                finalItems: plan.finalItems
            ) else { return }
            onComplete?()
        }
    }
}
