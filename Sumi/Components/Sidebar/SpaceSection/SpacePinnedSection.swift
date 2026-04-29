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
            && inlinePinnedGhostAsset != nil
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
        .sidebarSectionGeometry(
            for: .spacePinned,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var pinnedTabsList: some View {
        let allItems = spacePinnedItems
        
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: dropGuideEdgeAllowance)
                .allowsHitTesting(false)

            ForEach(Array(allItems.enumerated()), id: \.element.id) { sourceIndex, item in
                VStack(spacing: 0) {
                    switch item {
                    case .folder(let folderId):
                        if let folder = folders.first(where: { $0.id == folderId }) {
                            mixedFolderView(folder, topLevelPinnedIndex: sourceIndex)
                        }
                    case .shortcut(let pinId):
                        if let pin = topLevelPinnedPins.first(where: { $0.id == pinId }) {
                            pinnedShortcutView(pin, topLevelPinnedIndex: sourceIndex)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            spacePinnedDropGuideOverlay
        }
        .animation(isInteractive ? .easeInOut(duration: 0.25) : nil, value: folders.count)
        .animation(isInteractive ? .easeInOut(duration: 0.25) : nil, value: spacePinnedItems.count)
        .padding(.bottom, 8) // Add padding to act as drag tail for spacePinned
    }

    private var pinnedRevealStrip: some View {
        VStack(spacing: 0) {
            if showsEmptyPinnedDropPlaceholder {
                if pinnedEmptyDropShowsRowPreview, let asset = inlinePinnedGhostAsset {
                    Image(nsImage: asset.image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: asset.size.width, height: asset.size.height)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var inlinePinnedGhostAsset: SidebarDragPreviewAsset? {
        dragState.previewAssets[.row]
            ?? dragState.previewKind.flatMap { dragState.previewAssets[$0] }
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
            kind: .folder(folder.id),
            spaceId: space.id,
            topLevelIndex: topLevelPinnedIndex,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .transition(.opacity.animation(.easeInOut(duration: 0.12)))
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
            debugRenderMode: renderMode.debugDescription,
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
            kind: .shortcut(pin.id),
            spaceId: space.id,
            topLevelIndex: topLevelPinnedIndex,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .transition(.move(edge: .top).combined(with: .opacity))
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
        let sourceID = "space-pinned-shortcut-\(pin.id.uuidString)"
        SidebarUITestDragMarker.recordEvent(
            "resetShortcutAction",
            dragItemID: pin.id,
            ownerDescription: "SpaceView.resetShortcutPin",
            sourceID: sourceID,
            details: "phase=before pin=\(pin.id.uuidString) liveTab=\(activeShortcutTab(for: pin)?.id.uuidString ?? "nil") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "nil") currentTab=\(windowState.currentTabId?.uuidString ?? "nil") currentShortcutPin=\(windowState.currentShortcutPinId?.uuidString ?? "nil") sidebarVisible=\(windowState.isSidebarVisible) preserveCurrentPage=\(preserveCurrentPage)"
        )
        _ = browserManager.tabManager.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
        SidebarUITestDragMarker.recordEvent(
            "resetShortcutAction",
            dragItemID: pin.id,
            ownerDescription: "SpaceView.resetShortcutPin",
            sourceID: sourceID,
            details: "phase=after pin=\(pin.id.uuidString) liveTab=\(activeShortcutTab(for: pin)?.id.uuidString ?? "nil") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "nil") currentTab=\(windowState.currentTabId?.uuidString ?? "nil") currentShortcutPin=\(windowState.currentShortcutPinId?.uuidString ?? "nil") sidebarVisible=\(windowState.isSidebarVisible)"
        )
    }

    private func pinShortcutGlobally(_ pin: ShortcutPin) {
        let syntheticTab = Tab(
            url: pin.launchURL,
            name: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            favicon: pin.systemIconName,
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
