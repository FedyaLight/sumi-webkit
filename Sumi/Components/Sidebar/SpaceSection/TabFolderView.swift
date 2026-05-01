//
//  TabFolderView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct TabFolderView: View {
    private enum FolderListItem: Hashable {
        case shortcut(UUID)
    }

    private static let folderContentLeadingPadding: CGFloat = 14
    private static let folderContentVerticalPadding: CGFloat = 4
    private static let zenFolderContentAnimation = Animation.easeInOut(duration: 0.18)

    @ObservedObject var folder: TabFolder
    let space: Space
    let renderMode: SpaceViewRenderMode
    let topLevelPinnedIndex: Int?
    let onDelete: () -> Void
    let onAddTab: () -> Void

    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var measuredExpandedFolderContentHeight: CGFloat = 0
    @State private var measuredCollapsedFolderContentHeight: CGFloat = 0
    @State private var displayedCollapsedProjectionIDs: [UUID] = []
    @State private var deferredExpandedHeightMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var deferredCollapsedHeightMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var isFolderHeaderHovered = false
    @FocusState private var nameFieldFocused: Bool

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject private var dragState = SidebarDragState.shared

    private var isInteractive: Bool {
        renderMode.isInteractive
    }

    private var launcherProjection: TabManager.SpaceLauncherProjection {
        browserManager.tabManager.launcherProjection(for: space.id, in: windowState.id)
    }

    private var shortcutPinsInFolder: [ShortcutPin] {
        launcherProjection.folderPins[folder.id] ?? []
    }

    private var folderProjectionState: SidebarFolderProjectionState {
        windowState.sidebarFolderProjection(for: folder.id)
    }

    private var folderItems: [FolderListItem] {
        shortcutPinsInFolder
            .map { ($0.index, FolderListItem.shortcut($0.id)) }
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
            .map(\.1)
    }

    private var targetCollapsedProjectionPins: [ShortcutPin] {
        guard !folder.isOpen else { return [] }
        return collapsedProjectedShortcutPins(using: folderProjectionState.projectedChildIDs)
    }

    private var targetCollapsedProjectionIDs: [UUID] {
        targetCollapsedProjectionPins.map(\.id)
    }

    private var visibleCollapsedProjectionIDs: [UUID] {
        displayedCollapsedProjectionIDs.isEmpty
            ? targetCollapsedProjectionIDs
            : displayedCollapsedProjectionIDs
    }

    private var visibleCollapsedProjectionPins: [ShortcutPin] {
        visibleCollapsedProjectionIDs.compactMap { pinId in
            shortcutPinsInFolder.first { $0.id == pinId }
        }
    }

    private var visibleFolderBodyItems: [FolderListItem] {
        folder.isOpen
            ? folderItems
            : visibleCollapsedProjectionIDs.map(FolderListItem.shortcut)
    }

    private var hasCollapsedProjectionForLayout: Bool {
        !displayedCollapsedProjectionIDs.isEmpty || !targetCollapsedProjectionIDs.isEmpty
    }

    private func collapsedProjectedShortcutPins(
        using projectedChildIDs: [UUID]
    ) -> [ShortcutPin] {
        let livePins = shortcutPinsInFolder.filter { pin in
            browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id) != nil
        }

        guard !projectedChildIDs.isEmpty else {
            return livePins.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        let projectedOrder = Dictionary(
            uniqueKeysWithValues: projectedChildIDs.enumerated().map { ($1, $0) }
        )
        return livePins.sorted { lhs, rhs in
            let leftOrder = projectedOrder[lhs.id] ?? lhs.index
            let rightOrder = projectedOrder[rhs.id] ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // Replaced by SidebarDragState
    private var isFolderContainTargeted: Bool {
        dragState.folderDropIntent == .contain(folderId: folder.id)
    }

    private var isFolderDropHighlighted: Bool {
        isFolderContainTargeted
    }

    private var folderPreviewIsOpen: Bool {
        folder.isOpen || isFolderDragOpenPreviewed
    }

    private var isFolderDragOpenPreviewed: Bool {
        dragState.isDragging
            && !folder.isOpen
            && dragState.activeHoveredFolderId == folder.id
    }

    private var resolvedTopLevelPinnedIndex: Int {
        topLevelPinnedIndex ?? 0
    }

    private var folderInsertionGuideLeading: CGFloat {
        max(
            0,
            SidebarRowLayout.leadingInset +
                SidebarRowLayout.folderTitleLeading -
                Self.folderContentLeadingPadding
        )
    }

    private var folderDragHighlightHorizontalBleed: CGFloat {
        8
    }

    private var isTopLevelPinnedFolder: Bool {
        topLevelPinnedIndex != nil
    }

    private var expandedFolderContentFallbackHeight: CGFloat {
        (CGFloat(folderItems.count) * SidebarRowLayout.rowHeight) +
            (Self.folderContentVerticalPadding * 2)
    }

    private var collapsedFolderContentFallbackHeight: CGFloat {
        let projectedCount = max(
            displayedCollapsedProjectionIDs.count,
            targetCollapsedProjectionIDs.count
        )
        guard projectedCount > 0 else { return 0 }
        return (CGFloat(projectedCount) * SidebarRowLayout.rowHeight) +
            (Self.folderContentVerticalPadding * 2)
    }

    private var expandedFolderContentHeight: CGFloat {
        max(measuredExpandedFolderContentHeight, expandedFolderContentFallbackHeight)
    }

    private var collapsedFolderContentHeight: CGFloat {
        guard hasCollapsedProjectionForLayout else { return 0 }
        return max(measuredCollapsedFolderContentHeight, collapsedFolderContentFallbackHeight)
    }

    private var folderBodyTargetHeight: CGFloat {
        folder.isOpen ? expandedFolderContentHeight : collapsedFolderContentHeight
    }

    private var folderBodyTargetOpacity: Double {
        folderBodyTargetHeight > 0 ? 1 : 0
    }

    private var folderBodyGeometryIsActive: Bool {
        isInteractive && (folder.isOpen || hasCollapsedProjectionForLayout)
    }

    private var folderHasActiveSelection: Bool {
        if let currentShortcutPinId = windowState.currentShortcutPinId,
           shortcutPinsInFolder.contains(where: { $0.id == currentShortcutPinId }) {
            return true
        }

        guard let currentTabId = windowState.currentTabId else { return false }
        return shortcutPinsInFolder.contains { pin in
            browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)?.id == currentTabId
        }
    }

    private var folderForegroundColor: Color {
        tokens.primaryText
    }

    private var folderShellPalette: SumiFolderGlyphPalette {
        let accent = themeContext.gradient.primaryColor
        let scheme = themeContext.chromeColorScheme

        let backFill: Color
        let frontFill: Color
        let stroke: Color

        switch scheme {
        case .light:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        case .dark:
            backFill = accent.mixed(with: Color(hex: "C1C1C1"), amount: 0.4)
            frontFill = accent.mixed(with: .black, amount: 0.4)
            stroke = Color(hex: "EBEBEB").mixed(with: tokens.primaryText, amount: 0.15)
        @unknown default:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        }

        let iconForeground = stroke.mixed(with: folderForegroundColor, amount: 0.35)

        return SumiFolderGlyphPalette(
            backFill: backFill,
            frontFill: frontFill,
            stroke: stroke,
            iconForeground: iconForeground,
            backOverlayTop: Color.white.opacity(0.1),
            backOverlayBottom: Color.black.opacity(0.1),
            frontOverlayTop: Color.white.opacity(0.1),
            frontOverlayBottom: Color.black.opacity(0.1)
        )
    }

    var body: some View {
        let _ = browserManager.tabStructuralRevision

        folderCompositeContent
            .onChange(of: targetCollapsedProjectionIDs) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: folder.isOpen) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: windowState.currentTabId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: windowState.currentShortcutPinId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onAppear {
                syncDisplayedCollapsedProjectionIDs(animated: false)
                scheduleProjectionStateRefresh()
            }
    }

    private var folderCompositeContent: some View {
        VStack(spacing: 0) {
            folderHeader
            folderBodyContainer
        }
        .overlay(alignment: .bottom) {
            folderAfterDropTarget
        }
    }

    @ViewBuilder
    private var folderBodyContainer: some View {
        folderBodyAnimatedContent
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: folderItems.count,
                isOpen: folder.isOpen,
                region: .body,
                generation: dragState.sidebarGeometryGeneration,
                isActive: folderBodyGeometryIsActive
            )
    }

    private var folderBodyAnimatedContent: some View {
        ZStack(alignment: .topLeading) {
            folderBodyVisibleContent
            folderBodyHeightMeasurements
        }
        .frame(height: folderBodyTargetHeight, alignment: .top)
        .opacity(folderBodyTargetOpacity)
        .clipped()
        .overlay(alignment: .topLeading) {
            folderDropIndicator
        }
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: folder.isOpen)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: folderBodyTargetHeight)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: folderBodyTargetOpacity)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: folderItems)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: displayedCollapsedProjectionIDs)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: targetCollapsedProjectionIDs)
    }

    private var folderBodyVisibleContent: some View {
        folderBodyContent(
            items: visibleFolderBodyItems,
            reportsGeometry: true,
            reportsFolderChildGeometry: folder.isOpen
        )
        .allowsHitTesting(folder.isOpen || !visibleCollapsedProjectionIDs.isEmpty)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: folder.isOpen)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: visibleFolderBodyItems)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: displayedCollapsedProjectionIDs)
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: targetCollapsedProjectionIDs)
    }

    private var folderBodyHeightMeasurements: some View {
        ZStack(alignment: .topLeading) {
            folderContent(reportsGeometry: false)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    FolderBodyHeightReader { height in
                        deferredExpandedHeightMutation.schedule(height) { resolvedHeight in
                            updateMeasuredExpandedFolderContentHeight(resolvedHeight)
                        }
                    }
                }
                .hidden()

            collapsedFolderContent
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    FolderBodyHeightReader { height in
                        deferredCollapsedHeightMutation.schedule(height) { resolvedHeight in
                            updateMeasuredCollapsedFolderContentHeight(resolvedHeight)
                        }
                    }
                }
                .hidden()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var folderAfterDropTarget: some View {
        if isTopLevelPinnedFolder {
            let height = dragState.isDragging ? SidebarRowLayout.rowHeight * 0.45 : 0
            Color.clear
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .offset(y: height / 2)
                .sidebarFolderDropGeometry(
                    folderId: folder.id,
                    spaceId: space.id,
                    topLevelIndex: resolvedTopLevelPinnedIndex,
                    childCount: folderItems.count,
                    isOpen: folder.isOpen,
                    region: .after,
                    generation: dragState.sidebarGeometryGeneration,
                    isActive: isInteractive && height > 0
                )
                .allowsHitTesting(false)
        }
    }

    private var folderDropIndicator: some View {
        Group {
            switch dragState.folderDropIntent {
            case .insertIntoFolder(let folderId, let index) where folderId == folder.id:
                folderInsertionGuide(slot: index)
                    .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: index)
            default:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
    }

    private func folderInsertionGuide(slot: Int) -> some View {
        let safeSlot = max(0, min(slot, folderItems.count))
        let centerY = Self.folderContentVerticalPadding + CGFloat(safeSlot) * SidebarRowLayout.rowHeight

        return SidebarInsertionGuide()
            .padding(.leading, folderInsertionGuideLeading)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .offset(y: centerY - SidebarInsertionGuide.visualCenterY)
    }

    private var folderHeaderContainGuide: some View {
        SidebarInsertionGuide()
            .padding(.leading, SidebarRowLayout.leadingInset + SidebarRowLayout.folderTitleLeading)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .offset(y: SidebarInsertionGuide.visualCenterY)
            .allowsHitTesting(false)
    }

    private var folderHeader: some View {
        folderHeaderRow
        .sidebarFolderDropGeometry(
            folderId: folder.id,
            spaceId: space.id,
            topLevelIndex: resolvedTopLevelPinnedIndex,
            childCount: folderItems.count,
            isOpen: folder.isOpen,
            region: .header,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        .sidebarAppKitContextMenu(
            isEnabled: !isRenaming,
            isInteractionEnabled: isInteractive,
            dragSource: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(folderId: folder.id, title: folder.name),
                sourceZone: .spacePinned(space.id),
                previewKind: .folderRow,
                pinnedConfig: .large,
                folderGlyphPresentation: folderGlyphPresentation,
                folderGlyphPalette: folderShellPalette,
                onActivate: {
                    toggleFolderOpenState()
                },
                isEnabled: !isRenaming
                    && isInteractive
            ),
            primaryAction: {
                guard !isRenaming else { return }
                toggleFolderOpenState()
            },
            sourceID: "folder-header-\(folder.id.uuidString)",
            entries: {
                folderHeaderContextMenuEntries()
            }
        )
        .accessibilityIdentifier("folder-header-\(folder.id.uuidString)")
        .accessibilityValue(folder.isOpen ? "expanded" : "collapsed")
    }

    private var folderHeaderRow: some View {
        HStack(spacing: 0) {
            folderHeaderIconSlot
            folderTitleView
            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(alignment: .center) {
            if isFolderDropHighlighted {
                Rectangle()
                    .fill(tokens.sidebarRowHover)
                    .padding(.horizontal, -folderDragHighlightHorizontalBleed)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(displayIsHovering ? tokens.sidebarRowHover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) {
            if isFolderContainTargeted && (!folder.isOpen || folderItems.isEmpty) {
                folderHeaderContainGuide
            }
        }
        .sidebarDDGHover($isFolderHeaderHovered, isEnabled: isInteractive)
    }

    @ViewBuilder
    private var folderTitleView: some View {
        if isRenaming {
            TextField("", text: $draftName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(folderForegroundColor)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .focused($nameFieldFocused)
                .onAppear {
                    draftName = folder.name
                    DispatchQueue.main.async {
                        nameFieldFocused = true
                    }
                }
                .onSubmit {
                    commitRename()
                }
                .onExitCommand {
                    cancelRename()
                }
        } else {
            Text(folder.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(folderForegroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var folderIconView: some View {
        SumiFolderGlyphView(
            presentation: folderGlyphPresentation,
            palette: folderShellPalette
        )
        .frame(
            width: SidebarRowLayout.folderGlyphSize,
            height: SidebarRowLayout.folderGlyphSize,
            alignment: .center
        )
    }

    /// Full-size Zen glyph; horizontal center matches favicon column, layout width matches tab rows (`folderTitleLeading`).
    private var folderHeaderIconSlot: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
            folderIconView
                .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
        }
        .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)
    }

    private var collapsedFolderContent: some View {
        folderBodyContent(
            items: visibleCollapsedProjectionIDs.map(FolderListItem.shortcut),
            reportsGeometry: false,
            reportsFolderChildGeometry: false
        )
    }

    private func folderContent(reportsGeometry: Bool = true) -> some View {
        folderBodyContent(
            items: folderItems,
            reportsGeometry: reportsGeometry,
            reportsFolderChildGeometry: reportsGeometry && folder.isOpen
        )
    }

    private func folderBodyContent(
        items: [FolderListItem],
        reportsGeometry: Bool,
        reportsFolderChildGeometry: Bool
    ) -> some View {
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                switch item {
                case .shortcut(let pinId):
                    if let pin = shortcutPinsInFolder.first(where: { $0.id == pinId }) {
                        folderShortcutView(pin)
                            .sidebarFolderChildDropGeometry(
                                spaceId: space.id,
                                folderId: folder.id,
                                childId: pin.id,
                                index: index,
                                generation: dragState.sidebarGeometryGeneration,
                                isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                            )
                            .transition(folderContentRowTransition)
                    }
                }
            }
        }
        .padding(.leading, Self.folderContentLeadingPadding)
        .padding(.vertical, Self.folderContentVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clear)
        )
        .animation(isInteractive ? Self.zenFolderContentAnimation : nil, value: items)
    }

    private func folderShortcutView(_ pin: ShortcutPin) -> some View {
        return ShortcutSidebarRow(
            pin: pin,
            liveTab: browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id),
            accessibilityID: "folder-shortcut-\(pin.id.uuidString)",
            contextMenuEntries: { toggleEditIcon in
                folderShortcutContextMenuEntries(pin, toggleEditIcon: toggleEditIcon)
            },
            action: { activateShortcutPin(pin) },
            dragSourceZone: .folder(folder.id),
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
    }

    private func folderShortcutContextMenuEntries(
        _ pin: ShortcutPin,
        toggleEditIcon: @escaping () -> Void
    ) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)

        return makeFolderLauncherContextMenuEntries(
            hasRuntimeResetActions: browserManager.tabManager.shortcutHasDrifted(pin, in: windowState),
            showsCloseCurrentPage: presentationState.isSelected,
            callbacks: .init(
                onOpen: { activateShortcutPin(pin) },
                onSplitRight: { openShortcutPinInSplit(pin, side: .right) },
                onSplitLeft: { openShortcutPinInSplit(pin, side: .left) },
                onDuplicate: { duplicateShortcutPin(pin) },
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
                onPinGlobally: nil,
                onCloseCurrentPage: { closeShortcutPinIfActive(pin) }
            )
        )
    }

    private func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        makeFolderHeaderContextMenuEntries(
            hasCustomIcon: folderHasCustomIcon,
            callbacks: .init(
                onRename: startRenaming,
                onChangeIcon: {
                    presentFolderIconPicker(
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onResetIcon: { browserManager.tabManager.updateFolderIcon(folder.id, icon: "") },
                onAddTab: onAddTab,
                onAlphabetize: alphabetizeTabs,
                onDelete: onDelete
            )
        )
    }

    /// Uses `DialogManager` instead of SwiftUI `.sheet` so presenting after `NSMenu` does not trip
    /// `_NSTouchBarFinderObservation` KVO faults on `SumiBrowserWindow` (see `BrowserManager+DialogsUtilities`).
    private func presentFolderIconPicker(
        source: SidebarTransientPresentationSource? = nil
    ) {
        let folderId = folder.id
        let iconSnapshot = folder.icon
        let settings = sumiSettings
        let theme = themeContext
        let manager = browserManager
        DispatchQueue.main.async {
            let picker = FolderIconPickerSheet(
                currentIconValue: iconSnapshot,
                onSelect: { value in
                    DispatchQueue.main.async {
                        manager.tabManager.updateFolderIcon(folderId, icon: value)
                    }
                },
                onReset: {
                    DispatchQueue.main.async {
                        manager.tabManager.updateFolderIcon(folderId, icon: "")
                    }
                },
                onRequestClose: {
                    manager.closeDialog()
                }
            )
            .environment(\.sumiSettings, settings)
            .environment(\.resolvedThemeContext, theme)

            if let source {
                manager.showDialog(
                    picker,
                    source: source
                )
                return
            }

            manager.showDialog(
                picker
            )
        }
    }

    /// Same rationale as `presentFolderIconPicker`: avoid SwiftUI `.sheet` immediately after `NSMenu` (TouchBar KVO).
    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        let manager = browserManager
        let settings = sumiSettings
        let theme = themeContext
        DispatchQueue.main.async {
            let editor = ShortcutLinkEditorSheet(
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

            if let source {
                manager.showDialog(
                    editor,
                    source: source
                )
                return
            }

            manager.showDialog(
                editor
            )
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isFolderHeaderHovered,
            freezesHoverState: freezesHoverState
        )
    }

    private func alphabetizeTabs() {
        withAnimation(Self.zenFolderContentAnimation) {
            browserManager.tabManager.alphabetizeFolderPins(folder.id, in: space.id)
        }
    }

    private var folderContentRowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        )
    }

    private func toggleFolderOpenState() {
        withAnimation(Self.zenFolderContentAnimation) {
            folder.isOpen.toggle()
        }
    }

    // MARK: - Rename Actions

    private func startRenaming() {
        draftName = folder.name
        isRenaming = true
    }

    private func cancelRename() {
        isRenaming = false
        draftName = folder.name
        nameFieldFocused = false
    }

    private func commitRename() {
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != folder.name {
            browserManager.tabManager.renameFolder(folder.id, newName: newName)
        }
        isRenaming = false
        nameFieldFocused = false
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private var folderGlyphPresentation: SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: folder.icon,
            isOpen: folderPreviewIsOpen,
            isDragOpenPreviewed: isFolderDragOpenPreviewed,
            hasActiveProjection: folderHasProjectedContent
        )
    }

    private var folderHasCustomIcon: Bool {
        folderGlyphPresentation.bundledIconName != nil
    }

    private var folderHasProjectedContent: Bool {
        folderProjectionState.hasActiveProjection || folderHasActiveSelection || hasCollapsedProjectionForLayout
    }

    private func scheduleProjectionStateRefresh() {
        let projectedIDs = collapsedProjectedShortcutPins(
            using: folderProjectionState.projectedChildIDs
        ).map(\.id)
        let newHasActiveProjection = folderHasActiveSelection || !projectedIDs.isEmpty
        windowState.scheduleSidebarFolderProjectionUpdate(
            for: folder.id,
            projectedChildIDs: projectedIDs,
            hasActiveProjection: newHasActiveProjection
        )
    }

    private func syncDisplayedCollapsedProjectionIDs(animated: Bool) {
        let targetIDs = targetCollapsedProjectionIDs
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated && isInteractive {
            withAnimation(Self.zenFolderContentAnimation, update)
        } else {
            update()
        }
    }

    private func updateMeasuredExpandedFolderContentHeight(_ height: CGFloat) {
        guard abs(measuredExpandedFolderContentHeight - height) > 0.5 else { return }
        measuredExpandedFolderContentHeight = height
    }

    private func updateMeasuredCollapsedFolderContentHeight(_ height: CGFloat) {
        guard abs(measuredCollapsedFolderContentHeight - height) > 0.5 else { return }
        measuredCollapsedFolderContentHeight = height
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

    private func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserManager.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
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

}

private struct FolderBodyHeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    onChange(geometry.size.height)
                }
                .onChange(of: geometry.size.height) { _, height in
                    onChange(height)
                }
        }
    }
}

struct SumiFolderGlyphPalette {
    let backFill: Color
    let frontFill: Color
    let stroke: Color
    let iconForeground: Color
    let backOverlayTop: Color
    let backOverlayBottom: Color
    let frontOverlayTop: Color
    let frontOverlayBottom: Color
}

enum SumiFolderGlyphShellState: Equatable {
    case closed
    case open
}

struct SumiFolderGlyphPresentationState: Equatable {
    let shellState: SumiFolderGlyphShellState
    let isDragOpenPreviewed: Bool
    let isActive: Bool
    let bundledIconName: String?

    init(iconValue: String?, isOpen: Bool, hasActiveProjection: Bool) {
        self.init(
            iconValue: iconValue,
            isOpen: isOpen,
            isDragOpenPreviewed: false,
            hasActiveProjection: hasActiveProjection
        )
    }

    init(
        iconValue: String?,
        isOpen: Bool,
        isDragOpenPreviewed: Bool,
        hasActiveProjection: Bool
    ) {
        shellState = isOpen ? .open : .closed
        self.isDragOpenPreviewed = isDragOpenPreviewed
        isActive = !isOpen && hasActiveProjection

        switch SumiZenFolderIconCatalog.resolveFolderIcon(iconValue) {
        case .bundled(let name):
            bundledIconName = name
        case .none:
            bundledIconName = nil
        }
    }

    var isOpen: Bool {
        shellState == .open
    }

    var showsDots: Bool {
        isActive
    }

    var showsCustomIcon: Bool {
        bundledIconName != nil && !showsDots
    }
}

struct SumiFolderGlyphView: View {
    private static let shellAnimation = Animation.easeInOut(duration: 0.16)

    let presentation: SumiFolderGlyphPresentationState
    let palette: SumiFolderGlyphPalette

    @State private var renderedShellIsOpen: Bool?

    var body: some View {
        GeometryReader { geometry in
            let shellIsOpen = renderedShellIsOpen ?? presentation.isOpen
            let unitScale = min(
                geometry.size.width / SumiFolderGlyphMetrics.canvasDimension,
                geometry.size.height / SumiFolderGlyphMetrics.canvasDimension
            )
            let canvasSize = SumiFolderGlyphMetrics.canvasDimension * unitScale
            let originX = ((geometry.size.width - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.width * unitScale)
            let originY = ((geometry.size.height - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.height * unitScale)

            ZStack(alignment: .topLeading) {
                canvasLayer(scale: unitScale) {
                    backLayer(scale: unitScale)
                }
                .modifier(backTransform(scale: unitScale, isOpen: shellIsOpen))

                canvasLayer(scale: unitScale) {
                    frontLayer(scale: unitScale)
                }
                .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))

                if presentation.showsCustomIcon {
                    canvasLayer(scale: unitScale) {
                        iconLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }

                if presentation.showsDots {
                    canvasLayer(scale: unitScale) {
                        dotsLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }
            }
            .frame(width: canvasSize, height: canvasSize, alignment: .topLeading)
            .offset(x: originX, y: originY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contrast(1.25)
        .onAppear {
            renderedShellIsOpen = presentation.isOpen
        }
        .onChange(of: presentation.isOpen) { _, isOpen in
            updateRenderedShellState(isOpen)
        }
    }

    private func canvasLayer<Content: View>(
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()
        }
        .frame(
            width: SumiFolderGlyphMetrics.canvasDimension * scale,
            height: SumiFolderGlyphMetrics.canvasDimension * scale,
            alignment: .topLeading
        )
    }

    private func backLayer(scale: CGFloat) -> some View {
        ZStack {
            SumiFolderBackShape()
                .fill(palette.backFill)

            SumiFolderBackShape()
                .fill(
                    LinearGradient(
                        colors: [palette.backOverlayTop, palette.backOverlayBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            SumiFolderBackShape()
                .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
    }

    private func frontLayer(scale: CGFloat) -> some View {
        let size = SumiFolderGlyphMetrics.frontSize.scaled(by: scale)
        let origin = SumiFolderGlyphMetrics.frontOrigin.scaled(by: scale)

        return ZStack {
            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(palette.frontFill)

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [palette.frontOverlayTop, palette.frontOverlayBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: origin.x, y: origin.y)
    }

    private func iconLayer(scale: CGFloat) -> some View {
        let iconSize = SumiFolderGlyphMetrics.iconDimension * scale
        let iconOrigin = SumiFolderGlyphMetrics.iconOrigin.scaled(by: scale)

        return Group {
            if let bundledIconName = presentation.bundledIconName {
                SumiZenBundledIconView(
                    image: SumiZenFolderIconCatalog.bundledFolderImage(named: bundledIconName),
                    size: iconSize,
                    tint: palette.iconForeground.opacity(0.96)
                )
                .frame(width: iconSize, height: iconSize)
                .offset(x: iconOrigin.x, y: iconOrigin.y)
            }
        }
    }

    private func dotsLayer(scale: CGFloat) -> some View {
        let dotSize = SumiFolderGlyphMetrics.dotDiameter * scale

        return ZStack(alignment: .topLeading) {
            ForEach(Array(SumiFolderGlyphMetrics.dotCenters.enumerated()), id: \.offset) { _, center in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .offset(
                        x: (center.x - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale,
                        y: (center.y - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale
                    )
            }
        }
        .foregroundStyle(palette.iconForeground.opacity(0.94))
    }

    private func backTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.backOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func frontTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? -SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.frontOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func updateRenderedShellState(_ isOpen: Bool) {
        let update = {
            renderedShellIsOpen = isOpen
        }

        withAnimation(Self.shellAnimation, update)
    }

    private func elementTransform(
        xDegrees: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        unitScale: CGFloat
    ) -> SumiFolderElementTransform {
        SumiFolderElementTransform(
            xDegrees: xDegrees,
            scale: scale,
            offset: CGSize(width: offset.width * unitScale, height: offset.height * unitScale)
        )
    }
}

private enum SumiFolderGlyphMetrics {
    static let canvasDimension: CGFloat = 27
    static let baseOffset = CGSize(width: -1, height: -1)
    static let openSkewDegrees: CGFloat = 16
    static let openScale: CGFloat = 0.85
    static let backOpenOffset = CGSize(width: -4, height: 2)
    static let frontOpenOffset = CGSize(width: 8, height: 2)
    static let frontOrigin = CGPoint(x: 5.625, y: 9.625)
    static let frontSize = CGSize(width: 16.75, height: 12.75)
    static let frontCornerRadius: CGFloat = 2.375
    static let iconOrigin = CGPoint(x: 8.5, y: 10.5)
    static let iconDimension: CGFloat = 11
    static let dotDiameter: CGFloat = 2.5
    static let dotCenters: [CGPoint] = [
        CGPoint(x: 10, y: 16),
        CGPoint(x: 14, y: 16),
        CGPoint(x: 18, y: 16),
    ]
}

private struct SumiFolderElementTransform: ViewModifier {
    let xDegrees: CGFloat
    let scale: CGFloat
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .modifier(SkewEffect(xDegrees: xDegrees))
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height)
    }
}

private extension CGPoint {
    func scaled(by scale: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}

private struct SumiFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 27
        let sy = rect.height / 27

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }

        var path = Path()
        path.move(to: point(8, 5.625))
        path.addLine(to: point(11.9473, 5.625))
        path.addLine(to: point(13.4316, 6.14551))
        path.addLine(to: point(14.2881, 6.83105))
        path.addLine(to: point(16.5527, 7.625))
        path.addLine(to: point(20, 7.625))
        path.addQuadCurve(to: point(22.375, 10), control: point(22.375, 7.625))
        path.addLine(to: point(22.375, 20))
        path.addQuadCurve(to: point(20, 22.375), control: point(22.375, 22.375))
        path.addLine(to: point(8, 22.375))
        path.addQuadCurve(to: point(5.625, 20), control: point(5.625, 22.375))
        path.addLine(to: point(5.625, 8))
        path.addQuadCurve(to: point(8, 5.625), control: point(5.625, 5.625))
        path.closeSubpath()
        return path
    }
}

private struct SkewEffect: GeometryEffect {
    var xDegrees: CGFloat

    var animatableData: CGFloat {
        get { xDegrees }
        set { xDegrees = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CGAffineTransform.identity
        transform.c = tan(xDegrees * .pi / 180)
        return ProjectionTransform(transform)
    }
}
