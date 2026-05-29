//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import AppKit
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
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return browserManager.tabManager.tabs(in: space)
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
        .background(
            RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous)
                .fill(displayIsNewTabHovered ? tokens.sidebarRowHover : Color.clear)
                .padding(.horizontal, 2)
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
        browserManager.showNewTabFloatingBar(in: windowState)
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

            SpaceSeparator(space: space, isHovering: $isSidebarHovered) {
                browserManager.tabManager.clearRegularTabs(for: space.id)
            }
            .environmentObject(browserManager)
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
            syncRegularRenderedTabsWithoutAnimation(to: tabs.map(\.id))
        }
        .onChange(of: tabs.map(\.id)) { oldValue, newValue in
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

    private var regularTabsUsesLazyRowStack: Bool {
        isInteractive
            && !dragState.isDragging
            && !dragState.isDropProjectionActive
            && !dragState.isCompletingDrop
            && regularGapHeights.isEmpty
            && regularInsertedTabHeights.isEmpty
            && regularDeferredRemovalGapIdsByTabId.isEmpty
    }

    private var regularTabsListInner: some View {
        Group {
            if !tabs.isEmpty || regularTabsUsesProjectedDropLayout {
                regularTabsContent
            }
        }
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

    private var regularTabsDragSpacer: some View {
        Color.clear
            .frame(height: tabs.isEmpty ? 48 : 24)
    }

    private func regularTabsView(currentTabs: [Tab]) -> some View {
        return regularTabsRowStack {
            let tabById = Dictionary(uniqueKeysWithValues: currentTabs.map { ($0.id, $0) })
            let splitGroups = visibleSplitGroups(currentTabs: currentTabs)
            let groupedTabIds = Set(splitGroups.flatMap(\.tabIds))
            let splitGroupByFirstTabId = Dictionary(
                uniqueKeysWithValues: splitGroups.compactMap { group -> (UUID, SplitGroup)? in
                    guard let first = currentTabs.first(where: { group.contains($0.id) })?.id else { return nil }
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
                            isAppKitInteractionEnabled: isInteractive,
                            segmentAction: { item in
                                splitSegmentAction(for: item, in: group)
                            },
                            dragSource: { item in
                                splitSegmentDragSource(for: item, in: group)
                            },
                            contextMenuEntries: regularTabContextMenuEntries,
                            onActivate: onActivateTab,
                            onActivateGroup: { browserManager.focusSplitGroup(group, in: windowState) },
                            onSegmentAction: { item in
                                performSplitSegmentAction(for: item, in: group)
                            }
                        )
                        .environmentObject(browserManager)
                        .environmentObject(splitManager)
                    } else if groupedTabIds.contains(tabId) {
                        EmptyView()
                    } else if let tab = tabById[tabId] {
                        regularRenderedTabView(tab)
                    }
                case .gap(let gapId):
                    regularLayoutGap(gapId)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !regularTabsUsesProjectedDropLayout {
                regularDropGuideOverlay(itemCount: currentTabs.count)
            }
        }
    }

    private func visibleSplitGroups(currentTabs: [Tab]) -> [SplitGroup] {
        guard !SidebarDragState.shared.isDragging else { return [] }
        let currentTabIds = Set(currentTabs.map(\.id))
        var seenGroupIds = Set<UUID>()
        return currentTabs.compactMap { tab in
            guard let group = browserManager.tabManager.splitGroup(containing: tab.id),
                  !group.isShortcutHosted,
                  seenGroupIds.insert(group.id).inserted,
                  group.tabIds.count >= SplitGroup.minimumTabs,
                  group.tabIds.contains(where: { currentTabIds.contains($0) })
            else {
                return nil
            }
            return group
        }
    }

    private func splitGroupItems(
        for group: SplitGroup,
        tabById: [UUID: Tab]
    ) -> [SplitGroupSidebarItem] {
        group.tabIds.compactMap { id in
            if let tab = tabById[id] ?? browserManager.tabManager.tab(for: id) {
                return .tab(tab)
            }
            if let pinId = group.member(for: id)?.pinId,
               let pin = browserManager.tabManager.shortcutPin(by: pinId) {
                return .pin(pin)
            }
            if let pin = browserManager.tabManager.shortcutPin(by: id) {
                return .pin(pin)
            }
            return nil
        }
    }

    private func splitSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        if splitMember(for: item, in: group)?.isShortcutBacked == true {
            return .restore
        }
        return item.tab == nil ? nil : .close
    }

    private func performSplitSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) {
        if splitMember(for: item, in: group)?.isShortcutBacked == true {
            browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
            return
        }

        guard let tab = item.tab else { return }
        closeRegularTab(tab)
    }

    private func splitMember(
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

    private func splitSegmentDragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SidebarDragSourceConfiguration? {
        let member = splitMember(for: item, in: group)
        if let pin = splitSegmentShortcutPin(for: item, member: member) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: splitSegmentSourceZone(for: pin),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: {
                    if let tab = item.tab {
                        onActivateTab(tab)
                    } else {
                        browserManager.focusSplitGroup(group, in: windowState)
                    }
                },
                isEnabled: isInteractive
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem(
                tabId: tab.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(space.id),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: { onActivateTab(tab) },
            isEnabled: isInteractive
        )
    }

    private func splitSegmentShortcutPin(
        for item: SplitGroupSidebarItem,
        member: SplitGroupMember?
    ) -> ShortcutPin? {
        if let pin = item.pin {
            return pin
        }
        if let pinId = item.tab?.shortcutPinId ?? member?.pinId {
            return browserManager.tabManager.shortcutPin(by: pinId)
        }
        return nil
    }

    private func splitSegmentSourceZone(for pin: ShortcutPin) -> DropZoneID {
        switch pin.role {
        case .essential:
            return .essentials
        case .spacePinned:
            if let folderId = pin.folderId {
                return .folder(folderId)
            }
            return .spacePinned(pin.spaceId ?? space.id)
        }
    }

    @ViewBuilder
    private func regularTabsRowStack<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if regularTabsUsesLazyRowStack {
            LazyVStack(alignment: .leading, spacing: 2) {
                content()
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
        }
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

        let currentTabIds = currentTabs.map(\.id)
        guard !regularRenderedTabItems.isEmpty else {
            return currentTabIds.map(RegularTabRenderedItem.tab)
        }

        return regularRenderedTabItems.compactMap { item in
            switch item {
            case .tab(let tabId):
                return currentTabIds.contains(tabId) ? item : nil
            case .gap:
                return item
            }
        }
    }

    @ViewBuilder
    private func regularRenderedTabView(_ tab: Tab) -> some View {
        if let height = regularInsertedTabHeights[tab.id] {
            let progress = regularInsertedTabProgress(for: height)

            regularInsertedTabPreview(tab, progress: progress)
                .frame(height: height, alignment: .top)
                .frame(maxWidth: .infinity)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 0) {
                regularTabView(tab)
            }
        }
    }

    private func regularInsertedTabProgress(for height: CGFloat) -> CGFloat {
        guard SidebarRowLayout.rowHeight > 0 else { return 1 }
        return min(max(height / SidebarRowLayout.rowHeight, 0), 1)
    }

    private func regularLayoutGap(_ gapId: UUID) -> some View {
        let height = regularGapHeights[gapId] ?? SidebarRowLayout.rowHeight

        return Color.clear
            .frame(height: height, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func regularInsertedTabPreview(_ tab: Tab, progress: CGFloat) -> some View {
        HStack(spacing: 8) {
            regularInsertedTabPreviewIcon(tab)

            RegularInsertedTabPreviewTitle(
                title: tab.name,
                color: tokens.primaryText,
                trailingFadePadding: SidebarHoverChrome.trailingFadePadding(
                    showsTrailingAction: windowState.currentTabId == tab.id
                )
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)

            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tokens.primaryText)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .opacity(windowState.currentTabId == tab.id ? 1 : 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(windowState.currentTabId == tab.id ? tokens.sidebarRowActive : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .offset(y: -4 * (1 - progress))
    }

    @ViewBuilder
    private func regularInsertedTabPreviewIcon(_ tab: Tab) -> some View {
        if tab.usesChromeThemedTemplateFavicon {
            Image(systemName: regularInsertedTabPreviewSystemImageName(for: tab))
                .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tokens.primaryText)
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
        } else {
            tab.favicon
                .resizable()
                .scaledToFit()
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func regularInsertedTabPreviewSystemImageName(for tab: Tab) -> String {
        if tab.representsSumiSettingsSurface {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if tab.representsSumiHistorySurface {
            return SumiSurface.historyTabFaviconSystemImageName
        }
        if tab.representsSumiBookmarksSurface {
            return SumiSurface.bookmarksTabFaviconSystemImageName
        }
        return "globe"
    }

    private func syncRegularRenderedTabsWithoutAnimation(to tabIds: [UUID]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            regularRenderedTabItems = tabIds.map(RegularTabRenderedItem.tab)
            regularGapHeights.removeAll()
            regularInsertedTabHeights.removeAll()
            regularDeferredRemovalGapIdsByTabId.removeAll()
            regularLayoutAnimationGeneration += 1
        }
    }

    private func animateRegularRenderedTabsChange(from oldIds: [UUID], to newIds: [UUID]) {
        guard let animation = sidebarContentMutationAnimation else {
            syncRegularRenderedTabsWithoutAnimation(to: newIds)
            return
        }

        if let insertedId = newIds.first(where: { !oldIds.contains($0) }) {
            animateRegularInsertion(insertedId: insertedId, newIds: newIds, animation: animation)
            return
        }

        if let removedId = oldIds.first(where: { !newIds.contains($0) }),
           let removalIndex = oldIds.firstIndex(of: removedId) {
            if let gapId = regularDeferredRemovalGapIdsByTabId[removedId] {
                completeDeferredRegularRemoval(removedId: removedId, gapId: gapId, newIds: newIds)
                return
            }
            animateRegularRemoval(removalIndex: removalIndex, newIds: newIds, animation: animation)
            return
        }

        withAnimation(animation) {
            regularRenderedTabItems = newIds.map(RegularTabRenderedItem.tab)
        }
    }

    private func animateRegularInsertion(
        insertedId: UUID,
        newIds: [UUID],
        animation: Animation
    ) {
        let finalItems = newIds.map(RegularTabRenderedItem.tab)
        let generation = regularLayoutAnimationGeneration + 1

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            regularLayoutAnimationGeneration = generation
            regularRenderedTabItems = finalItems
            regularInsertedTabHeights[insertedId] = 0
        }

        DispatchQueue.main.async {
            withAnimation(animation) {
                regularInsertedTabHeights[insertedId] = SidebarRowLayout.rowHeight
            }
        }

        completeRegularInsertionAnimation(generation: generation, finalItems: finalItems, insertedId: insertedId)
    }

    private func animateRegularRemoval(
        removalIndex: Int,
        newIds: [UUID],
        animation: Animation
    ) {
        let gapId = UUID()
        let finalItems = newIds.map(RegularTabRenderedItem.tab)
        var stagedItems = finalItems
        stagedItems.insert(.gap(gapId), at: min(removalIndex, stagedItems.count))
        let generation = regularLayoutAnimationGeneration + 1

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            regularLayoutAnimationGeneration = generation
            regularRenderedTabItems = stagedItems
            regularGapHeights[gapId] = SidebarRowLayout.rowHeight
        }

        DispatchQueue.main.async {
            withAnimation(animation) {
                regularGapHeights[gapId] = 0
            }
        }

        completeRegularRemovalAnimation(generation: generation, finalItems: finalItems, gapId: gapId)
    }

    @discardableResult
    private func animateRegularDeferredRemoval(_ tab: Tab, animation: Animation) -> Bool {
        let currentIds = tabs.map(\.id)
        guard currentIds.contains(tab.id) else {
            return false
        }
        guard regularDeferredRemovalGapIdsByTabId[tab.id] == nil else {
            return true
        }

        let gapId = UUID()
        let stagedItems = currentIds.map { tabId -> RegularTabRenderedItem in
            tabId == tab.id ? .gap(gapId) : .tab(tabId)
        }
        let generation = regularLayoutAnimationGeneration + 1

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            regularLayoutAnimationGeneration = generation
            regularRenderedTabItems = stagedItems
            regularGapHeights[gapId] = SidebarRowLayout.rowHeight
            regularDeferredRemovalGapIdsByTabId[tab.id] = gapId
        }

        DispatchQueue.main.async {
            withAnimation(animation) {
                regularGapHeights[gapId] = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) {
            guard regularDeferredRemovalGapIdsByTabId[tab.id] == gapId else { return }
            onCloseTab(tab)
        }

        return true
    }

    private func completeDeferredRegularRemoval(
        removedId: UUID,
        gapId: UUID,
        newIds: [UUID]
    ) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            regularRenderedTabItems = newIds.map(RegularTabRenderedItem.tab)
            regularGapHeights.removeValue(forKey: gapId)
            regularDeferredRemovalGapIdsByTabId.removeValue(forKey: removedId)
            regularLayoutAnimationGeneration += 1
        }
    }

    private func completeRegularInsertionAnimation(
        generation: Int,
        finalItems: [RegularTabRenderedItem],
        insertedId: UUID
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) {
            guard regularLayoutAnimationGeneration == generation else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                regularRenderedTabItems = finalItems
                regularInsertedTabHeights.removeValue(forKey: insertedId)
            }
        }
    }

    private func completeRegularRemovalAnimation(
        generation: Int,
        finalItems: [RegularTabRenderedItem],
        gapId: UUID
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) {
            guard regularLayoutAnimationGeneration == generation else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                regularRenderedTabItems = finalItems
                regularGapHeights.removeValue(forKey: gapId)
            }
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
        guard dragState.isCompletingDrop,
              let sourceContainer = dragState.projectionDragScope?.sourceContainer,
              sourceContainer != .spaceRegular(space.id) else {
            return false
        }

        switch sourceContainer {
        case .essentials, .spacePinned, .folder:
            return true
        case .spaceRegular, .none:
            return false
        }
    }

    private var regularExternalDropGapPlacement: RegularExternalDropGapPlacement? {
        guard dragState.isDragging,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.hoveredSlot,
              hoveredSpaceId == space.id,
              let location = dragState.dragLocation,
              let listMetrics = dragState.regularListHitTargets[space.id] else {
            return nil
        }

        if slot == 0, location.y < listMetrics.frame.minY {
            return .top
        }

        if showsBottomNewTabButton,
           location.y > listMetrics.frame.maxY {
            return .bottom
        }

        return nil
    }

    private var regularDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
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
            onMute: { onMuteTab(tab) },
            contextMenuEntries: { regularTabContextMenuEntries(tab) }
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
        if let animation = sidebarContentMutationAnimation {
            if !animateRegularDeferredRemoval(tab, animation: animation) {
                onCloseTab(tab)
            }
        } else {
            onCloseTab(tab)
        }
    }

    private func regularTabContextMenuEntries(_ tab: Tab) -> [SidebarContextMenuEntry] {
        let profiles = browserManager.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: browserManager.tabManager.folders(for: space.id)
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: browserManager.tabManager.spaces,
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
            : { browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id) }
        let addToEssentialsAction: (() -> Void)? = canAddTabToEssentials(tab)
            ? {
                browserManager.tabManager.pinTab(
                    tab,
                    context: .init(windowState: windowState, spaceId: space.id)
                )
            }
            : nil
        let closeTabsBelowAction: (() -> Void)? = !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil
            ? { browserManager.tabManager.closeAllTabsBelow(tab) }
            : nil
        let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
            browserManager.tabManager.moveTab(tab.id, to: targetSpaceId)
        }

        return makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: .init(
                duplicate: { browserManager.duplicateTab(tab, in: windowState) },
                copyLink: { copyLink(tab.url) },
                share: {
                    presentSharePicker(
                        for: tab.url,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                rename: { tab.startRenaming() },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in
                        browserManager.tabManager.moveTabToFolder(tab: tab, folderId: folderId)
                    }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: moveToSpaceAction
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        browserManager.tabManager.assign(tab: tab, toProfile: profileId)
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
        guard !tab.isPinned && !tab.isSpacePinned else { return false }
        return browserManager.tabManager.canAddURLToEssentials(
            tab.url,
            using: .init(windowState: windowState, spaceId: space.id)
        )
    }

    private func regularDropGuideOverlay(itemCount: Int) -> some View {
        GeometryReader { geometry in
            if let localY = regularDropGuideLocalY(in: geometry, itemCount: itemCount) {
                dropLine()
                    .offset(y: localY - SidebarInsertionGuide.visualCenterY)
                    .transition(.opacity)
                    .animation(dropGuideAnimation, value: localY)
            }
        }
        .allowsHitTesting(false)
    }

    private func regularDropGuideLocalY(in geometry: GeometryProxy, itemCount: Int) -> CGFloat? {
        guard dragState.isDragging,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.hoveredSlot,
              hoveredSpaceId == space.id,
              let metrics = dragState.regularListHitTargets[space.id],
              itemCount > 0 else {
            return nil
        }

        let safeSlot = max(0, min(slot, itemCount))
        let globalY: CGFloat
        if safeSlot == itemCount {
            globalY = metrics.frame.maxY
        } else {
            let rowSpacing = itemCount > 1
                ? max(0, (metrics.frame.height - (CGFloat(itemCount) * SidebarRowLayout.rowHeight)) / CGFloat(itemCount - 1))
                : 0
            globalY = metrics.frame.minY + CGFloat(safeSlot) * (SidebarRowLayout.rowHeight + rowSpacing)
        }

        return globalY - geometry.frame(in: .global).minY
    }

    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }

    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }

    private func handleUserTabActivation(_ tab: Tab) {
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func regularTabExclusionZones(for tab: Tab) -> [SidebarDragSourceExclusionZone] {
        var exclusions: [SidebarDragSourceExclusionZone] = [.trailingStrip(40)]
        if tab.audioState.showsTabAudioButton {
            exclusions.append(.fixedRect(SpaceTab.audioButtonHitFrame))
        }
        return exclusions
    }

    private func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource? = nil
    ) {
        if let source {
            browserManager.presentSharingServicePicker([url], source: source)
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}

private struct RegularInsertedTabPreviewTitle: View {
    let title: String
    let color: Color
    let trailingFadePadding: CGFloat

    private let fadeWidth: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .allowsTightening(false)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipped()
                .mask(
                    RegularInsertedTabPreviewTitleFadeMask(
                        fadeWidth: fadeWidth,
                        trailingPadding: trailingFadePadding
                    )
                )
        }
        .frame(height: SidebarRowLayout.titleHeight, alignment: .center)
        .accessibilityLabel(title)
    }
}

private struct RegularInsertedTabPreviewTitleFadeMask: View {
    let fadeWidth: CGFloat
    let trailingPadding: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let availableWidth = max(width - trailingPadding, 0)
            let safeFadeWidth = min(fadeWidth, availableWidth)
            let start = width > 0
                ? (width - (trailingPadding + safeFadeWidth)) / width
                : 1
            let end = width > 0
                ? (width - trailingPadding) / width
                : 1

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: max(0, min(start, 1))),
                    .init(color: .clear, location: max(0, min(end, 1))),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
