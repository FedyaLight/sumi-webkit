//
//  SpacePinnedSection.swift
//  Sumi
//

import AppKit
import SwiftUI

private typealias SpacePinnedListItem = TabManager.SpacePinnedVisualItem

private enum SpacePinnedRenderedItem: Hashable {
    case item(SpacePinnedListItem)
    case dragPlaceholder
    case restoreGap(UUID)
}

private struct SpacePinnedDisplayEntry: Identifiable {
    let item: SpacePinnedRenderedItem
    let dropIndex: Int
    let id: String
}

extension SpaceView {
    private var launcherProjection: TabManager.SpaceLauncherProjection? {
        guard windowState.isIncognito == false else { return nil }
        return browserManager.tabManager.launcherProjection(for: space.id, in: windowState.id)
    }

    private var topLevelPinnedPins: [ShortcutPin] {
        if windowState.isIncognito {
            return []
        }
        return launcherProjection?.topLevelPins ?? []
    }

    private var folders: [TabFolder] {
        if windowState.isIncognito {
            return []
        }
        return launcherProjection?.topLevelFolders ?? []
    }

    private var hasSpacePinnedContent: Bool {
        !spacePinnedItems.isEmpty
            || shortcutRestoreGaps.contains { $0.container == .spacePinned(space.id) }
    }

    private var showsEmptyPinnedDropPlaceholder: Bool {
        !hasSpacePinnedContent
            && isInteractive
            && isHoveringThisSpacePinnedWhileEmpty
    }

    private var isHoveringThisSpacePinnedWhileEmpty: Bool {
        guard case .spacePinned(let sid, _) = dragState.hoveredSlot else { return false }
        return sid == space.id
    }


    private var dropGuideEdgeAllowance: CGFloat {
        SidebarInsertionGuide.visualCenterY
    }



    private var spacePinnedItems: [SpacePinnedListItem] {
        guard !windowState.isIncognito else { return [] }
        return browserManager.tabManager.topLevelSpacePinnedVisualItems(for: space.id)
    }

    private var projectedSpacePinnedItems: [ProjectedItem<SpacePinnedListItem>] {
        SidebarDropProjection.projectedItems(
            itemIDs: spacePinnedItems,
            removesSourceID: spacePinnedProjectedSourceItem,
            insertsPlaceholderAt: spacePinnedProjectedInsertionIndex
        )
    }

    private var projectedSpacePinnedDisplayEntries: [SpacePinnedDisplayEntry] {
        var itemCount = 0
        return renderedSpacePinnedItems.map { item in
            let entry = SpacePinnedDisplayEntry(
                item: item,
                dropIndex: itemCount,
                id: projectedSpacePinnedDisplayID(for: item, placeholderIndex: itemCount)
            )
            switch item {
            case .item:
                itemCount += 1
            case .dragPlaceholder, .restoreGap:
                break
            }
            return entry
        }
    }

    private var renderedSpacePinnedItems: [SpacePinnedRenderedItem] {
        var rendered = projectedSpacePinnedItems.map { item -> SpacePinnedRenderedItem in
            switch item {
            case .item(let listItem):
                return .item(listItem)
            case .placeholder:
                return .dragPlaceholder
            }
        }

        let gaps = shortcutRestoreGaps.filter { gap in
            gap.container == .spacePinned(space.id)
        }
        for gap in gaps.sorted(by: { $0.index < $1.index }) {
            rendered.removeAll { item in
                if case .item(.shortcut(let pinId)) = item {
                    return pinId == gap.pinId
                }
                return false
            }
            rendered.insert(.restoreGap(gap.id), at: max(0, min(gap.index, rendered.count)))
        }

        return rendered
    }

    private func projectedSpacePinnedDisplayID(
        for item: SpacePinnedRenderedItem,
        placeholderIndex: Int
    ) -> String {
        switch item {
        case .item(let listItem):
            return "item-\(listItem.id.uuidString)"
        case .dragPlaceholder:
            if let projectionDragItemId = dragState.projectionDragItemId {
                return "item-\(projectionDragItemId.uuidString)"
            }
            return "placeholder-\(placeholderIndex)"
        case .restoreGap(let gapId):
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }) {
                return "item-\(gap.pinId.uuidString)"
            }
            return "restore-gap-\(gapId.uuidString)"
        }
    }

    private var spacePinnedUsesProjectedDropLayout: Bool {
        spacePinnedProjectedSourceItem != nil || spacePinnedProjectedInsertionIndex != nil
    }

    private var spacePinnedProjectedSourceItem: SpacePinnedListItem? {
        guard dragState.isDropProjectionActive,
              dragState.projectionDragScope?.sourceContainer == .spacePinned(space.id),
              let projectionDragItemId = dragState.projectionDragItemId else {
            return nil
        }
        return spacePinnedItems.first { $0.id == projectionDragItemId }
    }

    private var spacePinnedProjectedInsertionIndex: Int? {
        guard dragState.isDropProjectionActive,
              case .spacePinned(let hoveredSpaceId, let slot) = dragState.projectionHoveredSlot,
              hoveredSpaceId == space.id else {
            return nil
        }
        guard dragState.projectionFolderDropIntent == .none else {
            return nil
        }
        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .spacePinned(space.id),
                targetAlreadyContainsDraggedItem: spacePinnedItems.contains { $0.id == projectionDragItemId }
           ) {
            return nil
        }
        return slot
    }

    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        browserManager.showShortcutEditor(
            for: pin,
            in: windowState,
            themeContext: themeContext,
            source: source ?? windowState.resolveSidebarPresentationSource()
        )
    }

    var pinnedTabsSection: some View {
        Group {
            if hasSpacePinnedContent {
                pinnedTabsList
                    .transition(
                        isInteractive
                            ? .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.3)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.2))
                            )
                            : .identity
                    )
            } else {
                pinnedRevealStrip
            }
        }
        .animation(isInteractive ? .easeInOut(duration: 0.25) : nil, value: hasSpacePinnedContent)
        .animation(isInteractive ? .easeInOut(duration: 0.18) : nil, value: showsEmptyPinnedDropPlaceholder)
        .animation(sidebarContentMutationAnimation, value: spacePinnedItems)
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .sidebarSectionGeometry(
            for: .spacePinned,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private func performShortcutHostedSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) {
        if SplitGroupSidebarModel.member(for: item, in: group)?.isShortcutBacked == true {
            performShortcutRestoreWithPreparedGap(for: item, in: group) {
                performPinnedSplitModelMutation {
                    browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
                }
            }
            return
        }

        guard let tab = item.tab else { return }
        performPinnedSplitModelMutation {
            browserManager.closeTab(tab, in: windowState)
        }
    }

    private func performPinnedSplitModelMutation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, update)
    }

    @ViewBuilder
    private func shortcutHostedSplitGroupView(_ group: SplitGroup, topLevelPinnedIndex: Int) -> some View {
        let items = SplitGroupSidebarModel.items(for: group, tabManager: browserManager.tabManager)
        if !items.isEmpty {
            SplitGroupSidebarRow(
                group: group,
                items: items,
                spaceId: space.id,
                isAppKitInteractionEnabled: isInteractive,
                segmentAction: { item in
                    SplitGroupSidebarModel.segmentAction(for: item, in: group)
                },
                dragSource: { item in
                    shortcutHostedSplitSegmentDragSource(for: item, in: group)
                },
                contextMenuEntries: { _ in [] },
                onActivate: { tab in
                    browserManager.requestUserTabActivation(tab, in: windowState)
                },
                onActivateGroup: {
                    browserManager.focusSplitGroup(group, in: windowState)
                },
                onSegmentActionAnimationStart: { item in
                    if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
                        prepareShortcutRestoreGap(for: item, in: group)
                    }
                },
                onSegmentAction: { item in
                    performShortcutHostedSegmentAction(for: item, in: group)
                }
            )
            .environmentObject(browserManager)
            .environmentObject(splitManager)
            .accessibilityIdentifier("shortcut-host-split-row-\(group.id.uuidString)")
            .sidebarTopLevelPinnedItemGeometry(
                itemId: group.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SidebarDragSourceConfiguration? {
        let member = SplitGroupSidebarModel.member(for: item, in: group)
        if let pin = SplitGroupSidebarModel.shortcutPin(
            for: item,
            member: member,
            tabManager: browserManager.tabManager
        ) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: SplitGroupSidebarModel.sourceZone(for: pin, fallbackSpaceId: space.id),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: {
                    browserManager.focusSplitGroup(group, in: windowState)
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
            onActivate: {
                browserManager.requestUserTabActivation(tab, in: windowState)
            },
            isEnabled: isInteractive
        )
    }

    private var pinnedTabsList: some View {
        let allItems = projectedSpacePinnedDisplayEntries
        
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: dropGuideEdgeAllowance)
                .allowsHitTesting(false)

            ForEach(allItems) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .item(.folder(let folderId)):
                        if let folder = folders.first(where: { $0.id == folderId }) {
                            mixedFolderView(folder, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .item(.shortcut(let pinId)):
                        if let pin = topLevelPinnedPins.first(where: { $0.id == pinId }) {
                            pinnedShortcutView(pin, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .item(.splitGroup(let groupId)):
                        if let group = browserManager.tabManager.splitGroup(with: groupId) {
                            shortcutHostedSplitGroupView(group, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .dragPlaceholder:
                        pinnedDropGap
                    case .restoreGap(let gapId):
                        shortcutRestoreGap(gapId)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projectedSpacePinnedItems
        )
        .animation(sidebarContentMutationAnimation, value: spacePinnedItems)
        .animation(sidebarContentMutationAnimation, value: shortcutRestoreGaps)
        .animation(sidebarContentMutationAnimation, value: shortcutRestoreGapHeights.map { "\($0.key.uuidString):\($0.value)" }.sorted())
        .padding(.bottom, 8) // Add padding to act as drag tail for spacePinned
    }

    private var pinnedDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .accessibilityHidden(true)
    }

    private func shortcutRestoreGap(_ gapId: UUID) -> some View {
        let height = shortcutRestoreGapHeights[gapId] ?? 0
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }),
               let pin = browserManager.tabManager.shortcutPin(by: gap.pinId) {
                pinnedShortcutView(pin, topLevelPinnedIndex: gap.index)
                    .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
            }
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(sidebarContentMutationAnimation, value: height)
    }

    private var pinnedRevealStrip: some View {
        VStack(spacing: 0) {
            if showsEmptyPinnedDropPlaceholder {
                Color.clear
                    .frame(height: SidebarRowLayout.rowHeight)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(
            height: showsEmptyPinnedDropPlaceholder ? SidebarRowLayout.rowHeight : 6,
            alignment: .top
        )
    }

    private func mixedFolderView(_ folder: TabFolder, topLevelPinnedIndex: Int) -> some View {
        TabFolderView(
            folder: folder,
            space: space,
            shortcutPins: launcherProjection?.folderPins[folder.id] ?? [],
            childFolders: launcherProjection?.childFolders[folder.id] ?? [],
            childFoldersByParentId: launcherProjection?.childFolders ?? [:],
            folderPinsByFolderId: launcherProjection?.folderPins ?? [:],
            shortcutRestoreGaps: $shortcutRestoreGaps,
            shortcutRestoreGapHeights: $shortcutRestoreGapHeights,
            renderMode: renderMode,
            parentFolderId: nil,
            containerIndex: topLevelPinnedIndex,
            nestingDepth: 0,
            onUngroup: { ungroupFolder(folder) },
            onDelete: { deleteFolder(folder) },
            onPrepareShortcutRestoreGap: { item, group in
                prepareShortcutRestoreGap(for: item, in: group)
            },
            onPerformShortcutRestoreWithPreparedGap: { item, group, update in
                performShortcutRestoreWithPreparedGap(for: item, in: group, update: update)
            }
        )
        .environmentObject(browserManager)
        .environment(windowState)
        .sidebarTopLevelPinnedItemGeometry(
            itemId: folder.id,
            spaceId: space.id,
            topLevelIndex: topLevelPinnedIndex,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .sidebarZenCompositeLifecycleTransition(isEnabled: isInteractive)
    }

    @ViewBuilder
    private func pinnedShortcutView(_ pin: ShortcutPin, topLevelPinnedIndex: Int) -> some View {
        if let placeholderGroup = browserManager.tabManager.regularHostedSplitPlaceholderGroup(for: pin) {
            ShortcutSplitPlaceholderRow(
                pin: pin,
                isSelected: isPinnedSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "space-pinned-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isInteractive,
                action: {
                    browserManager.focusSplitGroup(placeholderGroup, in: windowState)
                }
            )
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .sidebarTopLevelPinnedItemGeometry(
                itemId: pin.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
            .sidebarZenRowLifecycleTransition(isEnabled: isInteractive)
        } else {
            let activeTab = activeShortcutTab(for: pin)
            ShortcutSidebarRow(
                pin: pin,
                liveTab: activeTab,
                accessibilityID: "space-pinned-shortcut-\(pin.id.uuidString)",
                contextMenuEntries: {
                    pinnedShortcutContextMenuEntries(pin)
                },
                action: { activateShortcutPin(pin) },
                dragSourceZone: .spacePinned(space.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onResetToLaunchURL: { resetShortcutPin(pin) },
                onUnload: { unloadShortcutPin(pin) },
                onRemove: { removeShortcutPin(pin) }
            )
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .sidebarTopLevelPinnedItemGeometry(
                itemId: pin.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
            .sidebarZenRowLifecycleTransition(isEnabled: isInteractive)
        }
    }

    private func pinnedShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserManager.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: browserManager.tabManager.folders(for: space.id),
            selectedFolderId: pin.folderId
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: browserManager.tabManager.spaces,
            selectedSpaceId: pin.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: browserManager.tabManager.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: space.id
            )
        )
        let addToEssentialsAction: (() -> Void)? = browserManager.tabManager.canAddURLToEssentials(
            pin.launchURL,
            using: .init(windowState: windowState, spaceId: space.id)
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions: SidebarSavedURLDriftActions? =
            browserManager.tabManager.shortcutHasDrifted(pin, in: windowState)
                ? .init(
                    onBackToSavedURL: { resetShortcutPin(pin) },
                    onUseCurrentPageAsSavedURL: { _ = browserManager.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                )
                : nil
        let unloadAction: (() -> Void)? = presentationState.isOpenLive
            ? { unloadShortcutPin(pin) }
            : nil
        let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
            moveShortcutPin(pin, toSpace: targetSpaceId)
        }

        return makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            actions: .init(
                duplicate: { duplicateShortcutPin(pin) },
                copyLink: { copyLink(pin.launchURL) },
                share: {
                    presentSharePicker(
                        for: pin.launchURL,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in moveShortcutPin(pin, toFolder: folderId) }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: moveToSpaceAction
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        browserManager.tabManager.assign(
                            shortcutPin: pin,
                            toExecutionProfile: profileId
                        )
                    }
                ),
                addToEssentials: addToEssentialsAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
        )
    }

    // MARK: - Folder Management

    private func ungroupFolder(_ folder: TabFolder) {
        mutatePinnedContent {
            browserManager.tabManager.ungroupFolder(folder.id)
        }
    }

    private func deleteFolder(_ folder: TabFolder) {
        let childCount = browserManager.tabManager.folderRecursiveChildCount(for: folder.id, in: space.id)
        guard childCount == 0 else {
            confirmDeleteFolder(folder, childCount: childCount)
            return
        }

        mutatePinnedContent {
            browserManager.tabManager.deleteFolder(folder.id)
        }
    }

    private func removeShortcutPin(_ pin: ShortcutPin) {
        mutatePinnedContent {
            browserManager.tabManager.removeShortcutPin(pin)
        }
    }

    private func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.window,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    private func confirmDeleteFolder(_ folder: TabFolder, childCount: Int) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
            folderName: folder.name,
            childCount: childCount,
            window: windowState.window,
            onDelete: {
                mutatePinnedContent {
                    browserManager.tabManager.deleteFolder(folder.id)
                }
            }
        )
    }

    private func mutatePinnedContent(_ update: () -> Void) {
        if let animation = sidebarContentMutationAnimation {
            withAnimation(animation) {
                update()
            }
        } else {
            update()
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
    }

    private func isPinnedSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        guard let currentTabId = windowState.currentTabId else {
            return false
        }
        return group.contains(currentTabId)
            || group.member(forPinId: pin.id)?.tabId == currentTabId
    }



    private func activateShortcutPin(_ pin: ShortcutPin) {
        let tab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func closeShortcutPinIfActive(_ pin: ShortcutPin) {
        guard let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState)
        else { return }
        browserManager.closeTab(current, in: windowState)
    }

    private func unloadShortcutPin(_ pin: ShortcutPin) {
        if let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserManager.closeTab(current, in: windowState)
            return
        }

        browserManager.tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    private func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserManager.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserManager.tabManager.folder(by: folderId) else { return }
        let targetIndex = browserManager.tabManager.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutatePinnedContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                index: targetIndex
            )
        }
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserManager.tabManager.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutatePinnedContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: targetIndex
            )
        }
    }

    private func resetShortcutPin(_ pin: ShortcutPin) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let preserveCurrentPage = modifiers.contains(.command) || modifiers.contains(.control)
        _ = browserManager.tabManager.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    private func pinShortcutGlobally(_ pin: ShortcutPin) {
        let syntheticTab = Tab(
            url: pin.launchURL,
            name: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: space.id,
            index: 0,
            browserManager: browserManager
        )
        browserManager.tabManager.pinTab(
            syntheticTab,
            context: .init(windowState: windowState, spaceId: space.id)
        )
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

struct ShortcutSplitPlaceholderRow: View {
    @ObservedObject var pin: ShortcutPin
    let isSelected: Bool
    let accessibilityID: String
    let isAppKitInteractionEnabled: Bool
    let action: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tokens.primaryText)
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.leading, SidebarRowLayout.leadingInset)
                .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

            SumiTabTitleLabel(
                title: pin.preferredDisplayTitle,
                font: .systemFont(ofSize: 13, weight: .medium),
                textColor: tokens.primaryText,
                trailingFadePadding: 0,
                animated: false,
                isLoading: false
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isAppKitInteractionEnabled,
            sourceID: accessibilityID,
            action: action
        )
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "split placeholder")
    }

    private var backgroundColor: Color {
        if isSelected {
            return tokens.sidebarRowActive
        }
        if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
