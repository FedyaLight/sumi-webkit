//
//  SpacePinnedSection.swift
//  Sumi
//

import AppKit
import SwiftUI

private typealias SpacePinnedListItem = TabManager.SpacePinnedVisualItem

private struct SpacePinnedDisplayEntry: Identifiable {
    let item: ProjectedItem<SpacePinnedListItem>
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
    }

    private var showsEmptyPinnedDropPlaceholder: Bool {
        !hasSpacePinnedContent
            && isInteractive
            && dragState.isDragging
    }

    private var isHoveringThisSpacePinnedWhileEmpty: Bool {
        guard case .spacePinned(let sid, _) = dragState.hoveredSlot else { return false }
        return sid == space.id
    }


    private var dropGuideEdgeAllowance: CGFloat {
        SidebarInsertionGuide.visualCenterY
    }

    private var pinnedEmptyDropShowsRowPreview: Bool {
        showsEmptyPinnedDropPlaceholder
            && isHoveringThisSpacePinnedWhileEmpty
            && inlinePinnedGhostPresentation != nil
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
        return projectedSpacePinnedItems.map { item in
            let entry = SpacePinnedDisplayEntry(
                item: item,
                dropIndex: itemCount,
                id: projectedSpacePinnedDisplayID(for: item, placeholderIndex: itemCount)
            )
            if case .item = item {
                itemCount += 1
            }
            return entry
        }
    }

    private func projectedSpacePinnedDisplayID(
        for item: ProjectedItem<SpacePinnedListItem>,
        placeholderIndex: Int
    ) -> String {
        switch item {
        case .item(let listItem):
            return "item-\(listItem.id.uuidString)"
        case .placeholder:
            if let projectionDragItemId = dragState.projectionDragItemId {
                return "item-\(projectionDragItemId.uuidString)"
            }
            return "placeholder-\(placeholderIndex)"
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

    /// Uses `DialogManager` instead of SwiftUI `.sheet` so presenting after `NSMenu` does not trip
    /// `_NSTouchBarFinderObservation` KVO faults on `SumiBrowserWindow` (see `TabFolderView.presentFolderIconPicker`).
    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        let manager = browserManager
        let settings = sumiSettings
        let theme = themeContext
        DispatchQueue.main.async {
            if let source {
                manager.showDialog(
                    ShortcutLinkEditorSheet(
                        pin: pin,
                        onSave: { newTitle, newURL in
                            DispatchQueue.main.async {
                                _ = manager.tabManager.updateShortcutPin(
                                    pin,
                                    title: newTitle,
                                    launchURL: newURL
                                )
                            }
                        },
                        onRequestClose: {
                            manager.closeDialog()
                        }
                    )
                    .environment(\.sumiSettings, settings)
                    .environment(\.resolvedThemeContext, theme),
                    source: source
                )
                return
            }

            manager.showDialog(
                ShortcutLinkEditorSheet(
                    pin: pin,
                    onSave: { newTitle, newURL in
                        DispatchQueue.main.async {
                            _ = manager.tabManager.updateShortcutPin(
                                pin,
                                title: newTitle,
                                launchURL: newURL
                            )
                        }
                    },
                    onRequestClose: {
                        manager.closeDialog()
                    }
                )
                .environment(\.sumiSettings, settings)
                .environment(\.resolvedThemeContext, theme)
            )
        }
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
        .animation(isInteractive ? .easeInOut(duration: 0.2) : nil, value: pinnedEmptyDropShowsRowPreview)
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

    private func shortcutHostedSplitGroupItems(_ group: SplitGroup) -> [SplitGroupSidebarItem] {
        group.tabIds.compactMap { id in
            if let tab = browserManager.tabManager.tab(for: id) {
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

    private func shortcutHostedSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        if shortcutHostedSplitMember(for: item, in: group)?.isShortcutBacked == true {
            return .restore
        }
        return item.tab == nil ? nil : .close
    }

    private func performShortcutHostedSegmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) {
        if shortcutHostedSplitMember(for: item, in: group)?.isShortcutBacked == true {
            browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
            return
        }

        guard let tab = item.tab else { return }
        browserManager.closeTab(tab, in: windowState)
    }

    private func shortcutHostedSplitMember(
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

    @ViewBuilder
    private func shortcutHostedSplitGroupView(_ group: SplitGroup, topLevelPinnedIndex: Int) -> some View {
        let items = shortcutHostedSplitGroupItems(group)
        if !items.isEmpty {
            SplitGroupSidebarRow(
                group: group,
                items: items,
                spaceId: space.id,
                isAppKitInteractionEnabled: isInteractive,
                segmentAction: { item in
                    shortcutHostedSegmentAction(for: item, in: group)
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
            .sidebarZenRowLifecycleTransition(isEnabled: isInteractive)
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SidebarDragSourceConfiguration? {
        let member = shortcutHostedSplitMember(for: item, in: group)
        if let pin = shortcutHostedSegmentShortcutPin(for: item, member: member) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: shortcutHostedSegmentSourceZone(for: pin),
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

    private func shortcutHostedSegmentShortcutPin(
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

    private func shortcutHostedSegmentSourceZone(for pin: ShortcutPin) -> DropZoneID {
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
                    case .placeholder:
                        pinnedDropGap
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if !spacePinnedUsesProjectedDropLayout {
                spacePinnedDropGuideOverlay
            }
        }
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projectedSpacePinnedItems
        )
        .animation(sidebarContentMutationAnimation, value: spacePinnedItems)
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

    private var pinnedRevealStrip: some View {
        VStack(spacing: 0) {
            if showsEmptyPinnedDropPlaceholder {
                if pinnedEmptyDropShowsRowPreview,
                   let presentation = inlinePinnedGhostPresentation {
                    SidebarTabRowPreviewVisual(
                        title: presentation.title,
                        icon: presentation.icon
                    )
                        .frame(height: SidebarRowLayout.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.82)
                        .scaleEffect(0.98)
                        .allowsHitTesting(false)
                } else {
                    SidebarPinnedEmptyDropDashPlaceholder()
                }
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

    private var inlinePinnedGhostPresentation: (title: String, icon: Image)? {
        if let model = dragState.previewModel {
            return (
                title: model.item.title,
                icon: model.previewIcon ?? Image(systemName: "globe")
            )
        }

        guard let draggedId = dragState.activeDragItemId,
              let proxyTab = browserManager.tabManager.resolveDragTab(for: draggedId) else {
            return nil
        }

        return (
            title: proxyTab.name,
            icon: proxyTab.favicon
        )
    }

    private func mixedFolderView(_ folder: TabFolder, topLevelPinnedIndex: Int) -> some View {
        TabFolderView(
            folder: folder,
            space: space,
            shortcutPins: launcherProjection?.folderPins[folder.id] ?? [],
            renderMode: renderMode,
            topLevelPinnedIndex: topLevelPinnedIndex,
            onDelete: { deleteFolder(folder) },
            onAddTab: { addTabToFolder(folder) }
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
                contextMenuEntries: { toggleEditIcon in
                    pinnedShortcutContextMenuEntries(pin, toggleEditIcon: toggleEditIcon)
                },
                action: { activateShortcutPin(pin) },
                dragSourceZone: .spacePinned(space.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onLauncherIconSelected: { newIconAsset in
                    _ = browserManager.tabManager.updateShortcutPin(pin, iconAsset: newIconAsset)
                },
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

    private func pinnedShortcutContextMenuEntries(
        _ pin: ShortcutPin,
        toggleEditIcon: @escaping () -> Void
    ) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)

        return makeSpacePinnedLauncherContextMenuEntries(
            hasRuntimeResetActions: browserManager.tabManager.shortcutHasDrifted(pin, in: windowState),
            showsCloseCurrentPage: presentationState.isSelected,
            callbacks: .init(
                onOpen: { activateShortcutPin(pin) },
                onSplitRight: { openShortcutPinInSplit(pin, side: .right) },
                onSplitLeft: { openShortcutPinInSplit(pin, side: .left) },
                onSplitTop: { openShortcutPinInSplit(pin, side: .top) },
                onSplitBottom: { openShortcutPinInSplit(pin, side: .bottom) },
                onDuplicate: {},
                onResetToLaunchURL: { resetShortcutPin(pin) },
                onReplaceLauncherURLWithCurrent: { _ = browserManager.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) },
                onEditIcon: toggleEditIcon,
                onEditLink: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onUnpin: { removeShortcutPin(pin) },
                onMoveToRegularTabs: { moveShortcutPinToRegularTabs(pin) },
                onPinGlobally: { pinShortcutGlobally(pin) },
                onCloseCurrentPage: { closeShortcutPinIfActive(pin) }
            )
        )
    }

    private var spacePinnedDropGuideOverlay: some View {
        GeometryReader { geometry in
            if let localY = spacePinnedDropGuideLocalY(in: geometry) {
                dropLine()
                    .offset(y: localY - SidebarInsertionGuide.visualCenterY)
                    .transition(.opacity)
                    .animation(dropGuideAnimation, value: localY)
            }
        }
        .allowsHitTesting(false)
    }

    private func spacePinnedDropGuideLocalY(in geometry: GeometryProxy) -> CGFloat? {
        guard dragState.isDragging,
              case .spacePinned(let hoveredSpaceId, let slot) = dragState.hoveredSlot,
              hoveredSpaceId == space.id,
              let globalY = spacePinnedDropGuideGlobalY(slot: slot) else {
            return nil
        }

        return globalY - geometry.frame(in: .global).minY
    }

    private func spacePinnedDropGuideGlobalY(slot: Int) -> CGFloat? {
        let items = dragState.topLevelPinnedItemTargets.values
            .filter { $0.spaceId == space.id }
            .sorted { lhs, rhs in
                if lhs.topLevelIndex != rhs.topLevelIndex {
                    return lhs.topLevelIndex < rhs.topLevelIndex
                }
                return lhs.itemId.uuidString < rhs.itemId.uuidString
            }

        guard !items.isEmpty else {
            return dragState.sectionFrame(for: .spacePinned, in: space.id)?.minY
        }

        if let target = items.first(where: { $0.topLevelIndex >= slot }) {
            return target.frame.minY
        }

        return items.last?.frame.maxY
    }

    // MARK: - Folder Management

    private func deleteFolder(_ folder: TabFolder) {
        mutatePinnedContent {
            browserManager.tabManager.deleteFolder(folder.id)
        }
    }

    private func removeShortcutPin(_ pin: ShortcutPin) {
        mutatePinnedContent {
            browserManager.tabManager.removeShortcutPin(pin)
        }
    }

    private func moveShortcutPinToRegularTabs(_ pin: ShortcutPin) {
        mutatePinnedContent {
            browserManager.tabManager.convertShortcutPinToRegularTab(pin, in: space.id)
        }
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

    private func addTabToFolder(_ folder: TabFolder) {
        let newTab = browserManager.tabManager.createNewTab(in: space)
        browserManager.tabManager.moveTabToFolder(tab: newTab, folderId: folder.id)
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

    private func openShortcutPinInSplit(_ pin: ShortcutPin, side: SplitDropSide) {
        let liveTab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        browserManager.splitManager.enterSplit(with: liveTab, placeOn: side, in: windowState)
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
