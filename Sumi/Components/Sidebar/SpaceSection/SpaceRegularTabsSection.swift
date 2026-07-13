//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import SumiDomain
import SwiftUI

private enum RegularExternalDropGapPlacement: Equatable {
    case top
    case bottom
}

private let regularDragProjectionGapId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

extension SpaceView {
    private var showsNewTabButtonInList: Bool {
        sumiSettings.showNewTabButtonInTabList
    }

    private var showsNewTabButtonAtTop: Bool {
        sumiSettings.tabListNewTabButtonPosition == .top
    }

    private var showsBottomNewTabButton: Bool {
        showsNewTabButtonInList && !showsNewTabButtonAtTop
    }

    private var tabs: [Tab] {
        regularTabs.tabs(in: space, windowState: windowState)
    }

    private var newTabRow: some View {
        Button(action: openNewTabFloatingBar) {
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
            background: displayIsNewTabHovered ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displayIsNewTabHovered,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sidebarDDGHover($isNewTabHovered, isEnabled: isInteractive)
        .sidebarZenPressEffect(sourceID: newTabRowSourceID, isEnabled: isInteractive)
        .accessibilityIdentifier("space-new-tab-\(space.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isInteractive,
            sourceID: newTabRowSourceID,
            action: openNewTabFloatingBar
        )
    }

    private var newTabRowSourceID: String {
        "space-new-tab-\(space.id.uuidString)"
    }

    private var displayIsNewTabHovered: Bool {
        SidebarHoverChrome.displayHover(
            isNewTabHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func openNewTabFloatingBar() {
        guard isInteractive else { return }
        browserContext.commands.openNewTabOrFloatingBar(windowState)
    }

    private var topNewTabButtonSection: some View {
        newTabRow
            .padding(.top, 4)
    }

    private var bottomNewTabButtonSection: some View {
        newTabRow
    }

    var regularTabsSection: some View {
        VStack(spacing: 0) {
            if regularExternalDropGapPlacement == .top {
                regularDropGap
            }

            SpaceSeparator(
                hasTabs: regularTabs.hasPersistedTabs(in: space),
                isHovering: $isSidebarHovered
            ) {
                regularTabs.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                if showsNewTabButtonInList && showsNewTabButtonAtTop {
                    topNewTabButtonSection
                }

                regularTabsListHitRegion

                if regularExternalDropGapPlacement == .bottom {
                    regularDropGap
                }

                if showsBottomNewTabButton {
                    bottomNewTabButtonSection
                }
            }
            .padding(.top, 8)

            regularTabsDragSpacer
        }
        .onAppear {
            regularTabsListAnimation.cacheTabs(tabs)
            syncRegularRenderedTabsWithoutAnimation(to: tabs.map(\.id))
        }
        .onChange(of: tabs.map(\.id)) { oldValue, newValue in
            regularTabsListAnimation.preserveSnapshots(
                from: oldValue,
                to: newValue,
                liveTab: { regularTabs.tab(for: $0) }
            )
            regularTabsListAnimation.cacheTabs(tabs)
            animateRegularRenderedTabsChange(from: oldValue, to: newValue)
        }
        .sidebarSectionGeometry(
            for: .spaceRegular,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: regularExternalDropGapPlacement
        )
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var regularTabsListHitRegion: some View {
        VStack(spacing: 0) {
            regularTabsListInner
        }
        .sidebarRegularListHitGeometry(
            for: space.id,
            itemCount: regularTabsRenderedRowCount,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var regularTabsRenderedRowCount: Int {
        regularDisplayItems(currentTabs: tabs).count
    }

    private var regularTabsListInner: some View {
        regularTabsContent
            .animation(
                isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
                value: regularProjectedItems(currentTabs: tabs)
            )
    }

    private var regularTabsContent: some View {
        Group {
            let currentTabs = tabs
            regularTabsView(currentTabs: currentTabs)
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var regularTabsUsesExpandedDragSpacer: Bool {
        regularTabsRenderedRowCount == 0 && !regularTabsListAnimation.hasRemovalInFlight
    }

    private var regularTabsDragSpacer: some View {
        Color.clear
            .frame(height: regularTabsUsesExpandedDragSpacer ? 48 : 24)
    }

    private func regularTabsView(currentTabs: [Tab]) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            let tabById = Dictionary(uniqueKeysWithValues: currentTabs.map { ($0.id, $0) })
            let splitGroups = visibleSplitGroups(currentTabs: currentTabs)
            let groupedTabIds = Set(splitGroups.flatMap { group in
                group.memberIDs.compactMap { memberID -> UUID? in
                    guard case .regularTab(let tabID) = memberID else {
                        return nil
                    }
                    return tabID
                }
            })
            let splitGroupByFirstTabId = Dictionary(
                uniqueKeysWithValues: splitGroups.compactMap { group -> (UUID, SplitGroup)? in
                    guard let first = currentTabs.first(where: {
                        group.contains(.regularTab($0.id))
                    })?.id else { return nil }
                    return (first, group)
                }
            )
            ForEach(regularDisplayItems(currentTabs: currentTabs), id: \.self) { item in
                switch item {
                case .tab(let tabId):
                    if let group = splitGroupByFirstTabId[tabId] {
                        let groupItems = splitGroupItems(for: group, tabById: tabById)
                        SplitGroupSidebarRow(
                            group: group,
                            items: groupItems,
                            spaceId: space.id,
                            currentTabId: windowState.currentTabId,
                            isAppKitInteractionEnabled: isInteractive,
                            faviconImageReader: browserContext.faviconImageReader,
                            splitLayout: browserContext.splitLayout,
                            emptySplitCreation: browserContext.emptySplitCreation,
                            segmentAction: { item in
                                splitSegmentAction(for: item, in: group)
                            },
                            dragSource: { item in
                                splitSegmentDragSource(for: item, in: group)
                            },
                            contextMenuEntries: regularTabContextMenuEntries,
                            onActivateMember: { memberID in
                                browserContext.commands.focusSplitGroup(
                                    group.id,
                                    memberID,
                                    windowState.id
                                )
                            },
                            onSegmentActionAnimationStart: { memberID in
                                if case .shortcutPin = memberID {
                                    prepareShortcutRestoreGap(
                                        groupID: group.id,
                                        memberID: memberID
                                    )
                                }
                            },
                            onSegmentAction: { memberID in
                                performSplitSegmentAction(
                                    memberID: memberID,
                                    groupID: group.id
                                )
                            },
                            onSegmentMiddleClick: { memberID in
                                performSplitSegmentMiddleClick(
                                    memberID: memberID,
                                    groupID: group.id
                                )
                            }
                        )
                        .zIndex(regularSplitGroupRowZIndex(group))
                    } else if groupedTabIds.contains(tabId) {
                        EmptyView()
                    } else if let tab = tabById[tabId]
                        ?? regularTabsListAnimation.resolvedTab(
                            for: tabId,
                            liveTab: { regularTabs.tab(for: $0) }
                        ) {
                        regularAnimatedTabRow(tab)
                    }
                case .gap(let gapId):
                    regularLayoutGap(gapId)
                }
            }
        }
        .animation(sidebarContentMutationAnimation, value: regularTabsListAnimation.gapHeights)
        .animation(sidebarContentMutationAnimation, value: regularTabsListAnimation.disappearingTabIds)
        .animation(sidebarContentMutationAnimation, value: regularTabsListAnimation.appearingTabIds)
    }

    private var regularSplitSegmentResolver: RegularSplitSegmentResolver {
        RegularSplitSegmentResolver(space: space, isInteractive: isInteractive)
    }

    private func visibleSplitGroups(currentTabs: [Tab]) -> [SplitGroup] {
        regularSplitSegmentResolver.visibleSplitGroups(
            currentTabs: currentTabs,
            isDragging: dragState.isDragging,
            splitGroup: { regularTabs.splitGroup(containing: $0) }
        )
    }

    private func splitGroupItems(
        for group: SplitGroup,
        tabById: [UUID: Tab]
    ) -> [SplitGroupSidebarItem] {
        regularSplitSegmentResolver.splitGroupItems(
            for: group,
            tabByID: tabById,
            regularTab: { regularTabs.tab(for: $0) },
            shortcutLiveTab: { pinID in
                selection.liveTab(for: pinID, in: windowState)
            },
            shortcutPin: { regularTabs.shortcutPin(by: $0) }
        )
    }

    private func splitSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        regularSplitSegmentResolver.action(for: item, in: group)
    }

    private func performSplitSegmentAction(
        memberID: SplitMemberID,
        groupID: UUID
    ) {
        if case .shortcutPin = memberID {
            performShortcutRestoreWithPreparedGap(
                groupID: groupID,
                memberID: memberID
            ) {
                performRegularSplitModelMutation {
                    browserContext.commands.restoreShortcutSplitMember(
                        groupID,
                        memberID,
                        windowState.id
                    )
                }
            }
            return
        }

        guard case .regularTab(let tabID) = memberID else {
            return
        }
        performRegularSplitModelMutation {
            regularSplitSegmentRemovalIds.insert(tabID)
            browserContext.commands.closeSplitMember(
                groupID,
                memberID,
                windowState.id
            )
        }
    }

    private func performSplitSegmentMiddleClick(
        memberID: SplitMemberID,
        groupID: UUID
    ) {
        performRegularSplitModelMutation {
            if case .regularTab(let tabID) = memberID {
                regularSplitSegmentRemovalIds.insert(tabID)
            }
            browserContext.commands.closeSplitMember(
                groupID,
                memberID,
                windowState.id
            )
        }
    }

    private func performRegularSplitModelMutation(_ update: () -> Void) {
        SidebarMotionTransaction.withoutAnimation(update)
    }

    private func splitSegmentDragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SidebarDragSourceConfiguration? {
        regularSplitSegmentResolver.dragSource(
            for: item,
            in: group,
            faviconImageReader: browserContext.faviconImageReader,
            shortcutPin: { regularTabs.shortcutPin(by: $0) },
            onActivateMember: {
                browserContext.commands.focusSplitGroup(
                    group.id,
                    item.id,
                    windowState.id
                )
            }
        )
    }

    private func regularDisplayItems(currentTabs: [Tab]) -> [RegularTabRenderedItem] {
        if regularTabsUsesProjectedDropLayout {
            return regularProjectedItems(currentTabs: currentTabs).map { item in
                switch item {
                case .item(let tabId):
                    return .tab(tabId)
                case .placeholder:
                    return .gap(regularDragProjectionGapId)
                }
            }
        }

        return regularTabsListAnimation.renderedItems
    }

    private func regularAnimatedTabRow(_ tab: Tab) -> some View {
        regularTabView(tab)
            .sidebarRowAnimatedListSlot(regularTabsListAnimation.rowMotion(for: tab.id))
            .zIndex(regularTabRowZIndex(tab))
    }

    private func regularTabRowZIndex(_ tab: Tab) -> Double {
        SidebarSelectionElevation.zIndex(isElevated: windowState.currentTabId == tab.id)
    }

    private func regularSplitGroupRowZIndex(_ group: SplitGroup) -> Double {
        SidebarSelectionElevation.zIndex(
            isElevated: SidebarSelectionElevation.splitGroupIsSelected(
                group,
                selectedGroupID: windowState.splitSelection?.groupID
            )
        )
    }

    private func regularLayoutGap(_ gapId: UUID) -> some View {
        Color.clear
            .sidebarRowLayoutGap(
                height: regularTabsListAnimation.gapHeights[gapId] ?? SidebarRowLayout.rowHeight
            )
    }

    private func syncRegularRenderedTabsWithoutAnimation(to tabIds: [UUID]) {
        SidebarMotionTransaction.withoutAnimation {
            regularTabsListAnimation.reset(to: tabIds)
        }
    }

    private func animateRegularRenderedTabsChange(from oldIds: [UUID], to newIds: [UUID]) {
        guard let animation = sidebarContentMutationAnimation else {
            syncRegularRenderedTabsWithoutAnimation(to: newIds)
            return
        }

        let insertedIds = Set(newIds.filter { !oldIds.contains($0) })
        if !insertedIds.isEmpty {
            animateRegularInsertion(insertedIds: insertedIds, newIds: newIds, animation: animation)
            return
        }

        if let removedId = oldIds.first(where: { !newIds.contains($0) }) {
            if regularSplitSegmentRemovalIds.remove(removedId) != nil {
                syncRegularRenderedTabsWithoutAnimation(to: newIds)
                return
            }
            if regularTabsListAnimation.isRemovalInFlight(for: removedId) {
                return
            }
            guard regularTabsListAnimation.containsRenderedTab(removedId),
                  let tab = regularTabsListAnimation.resolvedTab(
                    for: removedId,
                    liveTab: { regularTabs.tab(for: $0) }
                  ) else {
                syncRegularRenderedTabsWithoutAnimation(to: newIds)
                return
            }
            animateRegularRowRemoval(tabId: removedId, tab: tab, animation: animation)
            return
        }

        guard oldIds != newIds else { return }

        withAnimation(animation) {
            regularTabsListAnimation.renderedItems = newIds.map(RegularTabRenderedItem.tab)
        }
    }

    private func animateRegularInsertion(
        insertedIds: Set<UUID>,
        newIds: [UUID],
        animation: Animation
    ) {
        let finalItems = newIds.map(RegularTabRenderedItem.tab)

        SidebarMotionTransaction.withoutAnimation {
            regularTabsListAnimation.beginInsertion(insertedIds) {
                regularTabs.tab(for: $0)
            }
        }

        withAnimation(animation) {
            regularTabsListAnimation.renderedItems = finalItems
        }

        DispatchQueue.main.async {
            withAnimation(animation) {
                regularTabsListAnimation.revealInserted(insertedIds)
            }
        }
    }

    private func animateRegularRowRemoval(
        tabId: UUID,
        tab: Tab,
        animation: Animation,
        onComplete: (() -> Void)? = nil
    ) {
        guard let plan = regularTabsListAnimation.prepareRemoval(tabId: tabId, tab: tab) else {
            onComplete?()
            return
        }

        withAnimation(animation) {
            regularTabsListAnimation.commitRemovalAppearance(tabId: tabId, mode: plan.mode)
        }

        SidebarMotionTransaction.afterContentLayout {
            guard regularTabsListAnimation.finishRemoval(
                tabId: tabId,
                generation: plan.generation,
                finalItems: plan.finalItems
            ) else {
                return
            }
            onComplete?()
        }
    }

    private func regularProjectedItems(currentTabs: [Tab]) -> [ProjectedItem<UUID>] {
        let sourceId = regularProjectedSourceId(in: currentTabs)
        let projectedInsertionIndex = regularProjectedInsertionIndex()
        return SidebarDropProjection.projectedItems(
            itemIDs: currentTabs.map(\.id),
            removesSourceID: sourceId,
            insertsPlaceholderAt: projectedInsertionIndex
        )
    }

    private var regularTabsUsesProjectedDropLayout: Bool {
        regularProjectedSourceId(in: tabs) != nil || regularProjectedInsertionIndex() != nil
    }

    private func regularProjectedSourceId(in currentTabs: [Tab]) -> UUID? {
        guard dragState.isDropProjectionActive,
              dragState.projectionDragScope?.sourceContainer == .spaceRegular(space.id),
              let projectionDragItemId = dragState.projectionDragItemId,
              currentTabs.contains(where: { $0.id == projectionDragItemId }) else {
            return nil
        }
        return projectionDragItemId
    }

    private func regularProjectedInsertionIndex() -> Int? {
        guard dragState.isDropProjectionActive,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.projectionHoveredSlot,
              hoveredSpaceId == space.id,
              regularExternalDropGapPlacement == nil else {
            return nil
        }
        if shouldSuppressRegularCommitGapForExternalShortcutSource {
            return nil
        }
        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .spaceRegular(space.id),
                targetAlreadyContainsDraggedItem: tabs.contains { $0.id == projectionDragItemId }
           ) {
            return nil
        }
        return slot
    }

    private var shouldSuppressRegularCommitGapForExternalShortcutSource: Bool {
        SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
            isCompletingDrop: dragState.isCompletingDrop,
            sourceContainer: dragState.projectionDragScope?.sourceContainer,
            targetContainer: .spaceRegular(space.id)
        )
    }

    private var regularExternalDropGapPlacement: RegularExternalDropGapPlacement? {
        guard let gap = dragState.regularExternalDropGap,
              gap.spaceId == space.id else {
            return nil
        }

        switch gap.edge {
        case .top:
            return .top
        case .bottom:
            return showsBottomNewTabButton ? .bottom : nil
        }
    }

    private var regularDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
    }

    private func regularTabView(_ tab: Tab) -> some View {
        SpaceTab(
            tab: tab,
            dragSourceConfiguration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: tab.id,
                    title: tab.name,
                    urlString: tab.url.absoluteString
                ),
                sourceZone: .spaceRegular(space.id),
                previewKind: .row,
                previewIcon: tab.favicon,
                exclusionZones: regularTabExclusionZones(for: tab),
                onActivate: { handleUserTabActivation(tab) },
                isEnabled: !tab.isRenaming
                    && isInteractive
            ),
            isAppKitInteractionEnabled: isInteractive,
            action: { handleUserTabActivation(tab) },
            onClose: { closeRegularTab(tab) },
            onMiddleClick: { closeRegularTab(tab) },
            onMute: { onMuteTab(tab) },
            contextMenuEntries: { regularTabContextMenuEntries(tab) },
            isCurrentTab: windowState.currentTabId == tab.id
        )
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == tab.id
                ? 0.001
                : 1
        )
        .accessibilityIdentifier("space-regular-tab-\(tab.id.uuidString)")
        .accessibilityValue(windowState.currentTabId == tab.id ? "selected" : "not selected")
    }

    private func closeRegularTab(_ tab: Tab) {
        guard let animation = sidebarContentMutationAnimation else {
            onCloseTab(tab)
            return
        }

        animateRegularRowRemoval(tabId: tab.id, tab: tab, animation: animation) {
            onCloseTab(tab)
        }
    }

    private func regularTabContextMenuEntries(_ tab: Tab) -> [SidebarContextMenuEntry] {
        let profiles = browserContext.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: regularTabs.userFolders(for: space.id)
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: regularTabs.spaces,
            selectedSpaceId: tab.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: tab.profileId ?? space.profileId
        )
        let moveUpAction: (() -> Void)? = isFirstTab(tab) ? nil : { onMoveTabUp(tab) }
        let moveDownAction: (() -> Void)? = isLastTab(tab) ? nil : { onMoveTabDown(tab) }
        let pinToSpaceAction: (() -> Void)? = tab.isPinned || tab.isSpacePinned
            ? nil
            : { regularTabs.pinTabToSpace(tab, spaceId: space.id) }
        let addToEssentialsAction: (() -> Void)? = canAddTabToEssentials(tab)
            ? {
                regularTabs.addTabToEssentials(tab, in: space, windowState: windowState)
            }
            : nil
        let closeTabsBelowAction: (() -> Void)? = !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil
            ? { regularTabs.closeAllTabsBelow(tab) }
            : nil
        let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
            regularTabs.moveTab(tab.id, to: targetSpaceId)
        }

        return makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: .init(
                duplicate: { browserContext.commands.duplicateTab(tab, windowState) },
                copyLink: { SidebarLinkActions.copyLink(tab.url) },
                share: {
                    SidebarLinkActions.presentSharePicker(
                        for: tab.url,
                        source: windowState.resolveSidebarPresentationSource(in: windowRegistry),
                        presentationActions: browserContext.presentationActions
                    )
                },
                rename: { tab.startRenaming() },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in
                        regularTabs.moveTabToFolder(tab, folderId: folderId)
                    }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: moveToSpaceAction
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        regularTabs.assign(tab, toProfile: profileId)
                    }
                ),
                moveUp: moveUpAction,
                moveDown: moveDownAction,
                pinToSpace: pinToSpaceAction,
                addToEssentials: addToEssentialsAction,
                closeTabsBelow: closeTabsBelowAction,
                close: { closeRegularTab(tab) }
            )
        )
    }

    private func canAddTabToEssentials(_ tab: Tab) -> Bool {
        regularTabs.canAddToEssentials(tab, in: space, windowState: windowState)
    }

    private func isFirstTab(_ tab: Tab) -> Bool {
        tabs.first?.id == tab.id
    }

    private func isLastTab(_ tab: Tab) -> Bool {
        tabs.last?.id == tab.id
    }

    private func handleUserTabActivation(_ tab: Tab) {
        browserContext.commands.requestUserTabActivation(
            tab,
            windowState
        )
    }

    private func regularTabExclusionZones(for tab: Tab) -> [SidebarDragSourceExclusionZone] {
        var exclusions: [SidebarDragSourceExclusionZone] = [.trailingStrip(40)]
        if tab.audioState.showsTabAudioButton {
            exclusions.append(.fixedRect(SpaceTab.audioButtonHitFrame))
        }
        return exclusions
    }
}
