//
//  SpacePinnedSection.swift
//  Sumi
//

import AppKit
import SwiftUI

private enum SpacePinnedListItem: Hashable {
    case folder(UUID)
    case shortcut(UUID)

    var id: UUID {
        switch self {
        case .folder(let id), .shortcut(let id):
            return id
        }
    }
}

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
        !topLevelPinnedPins.isEmpty || !folders.isEmpty
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
        let currentFolders = folders
        let currentPins = topLevelPinnedPins

        // Early return if no content
        guard !currentPins.isEmpty || !currentFolders.isEmpty else {
            return []
        }

        return (
            currentFolders.map { ($0.index, SpacePinnedListItem.folder($0.id)) }
            + currentPins.map { ($0.index, SpacePinnedListItem.shortcut($0.id)) }
        )
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            switch (lhs.1, rhs.1) {
            case (.folder(let leftId), .folder(let rightId)):
                return leftId.uuidString < rightId.uuidString
            case (.shortcut(let leftId), .shortcut(let rightId)):
                return leftId.uuidString < rightId.uuidString
            case (.folder, .shortcut):
                return true
            case (.shortcut, .folder):
                return false
            }
        }
        .map(\.1)
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
    }

    private func pinnedShortcutView(_ pin: ShortcutPin, topLevelPinnedIndex: Int) -> some View {
        let activeTab = activeShortcutTab(for: pin)
        return ShortcutSidebarRow(
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
            onRemove: { browserManager.tabManager.removeShortcutPin(pin) }
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
                onUnpin: { browserManager.tabManager.removeShortcutPin(pin) },
                onMoveToRegularTabs: { browserManager.tabManager.convertShortcutPinToRegularTab(pin, in: space.id) },
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
        browserManager.tabManager.deleteFolder(folder.id)
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

    private func openShortcutPinInSplit(_ pin: ShortcutPin, side: SplitViewManager.Side) {
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
