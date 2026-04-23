//
//  SpaceView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct TabPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct SpaceContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum SpaceViewRenderMode {
    case interactive
    case transitionSnapshot

    var isInteractive: Bool {
        self == .interactive
    }

    var debugDescription: String {
        switch self {
        case .interactive:
            return "interactive"
        case .transitionSnapshot:
            return "transitionSnapshot"
        }
    }
}

@MainActor
private final class SidebarSelectionScrollGuard {
    private var lockedUntil: Date = .distantPast

    func lock(for duration: TimeInterval = 0.3) {
        lockedUntil = Date().addingTimeInterval(duration)
    }

    var isLocked: Bool {
        Date() < lockedUntil
    }
}

@MainActor
private final class SidebarPreferenceUpdateCoalescer {
    private var lastTabPositionUpdate: Date = .distantPast

    func shouldApplyTabPositionUpdate(minimumInterval: TimeInterval = 0.1) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastTabPositionUpdate) > minimumInterval else { return false }
        lastTabPositionUpdate = now
        return true
    }
}

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

struct ShortcutLinkEditorSheet: View {
    let pin: ShortcutPin
    let onSave: (String, URL) -> Void
    /// Dismiss `DialogManager` overlay — use async when closing from `NSMenu`-related paths (`FolderIconPickerSheet`).
    let onRequestClose: () -> Void

    @State private var title: String
    @State private var urlText: String

    init(
        pin: ShortcutPin,
        onSave: @escaping (String, URL) -> Void,
        onRequestClose: @escaping () -> Void
    ) {
        self.pin = pin
        self.onSave = onSave
        self.onRequestClose = onRequestClose
        _title = State(initialValue: pin.title)
        _urlText = State(initialValue: pin.launchURL.absoluteString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Launcher Link")
                .font(.headline)

            Form {
                TextField("Display Name", text: $title)
                    .accessibilityIdentifier("shortcut-link-editor-title-field")
                TextField("Launcher URL", text: $urlText)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("shortcut-link-editor-url-field")
            }
            .formStyle(.grouped)
            .accessibilityElement(children: .contain)

            HStack {
                Spacer()
                Button("Cancel") {
                    onRequestClose()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    guard let resolvedURL = normalizedLaunchURL(from: urlText) else { return }
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    onRequestClose()
                    onSave(trimmedTitle.isEmpty ? pin.title : trimmedTitle, resolvedURL)
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedLaunchURL(from: urlText) == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shortcut-link-editor-sheet")
    }

    private func normalizedLaunchURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }
        return URL(string: "https://\(trimmed)")
    }
}

struct SpaceView: View {
    let space: Space
    let renderMode: SpaceViewRenderMode
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @ObservedObject private var dragState = SidebarDragState.shared
    @State private var canScrollUp: Bool = false
    @State private var canScrollDown: Bool = false
    @State private var showTopArrow: Bool = false
    @State private var showBottomArrow: Bool = false
    @State private var isAtTop: Bool = true
    @State private var viewportHeight: CGFloat = 0
    @State private var totalContentHeight: CGFloat = 0
    @State private var activeTabPosition: CGRect = .zero
    @State private var scrollOffset: CGFloat = 0
    @State private var tabPositions: [UUID: CGRect] = [:]
    @State private var lastScrollOffset: CGFloat = 0
    @State private var selectionScrollGuard = SidebarSelectionScrollGuard()
    @State private var preferenceUpdateCoalescer = SidebarPreferenceUpdateCoalescer()
    @State private var deferredScrollStateMutation = SidebarDeferredStateMutation<CGRect>()
    @State private var deferredContentHeightMutation = SidebarDeferredStateMutation<CGFloat>()
    @Environment(\.resolvedThemeContext) private var themeContext

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    @EnvironmentObject var splitManager: SplitViewManager

    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserManager.getSavedSidebarWidth(for: windowState)
        return max(fallbackWidth, 0)
    }

    private var innerWidth: CGFloat {
        max(outerWidth - 16, 0)
    }

    private var isInteractive: Bool {
        renderMode.isInteractive
    }

    private var showsScrollIndicator: Bool {
        isInteractive && totalContentHeight > viewportHeight + 1
    }

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


    var body: some View {
        let _ = browserManager.tabStructuralRevision

        VStack(spacing: 4) {
            SpaceTitle(space: space, isAppKitInteractionEnabled: isInteractive)

            mainContentContainer
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
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

    private var mainContentContainer: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            pinnedTabsSection

                            VStack(spacing: 8) {
                                regularTabsSection
                            }
                        }
                        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: SpaceContentHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                        .coordinateSpace(name: "ScrollSpace")
                    }
                    .accessibilityIdentifier("space-view-scroll-\(space.id.uuidString)")
                    .scrollIndicators(.hidden)
                    .contentShape(Rectangle())
                    .onScrollGeometryChange(for: CGRect.self) { geometry in
                        geometry.bounds
                    } action: { oldBounds, newBounds in
                        guard isInteractive else { return }
                        deferredScrollStateMutation.schedule(newBounds) { bounds in
                            guard isInteractive else { return }
                            updateScrollState(bounds: bounds)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if showsScrollIndicator {
                            sidebarScrollIndicator
                                .padding(.trailing, 1)
                        }
                    }
                    VStack {
                        if showTopArrow {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToTop(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .zIndex(10)

                    VStack {
                        Spacer()
                        if showBottomArrow {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToActiveTab(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .onPreferenceChange(TabPositionPreferenceKey.self) { positions in
                    guard isInteractive else { return }
                    guard preferenceUpdateCoalescer.shouldApplyTabPositionUpdate() else { return }

                    let snapshot = positions
                    Task { @MainActor in
                        if tabPositions != snapshot {
                            tabPositions = snapshot
                        }
                        updateActiveTabPosition()
                    }
                }
                .onPreferenceChange(SpaceContentHeightPreferenceKey.self) { contentHeight in
                    guard isInteractive else { return }
                    deferredContentHeightMutation.schedule(contentHeight) { resolvedContentHeight in
                        guard isInteractive else { return }
                        guard abs(totalContentHeight - resolvedContentHeight) > 0.5 else { return }
                        totalContentHeight = resolvedContentHeight
                        updateArrowIndicators()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var sidebarScrollIndicator: some View {
        GeometryReader { geometry in
            let availableHeight = max(geometry.size.height - 8, 1)
            let thumbHeight = max(26, availableHeight * max(min(viewportHeight / max(totalContentHeight, 1), 1), 0))
            let maxTravel = max(availableHeight - thumbHeight, 0)
            let progress = max(
                0,
                min(
                    scrollOffset / max(totalContentHeight - viewportHeight, 1),
                    1
                )
            )

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.28))
                .frame(width: 3, height: thumbHeight)
                .offset(y: 4 + maxTravel * progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pinnedTabsSection: some View {
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
            ForEach(Array(allItems.enumerated()), id: \.element.id) { sourceIndex, item in
                VStack(spacing: 0) {
                    if isHoveredSpacePinned(before: sourceIndex) { dropLine().transition(.opacity) }
                    switch item {
                    case .folder(let folderId):
                        if let folder = folders.first(where: { $0.id == folderId }) {
                            mixedFolderView(folder, topLevelPinnedIndex: sourceIndex)
                        }
                    case .shortcut(let pinId):
                        if let pin = topLevelPinnedPins.first(where: { $0.id == pinId }) {
                            pinnedShortcutView(pin)
                        }
                    }
                    if isHoveredSpacePinned(after: sourceIndex, total: allItems.count) { dropLine().transition(.opacity) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .transition(.opacity.animation(.easeInOut(duration: 0.12)))
    }

    private func pinnedShortcutView(_ pin: ShortcutPin) -> some View {
        let activeTab = activeShortcutTab(for: pin)
        let rowId = activeTab?.id ?? pin.id
        return ShortcutSidebarRow(
            pin: pin,
            liveTab: activeTab,
            scrollTargetID: rowId,
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
        .background {
            if windowState.currentTabId == rowId {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: TabPositionPreferenceKey.self, value: [rowId: geometry.frame(in: .named("ScrollSpace"))])
                }
            }
        }
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

    private var newTabRow: some View {
        Button(action: openNewTabCommandPalette) {
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
        .sidebarHoverTarget(
            newTabHoverTarget,
            isEnabled: isInteractive,
            animation: .easeInOut(duration: 0.12)
        )
        .accessibilityIdentifier("space-new-tab-\(space.id.uuidString)")
        .sidebarAppKitPrimaryAction(isEnabled: isInteractive, action: openNewTabCommandPalette)
    }

    private var displayIsNewTabHovered: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(newTabHoverTarget)
            && !windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var newTabHoverTarget: SidebarHoverTarget {
        .row("space-new-tab-\(space.id.uuidString)")
    }

    private func openNewTabCommandPalette() {
        guard isInteractive else { return }
        browserManager.openCommandPalette(in: windowState, reason: .keyboard)
    }

    private var topNewTabButtonSection: some View {
        newTabRow
            .padding(.top, 4)
    }

    private var bottomNewTabButtonSection: some View {
        newTabRow
    }

    private var regularTabsSection: some View {
        VStack(spacing: 0) {
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

                if showsBottomNewTabButton {
                    bottomNewTabButtonSection
                }
            }
            .padding(.top, 8)

            regularTabsDragSpacer
        }
        .sidebarSectionGeometry(
            for: .spaceRegular,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var regularTabsListHitRegion: some View {
        VStack(spacing: 0) {
            regularTabsListInner
        }
        .sidebarRegularListHitGeometry(
            for: space.id,
            itemCount: tabs.count,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var regularTabsListInner: some View {
        Group {
            if !tabs.isEmpty {
                regularTabsContent
            }
        }
        .animation(isInteractive ? .easeInOut(duration: 0.15) : nil, value: tabs.count)
    }

    private var regularTabsContent: some View {
        VStack(spacing: 2) {
            let currentTabs = tabs
            let split = splitManager
            let windowId = windowState.id
            if !SidebarDragState.shared.isDragging,
               split.isSplit(for: windowId),
               let leftId = split.leftTabId(for: windowId), let rightId = split.rightTabId(for: windowId),
               let leftIdx = currentTabs.firstIndex(where: { $0.id == leftId }),
               let rightIdx = currentTabs.firstIndex(where: { $0.id == rightId }),
               leftIdx >= 0, rightIdx >= 0,
               leftIdx < currentTabs.count, rightIdx < currentTabs.count,
               leftIdx != rightIdx {
                splitTabsView(currentTabs: currentTabs, leftIdx: leftIdx, rightIdx: rightIdx)
            } else {
                regularTabsView(currentTabs: currentTabs)
            }
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var regularTabsDragSpacer: some View {
        Color.clear
            .frame(height: tabs.isEmpty ? 48 : 24)
    }

    private func splitTabsView(currentTabs: [Tab], leftIdx: Int, rightIdx: Int) -> some View {
        let firstIdx = min(leftIdx, rightIdx)
        let secondIdx = max(leftIdx, rightIdx)

        return ForEach(Array(currentTabs.enumerated()), id: \.element.id) { pair in
            let (idx, tab) = pair
            if idx == firstIdx {
                VStack(spacing: 2) {
                    let left = currentTabs[leftIdx]
                    let right = currentTabs[rightIdx]

                    SplitTabRow(
                        left: left,
                        right: right,
                        spaceId: space.id,
                        isAppKitInteractionEnabled: isInteractive,
                        contextMenuEntries: regularTabContextMenuEntries,
                        onActivate: onActivateTab,
                        onClose: onCloseTab
                    )
                    .environmentObject(browserManager)
                }
            } else if idx == secondIdx {
                EmptyView()
            } else {
                regularTabView(tab)
            }
        }
    }

    private func regularTabsView(currentTabs: [Tab]) -> some View {
        return LazyVStack(spacing: 2) {
            ForEach(Array(currentTabs.enumerated()), id: \.element.id) { index, tab in
                VStack(spacing: 0) {
                    if dragState.isDragging, case .spaceRegular(let dsId, let slot) = dragState.hoveredSlot, dsId == space.id, slot == index {
                        dropLine()
                            .transition(.opacity)
                    }
                    regularTabView(tab)
                    if dragState.isDragging, case .spaceRegular(let dsId, let slot) = dragState.hoveredSlot, dsId == space.id, index == currentTabs.count - 1, slot >= currentTabs.count {
                        dropLine()
                            .transition(.opacity)
                    }
                }
            }
        }
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
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) },
            contextMenuEntries: regularTabContextMenuEntries(tab)
        )
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == tab.id
                ? 0.001
                : 1
        )
        .id(tab.id)
        .background {
            if windowState.currentTabId == tab.id {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: TabPositionPreferenceKey.self, value: [tab.id: geometry.frame(in: .named("ScrollSpace"))])
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("space-regular-tab-\(tab.id.uuidString)")
        .accessibilityValue(windowState.currentTabId == tab.id ? "selected" : "not selected")
    }

    private func regularTabContextMenuEntries(_ tab: Tab) -> [SidebarContextMenuEntry] {
        let folderChoices = browserManager.tabManager.folders(for: space.id).map { folder in
            SidebarContextMenuChoice(id: folder.id, title: folder.name)
        }
        let spaceChoices = browserManager.tabManager.spaces.map { targetSpace in
            SidebarContextMenuChoice(
                id: targetSpace.id,
                title: targetSpace.name,
                isSelected: targetSpace.id == tab.spaceId
            )
        }

        return makeRegularTabContextMenuEntries(
            folders: folderChoices,
            spaces: spaceChoices,
            showsAddToFavorites: !tab.isPinned && !tab.isSpacePinned,
            canMoveUp: !isFirstTab(tab),
            canMoveDown: !isLastTab(tab),
            showsCloseAllBelow: !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil,
            callbacks: .init(
                onAddToFolder: { folderId in
                    browserManager.tabManager.moveTabToFolder(tab: tab, folderId: folderId)
                },
                onAddToFavorites: {
                    browserManager.tabManager.pinTab(
                        tab,
                        context: .init(windowState: windowState, spaceId: space.id)
                    )
                },
                onCopyLink: { copyLink(tab.url) },
                onShare: {
                    presentSharePicker(
                        for: tab.url,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onRename: { tab.startRenaming() },
                onSplitRight: { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) },
                onSplitLeft: { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) },
                onDuplicate: { browserManager.duplicateTab(tab, in: windowState) },
                onMoveToSpace: { targetSpaceId in browserManager.tabManager.moveTab(tab.id, to: targetSpaceId) },
                onMoveUp: { onMoveTabUp(tab) },
                onMoveDown: { onMoveTabDown(tab) },
                onPinToSpace: { browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id) },
                onPinGlobally: { onPinTab(tab) },
                onCloseAllBelow: { browserManager.tabManager.closeAllTabsBelow(tab) },
                onClose: { onCloseTab(tab) }
            )
        )
    }

    @ViewBuilder
    private func dropLine(isFolder: Bool = false) -> some View {
        SidebarInsertionGuide()
            .padding(.horizontal, isFolder ? 16 : 8)
    }

    private func isHoveredSpacePinned(before index: Int) -> Bool {
        if dragState.isDragging, case .spacePinned(let id, let s) = dragState.hoveredSlot, id == space.id, s == index { return true }
        return false
    }

    private func isHoveredSpacePinned(after index: Int, total: Int) -> Bool {
        if dragState.isDragging, case .spacePinned(let id, let s) = dragState.hoveredSlot, id == space.id, index == total - 1, s == total { return true }
        return false
    }

    // MARK: - Folder Management

    private func deleteFolder(_ folder: TabFolder) {
        browserManager.tabManager.deleteFolder(folder.id)
    }

    private func addTabToFolder(_ folder: TabFolder) {
        let newTab = browserManager.tabManager.createNewTab(in: space)
        browserManager.tabManager.moveTabToFolder(tab: newTab, folderId: folder.id)
    }

    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }

    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }

    // MARK: - Scroll State

    private func updateScrollState(bounds: CGRect) {
        guard isInteractive else { return }
        let minY = bounds.minY
        let contentHeight = bounds.height

        if abs(viewportHeight - contentHeight) > 0.5 {
            viewportHeight = contentHeight
        }
        let newScrollOffset = -minY
        if abs(scrollOffset - newScrollOffset) > 0.5 {
            scrollOffset = newScrollOffset
        }
        if abs(lastScrollOffset - newScrollOffset) > 0.5 {
            lastScrollOffset = newScrollOffset
        }

        let newCanScrollUp = minY < 0
        if canScrollUp != newCanScrollUp {
            canScrollUp = newCanScrollUp
        }

        let newCanScrollDown = totalContentHeight > viewportHeight && (-minY + viewportHeight) < totalContentHeight
        if canScrollDown != newCanScrollDown {
            canScrollDown = newCanScrollDown
        }

        let newIsAtTop = minY >= 0
        if isAtTop != newIsAtTop {
            isAtTop = newIsAtTop
        }

        updateContentHeight()
        updateArrowIndicators()
    }

    private func updateContentHeight() {
        totalContentHeight = max(totalContentHeight, 0)
    }

    private func handleUserTabActivation(_ tab: Tab) {
        selectionScrollGuard.lock()
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func updateActiveTabPosition() {
        guard isInteractive else {
            activeTabPosition = .zero
            showTopArrow = false
            showBottomArrow = false
            return
        }
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else {
            activeTabPosition = .zero
            showTopArrow = false
            showBottomArrow = false
            return
        }

        if let tabFrame = tabPositions[activeTab.id] {
            activeTabPosition = tabFrame
        }

        DispatchQueue.main.async {
            self.updateArrowIndicators()
        }
    }

    private func updateArrowIndicators() {
        guard isInteractive else {
            showTopArrow = false
            showBottomArrow = false
            return
        }
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else {
            // No active tab in this space, don't show arrows
            showTopArrow = false
            showBottomArrow = false
            return
        }

        guard !selectionScrollGuard.isLocked else {
            showTopArrow = false
            showBottomArrow = false
            return
        }

        let activeTabTop = activeTabPosition.minY
        let activeTabBottom = activeTabPosition.maxY

        let activeTabIsAbove = activeTabBottom < scrollOffset
        let activeTabIsBelow = activeTabTop > scrollOffset + viewportHeight
        showTopArrow = activeTabIsAbove && canScrollUp
        showBottomArrow = activeTabIsBelow && canScrollDown
    }

    private func scrollToActiveTab(proxy: ScrollViewProxy) {
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else { return }

        guard !selectionScrollGuard.isLocked else { return }

        updateContentHeight()
        updateActiveTabPosition()

        let activeTabTop = activeTabPosition.minY
        if activeTabTop > scrollOffset + viewportHeight {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .bottom)
            }
            return
        }

        let activeTabBottom = activeTabPosition.maxY
        if activeTabBottom < scrollOffset {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .top)
            }
            return
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("space-separator-top", anchor: .top)
        }
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
        selectionScrollGuard.lock()
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

    private func regularTabExclusionZones(for tab: Tab) -> [SidebarDragSourceExclusionZone] {
        var exclusions: [SidebarDragSourceExclusionZone] = [.trailingStrip(40)]
        if tab.audioState.showsTabAudioButton {
            exclusions.append(.leadingStrip(72))
        }
        return exclusions
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

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

struct ShortcutSidebarRow: View {
    @ObservedObject var pin: ShortcutPin
    var liveTab: Tab? = nil
    var scrollTargetID: UUID? = nil
    var accessibilityID: String? = nil
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry] = { _ in [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID? = nil
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    var debugRenderMode: String = "unspecified"
    var onLauncherIconSelected: ((String) -> Void)? = nil
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if let liveTab {
                ShortcutSidebarLiveRowContent(
                    pin: pin,
                    liveTab: liveTab,
                    scrollTargetID: scrollTargetID,
                    accessibilityID: accessibilityID,
                    contextMenuEntries: contextMenuEntries,
                    action: action,
                    dragSourceZone: dragSourceZone,
                    dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
                    dragIsEnabled: dragIsEnabled,
                    debugRenderMode: debugRenderMode,
                    onLauncherIconSelected: onLauncherIconSelected,
                    onResetToLaunchURL: onResetToLaunchURL,
                    onUnload: onUnload,
                    onRemove: onRemove
                )
            } else {
                ShortcutSidebarStoredRowContent(
                    pin: pin,
                    scrollTargetID: scrollTargetID,
                    accessibilityID: accessibilityID,
                    contextMenuEntries: contextMenuEntries,
                    action: action,
                    dragSourceZone: dragSourceZone,
                    dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
                    dragIsEnabled: dragIsEnabled,
                    debugRenderMode: debugRenderMode,
                    onLauncherIconSelected: onLauncherIconSelected,
                    onResetToLaunchURL: onResetToLaunchURL,
                    onUnload: onUnload,
                    onRemove: onRemove
                )
            }
        }
    }
}

private struct ShortcutSidebarLiveRowContent: View {
    @ObservedObject var pin: ShortcutPin
    @ObservedObject var liveTab: Tab
    var scrollTargetID: UUID?
    var accessibilityID: String?
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    var debugRenderMode: String
    var onLauncherIconSelected: ((String) -> Void)?
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let splitSide = splitManager.side(for: liveTab.id, in: windowState.id)

        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: liveTab,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            showsSplitBadge: splitSide != nil,
            splitBadgeIsSelected: splitManager.activeSide(for: windowState.id) == splitSide,
            scrollTargetID: scrollTargetID,
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            debugRenderMode: debugRenderMode,
            onLauncherIconSelected: onLauncherIconSelected,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarStoredRowContent: View {
    @ObservedObject var pin: ShortcutPin
    var scrollTargetID: UUID?
    var accessibilityID: String?
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    var debugRenderMode: String
    var onLauncherIconSelected: ((String) -> Void)?
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: nil,
            resolvedTitle: pin.preferredDisplayTitle,
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            showsSplitBadge: false,
            splitBadgeIsSelected: false,
            scrollTargetID: scrollTargetID,
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            debugRenderMode: debugRenderMode,
            onLauncherIconSelected: onLauncherIconSelected,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarRowChrome: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let resolvedTitle: String
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let showsSplitBadge: Bool
    let splitBadgeIsSelected: Bool
    var scrollTargetID: UUID? = nil
    var accessibilityID: String? = nil
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry] = { _ in [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID? = nil
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    var debugRenderMode: String = "unspecified"
    var onLauncherIconSelected: ((String) -> Void)? = nil
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var markerInstanceID = UUID()
    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(12)
        HStack(spacing: 0) {
            if runtimeAffordance.usesResetLeadingAction, let onResetToLaunchURL {
                Button(action: onResetToLaunchURL) {
                    resetLeadingButtonContent
                }
                .buttonStyle(.plain)
                .sidebarHoverTarget(
                    resetHoverTarget,
                    isEnabled: dragIsEnabled,
                    animation: .easeInOut(duration: 0.1)
                )
                .accessibilityIdentifier(resetActionAccessibilityID ?? "shortcut-sidebar-reset")
                .sidebarAppKitPrimaryAction(
                    isInteractionEnabled: dragIsEnabled,
                    action: onResetToLaunchURL
                )
            }

            ZStack {
                HStack(spacing: 0) {
                    if !runtimeAffordance.usesResetLeadingAction {
                        rowIcon
                            .padding(.leading, SidebarRowLayout.leadingInset)
                            .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    if let liveTab {
                        LauncherAudioButton(
                            tab: liveTab,
                            foregroundColor: textColor,
                            mutedForegroundColor: tokens.secondaryText,
                            hoverBackground: actionBackground,
                            accessibilityID: launcherAudioAccessibilityID,
                            isAppKitInteractionEnabled: dragIsEnabled
                        )
                        .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    titleStack
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, runtimeAffordance.usesResetLeadingAction ? SidebarRowLayout.changedLauncherTitleLeading : 0)
                .padding(.trailing, showsActionButton ? 0 : SidebarRowLayout.trailingInset)
                .frame(height: SidebarRowLayout.rowHeight)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .onTapGesture(perform: action)

            Button(action: performActionButton) {
                Image(systemName: actionIconName)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(textColor)
                    .frame(width: 24, height: 24)
                    .background(displayIsActionHovering ? actionBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .opacity(showsActionButton ? 1 : 0)
            .allowsHitTesting(showsActionButton && !freezesHoverState)
            .accessibilityHidden(!showsActionButton)
            .sidebarHoverTarget(
                actionHoverTarget,
                isEnabled: showsActionButton && dragIsEnabled,
                animation: .easeInOut(duration: 0.05)
            )
            .accessibilityIdentifier(trailingActionAccessibilityID ?? "shortcut-sidebar-action")
            .sidebarAppKitPrimaryAction(
                isEnabled: showsActionButton && !freezesHoverState,
                isInteractionEnabled: dragIsEnabled,
                action: performActionButton
            )
            .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .background(EmojiPickerAnchor(manager: emojiManager))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if showsSplitBadge {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(splitBadgeIsSelected ? Color.accentColor : tokens.secondaryText)
                    .padding(4)
                    .background(tokens.fieldBackground, in: Circle())
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
            }
        }
        // Expose the row container itself so the launcher keeps the same source identity
        // when runtime drift replaces the leading favicon with the reset control.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-row")
        .accessibilityValue(runtimeAffordance.isSelected ? "selected" : "not selected")
        .sidebarHoverTarget(
            rowHoverTarget,
            isEnabled: dragIsEnabled,
            animation: .easeInOut(duration: 0.05)
        )
        .onAppear {
            recordShortcutSidebarMarker("shortcutRowAppear")
        }
        .onDisappear {
            recordShortcutSidebarMarker("shortcutRowDisappear")
        }
        .onChange(of: liveTab?.id) { _, _ in
            recordShortcutSidebarMarker("shortcutRowLiveTabChange")
        }
        .onChange(of: runtimeAffordance.usesResetLeadingAction) { _, _ in
            recordShortcutSidebarMarker("shortcutRowResetAffordanceChange")
        }
        .onChange(of: runtimeAffordance.isSelected) { _, _ in
            recordShortcutSidebarMarker("shortcutRowSelectionChange")
        }
        .background {
            if let scrollTargetID {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(scrollTargetID)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: dragIsEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            sourceID: accessibilityID ?? "shortcut-sidebar-row",
            entries: { contextMenuEntries(toggleLauncherIconPicker) }
        )
        .onChange(of: emojiManager.committedEmoji) { _, newValue in
            guard !newValue.isEmpty else { return }
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(newValue)
            guard let onLauncherIconSelected else { return }
            DispatchQueue.main.async {
                onLauncherIconSelected(normalized)
            }
        }
        .shadow(
            color: runtimeAffordance.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: runtimeAffordance.isSelected ? 2 : 0,
            y: runtimeAffordance.isSelected ? 1 : 0
        )
    }

    private func recordShortcutSidebarMarker(_ name: String) {
        let sourceID = accessibilityID ?? "shortcut-sidebar-row"
        let mode = liveTab == nil ? "stored" : "live"
        SidebarUITestDragMarker.recordEvent(
            name,
            dragItemID: pin.id,
            ownerDescription: "ShortcutSidebarRowChrome{instance=\(markerInstanceID.uuidString)}",
            sourceID: sourceID,
            viewDescription: "swiftui:\(markerInstanceID.uuidString)",
            details: "source=\(sourceID) pin=\(pin.id.uuidString) liveTab=\(liveTab?.id.uuidString ?? "nil") mode=\(mode) renderMode=\(debugRenderMode) dragIsEnabled=\(dragIsEnabled) resetLeading=\(runtimeAffordance.usesResetLeadingAction) selected=\(runtimeAffordance.isSelected) window=\(windowState.id.uuidString)"
        )
    }

    private var rowIcon: some View {
        Group {
            if let launcherIconAsset = pin.iconAsset {
                launcherGlyph(for: launcherIconAsset)
            } else if let systemName = pin.pinnedChromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(textColor)
            } else {
                pin.favicon
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .saturation(runtimeAffordance.shouldDesaturateIcon ? 0.0 : 1.0)
        .opacity(runtimeAffordance.shouldDesaturateIcon ? 0.8 : 1.0)
    }

    @ViewBuilder
    private func launcherGlyph(for iconAsset: String) -> some View {
        if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
            Text(iconAsset)
                .font(.system(size: SidebarRowLayout.faviconSize * 0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(.center)
                .frame(
                    width: SidebarRowLayout.faviconSize,
                    height: SidebarRowLayout.faviconSize,
                    alignment: .center
                )
        } else {
            Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
                .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(textColor)
        }
    }

    private func toggleLauncherIconPicker() {
        guard onLauncherIconSelected != nil else { return }
        emojiManager.selectedEmoji = pin.iconAsset.flatMap { iconAsset in
            SumiPersistentGlyph.presentsAsEmoji(iconAsset) ? iconAsset : nil
        } ?? ""
        emojiManager.toggle(
            source: windowState.resolveSidebarPresentationSource()
        ) { picked in
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(picked)
            onLauncherIconSelected?(normalized)
        }
    }

    private var resetLeadingButtonContent: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                rowIcon
                    .padding(.leading, SidebarRowLayout.changedLauncherResetIconLeading)
                Spacer(minLength: 0)
            }
            .frame(
                width: SidebarRowLayout.changedLauncherResetWidth,
                height: SidebarRowLayout.changedLauncherResetHeight,
                alignment: .leading
            )
            .background(displayIsResetHovering ? actionBackground : Color.clear)
            .clipShape(resetHighlightShape)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tokens.secondaryText.opacity(displayIsResetHovering ? 0 : 0.3))
                .frame(
                    width: SidebarRowLayout.changedLauncherSeparatorWidth,
                    height: SidebarRowLayout.changedLauncherSeparatorHeight
                )
                .rotationEffect(.degrees(15))
        }
        .frame(
            width: SidebarRowLayout.changedLauncherResetWidth,
            height: SidebarRowLayout.changedLauncherResetHeight,
            alignment: .leading
        )
        .padding(.trailing, SidebarRowLayout.changedLauncherResetTrailingGap)
    }

    private var resetHighlightShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 8,
                bottomLeading: 8,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    @ViewBuilder
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleLabel

            if runtimeAffordance.showsChangedURLSlash {
                Text("Back to pinned url")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tokens.secondaryText.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxHeight: displayIsResetHovering ? 10 : 0, alignment: .topLeading)
                    .opacity(displayIsResetHovering ? 0.65 : 0)
                    .clipped()
            }
        }
        .animation(.easeInOut(duration: 0.1), value: displayIsResetHovering)
    }

    @ViewBuilder
    private var titleLabel: some View {
        SumiTabTitleLabel(
            title: resolvedTitle,
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: textColor,
            animated: liveTab != nil
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundColor: Color {
        if runtimeAffordance.isSelected {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var actionBackground: Color {
        runtimeAffordance.isSelected
            ? tokens.fieldBackgroundHover
            : tokens.fieldBackground
    }

    private var actionIconName: String {
        runtimeAffordance.isOpenLive ? "minus" : "xmark"
    }

    private var trailingActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "action")
    }

    private var resetActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "reset")
    }

    private var launcherAudioAccessibilityID: String? {
        actionAccessibilityID(suffix: "audio")
    }

    private var showsActionButton: Bool {
        displayIsHovering || runtimeAffordance.isSelected
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(rowHoverTarget)
            && !freezesHoverState
    }

    private var displayIsActionHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(actionHoverTarget)
            && !freezesHoverState
    }

    private var displayIsResetHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(resetHoverTarget)
            && !freezesHoverState
    }

    private var rowHoverTarget: SidebarHoverTarget {
        .row(accessibilityID ?? "shortcut-sidebar-row-\(pin.id.uuidString)")
    }

    private var actionHoverTarget: SidebarHoverTarget {
        .action(trailingActionAccessibilityID ?? "shortcut-sidebar-action-\(pin.id.uuidString)")
    }

    private var resetHoverTarget: SidebarHoverTarget {
        .action(resetActionAccessibilityID ?? "shortcut-sidebar-reset-\(pin.id.uuidString)")
    }

    private var dragSourceConfiguration: SidebarDragSourceConfiguration? {
        makeShortcutSidebarDragSourceConfiguration(
            pin: pin,
            resolvedTitle: resolvedTitle,
            runtimeAffordance: runtimeAffordance,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            action: action,
            dragIsEnabled: dragIsEnabled
        )
    }

    private var textColor: Color {
        tokens.primaryText
    }

    private func performActionButton() {
        if runtimeAffordance.isOpenLive {
            onUnload()
            return
        }
        onRemove()
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func actionAccessibilityID(suffix: String) -> String? {
        guard let accessibilityID else { return nil }
        if let id = accessibilityID.replacingPrefix("space-pinned-shortcut-", with: "space-pinned-shortcut-\(suffix)-") {
            return id
        }
        if let id = accessibilityID.replacingPrefix("folder-shortcut-", with: "folder-shortcut-\(suffix)-") {
            return id
        }
        return "\(accessibilityID)-\(suffix)"
    }
}

@MainActor
func makeShortcutSidebarDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragSourceZone: DropZoneID?,
    dragHasTrailingActionExclusion: Bool,
    action: (() -> Void)? = nil,
    dragIsEnabled: Bool = true
) -> SidebarDragSourceConfiguration? {
    guard let dragSourceZone else { return nil }

    return SidebarDragSourceConfiguration(
        item: SumiDragItem(
            tabId: pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: dragSourceZone,
        previewKind: .row,
        previewIcon: pin.favicon,
        exclusionZones: makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: runtimeAffordance,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion
        ),
        onActivate: action,
        isEnabled: dragIsEnabled
    )
}

@MainActor
func makeShortcutSidebarDragExclusionZones(
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragHasTrailingActionExclusion: Bool
) -> [SidebarDragSourceExclusionZone] {
    var exclusions: [SidebarDragSourceExclusionZone] = []
    if runtimeAffordance.usesResetLeadingAction {
        exclusions.append(.leadingStrip(SidebarRowLayout.changedLauncherResetWidth + 12))
    }
    if dragHasTrailingActionExclusion {
        exclusions.append(.trailingStrip(40))
    }
    return exclusions
}

private struct LauncherAudioButton: View {
    @ObservedObject var tab: Tab
    let foregroundColor: Color
    let mutedForegroundColor: Color
    let hoverBackground: Color
    let accessibilityID: String?
    let isAppKitInteractionEnabled: Bool
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        Group {
            if tab.audioState.showsTabAudioButton {
                Button {
                    tab.toggleMute()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(displayIsHovering ? hoverBackground : Color.clear)
                            .frame(width: 22, height: 22)

                        Image(systemName: tab.audioState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tab.audioState.isMuted ? mutedForegroundColor : foregroundColor)
                            .id(tab.audioState.isMuted)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                                    removal: .scale(scale: 1.08).combined(with: .opacity)
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
                .sidebarHoverTarget(
                    hoverTarget,
                    isEnabled: isAppKitInteractionEnabled,
                    animation: .easeInOut(duration: 0.1)
                )
                .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-audio")
                .sidebarAppKitPrimaryAction(
                    isEnabled: !windowState.sidebarInteractionState.freezesSidebarHoverState,
                    isInteractionEnabled: isAppKitInteractionEnabled,
                    action: tab.toggleMute
                )
                .help(tab.audioState.isMuted ? "Unmute Audio" : "Mute Audio")
                .animation(.easeInOut(duration: 0.1), value: tab.audioState.isMuted)
            }
        }
    }

    private var displayIsHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(hoverTarget)
            && !windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var hoverTarget: SidebarHoverTarget {
        .action(accessibilityID ?? "shortcut-sidebar-audio-\(tab.id.uuidString)")
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return replacement + String(dropFirst(prefix.count))
    }
}
