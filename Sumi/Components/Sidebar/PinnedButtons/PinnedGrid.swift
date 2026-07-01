//
//      PinnedGrid.swift
//      Sumi
//
//
import SwiftUI

enum PinnedGridContextResolver {
    static let unresolvedGeometrySpaceId: UUID = {
        guard let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            preconditionFailure("Invalid unresolved pinned-grid geometry space id")
        }
        return id
    }()

    static func contextMenuSpaceId(
        explicitSpaceId: UUID?,
        windowSpaceId: UUID?
    ) -> UUID? {
        explicitSpaceId ?? windowSpaceId
    }

    static func geometrySpaceId(
        explicitSpaceId: UUID?,
        windowSpaceId: UUID?
    ) -> UUID {
        explicitSpaceId ?? windowSpaceId ?? unresolvedGeometrySpaceId
    }
}

struct PinnedGrid: View {
    private static let collapsedRevealHeight: CGFloat = 6

    let width: CGFloat
    let browserContext: SidebarBrowserContext
    let spaceId: UUID?
    let profileId: UUID?
    let animateLayout: Bool
    let reportsGeometry: Bool
    let isAppKitInteractionEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    init(
        width: CGFloat,
        browserContext: SidebarBrowserContext,
        spaceId: UUID? = nil,
        profileId: UUID? = nil,
        animateLayout: Bool = true,
        reportsGeometry: Bool = true,
        isAppKitInteractionEnabled: Bool = true
    ) {
        self.width = width
        self.browserContext = browserContext
        self.spaceId = spaceId
        self.profileId = profileId
        self.animateLayout = animateLayout
        self.reportsGeometry = reportsGeometry
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
    }

    var body: some View {
        let _ = browserContext.tabStructuralRevision()
        let shouldReduceMotion = reduceMotion || sumiSettings.shouldReduceChromeMotion

        let pinnedTabsConfiguration: PinnedTabsConfiguration = .large
        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserContext.currentProfile()?.id
        let items: [ShortcutPin] = effectiveProfileId != nil
            ? browserContext.tabManager.essentialPins(for: effectiveProfileId)
            : []
        let gridProjection = SidebarEssentialsGridProjection(
            width: width,
            configuration: pinnedTabsConfiguration
        )
        let projectedLayout = SidebarEssentialsProjectionPolicy.make(
            items: items,
            width: width,
            configuration: pinnedTabsConfiguration,
            dragState: dragState
        )
        let rawPreviewState = dragState.essentialsPreviewState(for: geometrySpaceId)
        let reportsDetailedGeometry = reportsGeometry
            && dragState.shouldCollectDetailedGeometry(
                spaceId: geometrySpaceId,
                profileId: effectiveProfileId
            )
        let shouldAnimateDropLayout = animateLayout
            && (windowRegistry.activeWindow?.id == windowState.id)
            && !browserContext.isTransitioningProfile()
            && !shouldReduceMotion
            && dragState.shouldAnimateDropLayout
        let shouldAnimateContentLayout = animateLayout
            && (windowRegistry.activeWindow?.id == windowState.id)
            && !browserContext.isTransitioningProfile()
            && !shouldReduceMotion

        let isHoveringThisEssentials: Bool = {
            guard dragState.isDropProjectionActive,
                  case .essentials = dragState.projectionHoveredSlot else {
                return false
            }
            return true
        }()
        let showsRevealGap = items.isEmpty
            && isHoveringThisEssentials
            && projectedLayout.canAcceptDrop
        let revealTileSize = projectedLayout.rows.first?.tileSize ?? projectedLayout.tileSize
        let revealHeight = showsRevealGap
            ? revealTileSize.height
            : Self.collapsedRevealHeight
        let visibleRowCount = max(projectedLayout.visibleRowCount, items.isEmpty ? 0 : 1)
        let maxDropRowCount = items.isEmpty
            ? 1
            : SidebarEssentialsProjectionPolicy.neededRowCountAfterDrop(
                itemIDs: items.map(\.id),
                visibleItemCount: projectedLayout.visibleItemCount,
                layoutItemCount: projectedLayout.projectedItemCount,
                columnCount: projectedLayout.columnCount,
                canAcceptDrop: projectedLayout.canAcceptDrop,
                dragState: dragState
            )
        let dropFrame = items.isEmpty
            ? CGRect(x: 0, y: 0, width: width, height: revealHeight)
            : gridProjection.resolvedDropFrame(
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                tileSize: projectedLayout.tileSize,
                visibleHeight: gridProjection.projectedContentHeight(for: projectedLayout)
            )
        let previewState = rawPreviewState.flatMap {
            gridProjection.resolvedPreviewState(
                $0,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount
            )
        }
        let displayRows = gridProjection.resolvedDisplayRows(
            for: projectedLayout,
            previewState: previewState,
            maxDropRowCount: maxDropRowCount
        )
        let displayLayoutSignature = displayRows.flatMap { $0.layoutSignature }
        let dropSlotFrames = gridProjection.resolvedDropSlotFrames(
            for: projectedLayout,
            revealTileSize: revealTileSize,
            maxDropRowCount: maxDropRowCount
        )

        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                VStack(spacing: 0) {
                    if showsRevealGap {
                        Color.clear
                            .frame(width: revealTileSize.width, height: revealTileSize.height)
                    } else {
                        Color.clear
                            .frame(height: Self.collapsedRevealHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: revealHeight, alignment: .top)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: showsRevealGap)
            } else {
                LazyVStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                    ForEach(displayRows, id: \.stableID) { row in
                        HStack(spacing: pinnedTabsConfiguration.gridSpacing) {
                            ForEach(row.cells, id: \.stableID) { cell in
                                switch cell {
                                case .pin(let pin):
                                    renderTile(
                                        for: pin,
                                        configuration: pinnedTabsConfiguration,
                                        tileSize: row.tileSize
                                    )
                                case .gap:
                                    renderDropGap(
                                        tileSize: row.tileSize
                                    )
                                case .spacer:
                                    Color.clear
                                        .frame(width: row.tileSize.width, height: row.tileSize.height)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: items.map(\.id))
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.visualColumnSignature)
                .animation(shouldAnimateContentLayout ? SidebarDropMotion.contentLayout : nil, value: projectedLayout.projectedItemCount)
                .animation(shouldAnimateDropLayout ? .easeInOut(duration: 0.18) : nil, value: previewState?.expandedDropRowCount)
                .animation(shouldAnimateDropLayout ? SidebarDropMotion.gap : nil, value: displayLayoutSignature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: items.isEmpty ? revealHeight : 0, alignment: .top)
        .sidebarSectionGeometry(
            for: .essentials,
            spaceId: geometrySpaceId,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: reportsGeometry
        )
        .sidebarEssentialsLayoutGeometry(
            spaceId: geometrySpaceId,
            profileId: effectiveProfileId,
            itemCount: projectedLayout.projectedItemCount,
            columnCount: projectedLayout.columnCount,
            firstSyntheticRowSlot: max(visibleRowCount, 1) * max(projectedLayout.capacityColumnCount, 1),
            rowCount: max(displayRows.count, 1),
            visibleItemCount: projectedLayout.visibleItemCount,
            visibleRowCount: visibleRowCount,
            maxDropRowCount: maxDropRowCount,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemSize: projectedLayout.tileSize,
            gridSpacing: pinnedTabsConfiguration.gridSpacing,
            canAcceptDrop: projectedLayout.canAcceptDrop,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: reportsDetailedGeometry
        )
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .allowsHitTesting(!browserContext.isTransitioningProfile())
    }

    @ViewBuilder
    private func renderTile(
        for pin: ShortcutPin,
        configuration: PinnedTabsConfiguration,
        tileSize: CGSize
    ) -> some View {
        if let placeholderGroup = splitPlaceholderGroup(for: pin) {
            PinnedSplitPlaceholderTile(
                pin: pin,
                faviconPartition: browserContext.tabManager.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                isSelected: isSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "essential-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                onActivate: {
                    browserContext.commands.focusSplitGroup(placeholderGroup, windowState)
                }
            )
            .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .transition(
                reduceMotion
                    ? .identity
                    : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
            )
        } else {
            let presentationState = pinPresentationState(pin)
            let liveTab = browserContext.tabManager.shortcutLiveTab(
                for: pin.id,
                in: windowState.id
            )
            let contextMenuActions = essentialContextMenuActions(for: pin)

            PinnedTile(
                pin: pin,
                faviconPartition: browserContext.tabManager.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                presentationState: presentationState,
                liveTab: liveTab,
                essentialRuntimeState: essentialRuntimeState(pin),
                accessibilityID: "essential-shortcut-\(pin.id.uuidString)",
                onActivate: { activate(pin) },
                onUnload: { unload(pin) },
                contextMenuActions: contextMenuActions,
                dragPinnedConfiguration: configuration,
                dragIsEnabled: !browserContext.isTransitioningProfile() && isAppKitInteractionEnabled,
                isAppKitInteractionEnabled: isAppKitInteractionEnabled
            )
            .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .transition(
                reduceMotion
                    ? .identity
                    : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
            )
        }
    }

    @ViewBuilder
    private func renderDropGap(
        tileSize: CGSize
    ) -> some View {
        Color.clear
        .frame(width: tileSize.width, height: tileSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @EnvironmentObject private var dragState: SidebarDragState

    private func pinPresentationState(_ pin: ShortcutPin) -> ShortcutPresentationState {
        browserContext.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func essentialRuntimeState(_ pin: ShortcutPin) -> SumiEssentialRuntimeState? {
        browserContext.tabManager.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitManager: browserContext.splitManager
        )
    }

    private func splitPlaceholderGroup(for pin: ShortcutPin) -> SplitGroup? {
        browserContext.tabManager.splitGroup(containingPinId: pin.id)
    }

    private func isSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        guard let currentTabId = windowState.currentTabId else {
            return false
        }
        return group.contains(currentTabId)
            || group.member(forPinId: pin.id)?.tabId == currentTabId
    }

    private func activate(_ pin: ShortcutPin) {
        let tab = browserContext.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: windowState.currentSpaceId
        )
        browserContext.commands.requestUserTabActivation(
            tab,
            windowState
        )
    }

    private func unload(_ pin: ShortcutPin) {
        if let current = browserContext.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserContext.commands.closeTab(current, windowState)
            return
        }

        browserContext.tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    private func duplicateAsRegularTab(_ pin: ShortcutPin) {
        let _ = browserContext.commands.openForegroundTab(
            pin.launchURL.absoluteString,
            windowState,
            windowState.currentSpaceId
        )
    }

    private func essentialContextMenuActions(for pin: ShortcutPin) -> EssentialTileContextMenuActions {
        EssentialTileContextMenuActions(makeEntries: {
            let savedURLDriftActions: SidebarSavedURLDriftActions? =
                browserContext.tabManager.shortcutHasDrifted(pin, in: windowState)
                    ? .init(
                        onBackToSavedURL: { resetShortcutPin(pin) },
                        onUseCurrentPageAsSavedURL: { _ = browserContext.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                    )
                    : nil
            let unloadAction: (() -> Void)? = pinPresentationState(pin).isOpenLive
                ? { unload(pin) }
                : nil
            let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
                moveEssential(pin, toSpace: targetSpaceId)
            }
            let spaceChoices = essentialSpaceChoices

            return makeSidebarTabContextMenuEntries(
                role: .essential,
                actions: .init(
                    duplicate: { duplicateAsRegularTab(pin) },
                    copyLink: { copyLink(pin.launchURL) },
                    share: {
                        presentSharePicker(
                            for: pin.launchURL,
                            source: windowState.resolveSidebarPresentationSource()
                        )
                    },
                    edit: { presentShortcutLinkEditor(for: pin) },
                    folderTarget: .init(
                        choices: essentialFolderChoices,
                        onSelect: { folderId in moveEssential(pin, toFolder: folderId) }
                    ),
                    moveToSpace: .init(
                        choices: spaceChoices,
                        onSelect: moveToSpaceAction
                    ),
                    profileTarget: .init(
                        choices: profileChoices(for: pin),
                        onSelect: { profileId in
                            browserContext.tabManager.assign(
                                shortcutPin: pin,
                                toExecutionProfile: profileId
                            )
                        }
                    ),
                    savedURLDrift: savedURLDriftActions,
                    unload: unloadAction,
                    deleteSavedTab: { confirmDeleteEssential(pin) }
                )
            )
        })
    }

    private var contextMenuSpace: Space? {
        let targetSpaceId = PinnedGridContextResolver.contextMenuSpaceId(
            explicitSpaceId: spaceId,
            windowSpaceId: windowState.currentSpaceId
        )
        guard let targetSpaceId else { return nil }
        return browserContext.tabManager.spaces.first { $0.id == targetSpaceId }
    }

    private var essentialFolderChoices: [SidebarContextMenuChoice] {
        guard let contextMenuSpace else { return [] }
        return makeSidebarContextMenuFolderChoices(
            folders: browserContext.tabManager.folders(for: contextMenuSpace.id)
        )
    }

    private var essentialSpaceChoices: [SidebarContextMenuChoice] {
        makeSidebarContextMenuSpaceChoices(
            spaces: browserContext.tabManager.spaces
        )
    }

    private func profileChoices(for pin: ShortcutPin) -> [SidebarContextMenuChoice] {
        makeSidebarContextMenuProfileChoices(
            profiles: browserContext.profileManager.profiles,
            selectedProfileId: browserContext.tabManager.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: contextMenuSpace?.id
            )
        )
    }

    private func moveEssential(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserContext.tabManager.folder(by: folderId) else { return }
        let targetIndex = browserContext.tabManager.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutateContentLayout {
            let _ = browserContext.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                index: targetIndex
            )
        }
    }

    private func moveEssential(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserContext.tabManager.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutateContentLayout {
            let _ = browserContext.tabManager.moveShortcutPin(
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
        let _ = browserContext.tabManager.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    private func removeFromEssentials(_ pin: ShortcutPin) {
        mutateContentLayout {
            browserContext.tabManager.removeFromEssentials(pin)
        }
    }

    private func confirmDeleteEssential(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .essential,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.window,
            onDelete: { removeFromEssentials(pin) }
        )
    }

    private func presentShortcutLinkEditor(for pin: ShortcutPin) {
        browserContext.presentationActions.showShortcutEditor(
            pin,
            windowState,
            themeContext,
            windowState.resolveSidebarPresentationSource()
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
            browserContext.presentationActions.presentSharingServicePicker([url], source)
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

    private func mutateContentLayout(_ update: () -> Void) {
        guard animateLayout,
              windowRegistry.activeWindow?.id == windowState.id,
              !browserContext.isTransitioningProfile(),
              !reduceMotion,
              !dragState.isCompletingDrop else {
            update()
            return
        }

        withAnimation(SidebarDropMotion.contentLayout, update)
    }

    private var geometrySpaceId: UUID {
        PinnedGridContextResolver.geometrySpaceId(
            explicitSpaceId: spaceId,
            windowSpaceId: windowState.currentSpaceId
        )
    }
}

private struct PinnedSplitPlaceholderTile: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let isSelected: Bool
    let accessibilityID: String
    let isAppKitInteractionEnabled: Bool
    let onActivate: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isTileHovered = false
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        let configuration = PinnedTabsConfiguration.large
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFaviconImage(partition: faviconPartition)
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? pin.storedChromeTemplateSystemImageName(for: faviconPartition)
            : nil

        PinnedTileVisual(
            tabIcon: resolvedFavicon,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: isSelected ? .visuallySelected : .liveBackgrounded,
            isHovered: displayIsHovered,
            showsSplitGroupOutline: true,
            faviconOpacity: 1,
            configuration: configuration,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition
        )
        .frame(maxWidth: .infinity)
        .frame(height: configuration.height)
        .frame(minWidth: configuration.minWidth)
        .contentShape(
            RoundedRectangle(
                cornerRadius: sumiSettings.resolvedCornerRadius(configuration.cornerRadius),
                style: .continuous
            )
        )
        .onTapGesture(perform: onActivate)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "split placeholder")
        .sidebarDDGHover($isTileHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isAppKitInteractionEnabled,
            sourceID: accessibilityID,
            action: onActivate
        )
        .shadow(
            color: isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: isSelected ? 2 : 0,
            y: isSelected ? 1 : 0
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            storedFaviconLoader.invalidateIfNeeded(for: notification, launchURL: pin.launchURL)
        }
    }

    private var displayIsHovered: Bool {
        SidebarHoverChrome.displayHover(
            isTileHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(for: pin.launchURL)
    }

    private var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    @MainActor
    private func loadStoredFavicon() async {
        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }
}

private extension ShortcutPin {
    var glyphText: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) else {
            return nil
        }
        return iconAsset
    }

    var chromeTemplateSystemImageName: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) == false else {
            return nil
        }
        return SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset)
    }
}

private struct EssentialTileContextMenuActions {
    let makeEntries: () -> [SidebarContextMenuEntry]

    func entries() -> [SidebarContextMenuEntry] {
        makeEntries()
    }
}

private struct PinnedTile: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let presentationState: ShortcutPresentationState
    let liveTab: Tab?
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: EssentialTileContextMenuActions
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        Group {
            if let liveTab {
                LivePinnedTileContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    liveTab: liveTab,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onUnload: onUnload,
                    contextMenuActions: contextMenuActions,
                    dragPinnedConfiguration: dragPinnedConfiguration,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            } else {
                StoredPinnedTileContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onUnload: onUnload,
                    contextMenuActions: contextMenuActions,
                    dragPinnedConfiguration: dragPinnedConfiguration,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LivePinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    @ObservedObject var liveTab: Tab
    let presentationState: ShortcutPresentationState
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: EssentialTileContextMenuActions
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        let resolvedTitle = pin.resolvedDisplayTitle(liveTab: liveTab)
        let glyphText = pin.glyphText
        let launcherFavicon = currentCachedStoredFavicon
        let resolvedFavicon = launcherFavicon ?? liveTab.favicon
        let chromeTemplateSystemImageName = pin.chromeTemplateSystemImageName
            ?? Self.chromeTemplateSystemImageName(
                for: liveTab,
                hasLauncherFavicon: launcherFavicon != nil
            )
        PinnedTabView(
            tabIcon: resolvedFavicon,
            glyphText: glyphText,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: liveTab,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: resolvedFavicon,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                pinnedConfiguration: dragPinnedConfiguration,
                exclusionZones: dragExclusionZones,
                onActivate: onActivate,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            storedFaviconLoader.invalidateIfNeeded(for: notification, launchURL: pin.launchURL)
        }
    }

    private static func chromeTemplateSystemImageName(
        for liveTab: Tab,
        hasLauncherFavicon: Bool
    ) -> String? {
        if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if hasLauncherFavicon {
            return nil
        }
        if liveTab.faviconIsTemplateGlobePlaceholder {
            return SumiPersistentGlyph.launcherSystemImageFallback
        }
        return nil
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] {
        var zones: [SidebarDragSourceExclusionZone] = []

        if liveTab.audioState.showsTabAudioButton {
            zones.append(.topLeadingSquare(size: 22, inset: 6))
        }

        return zones
    }

    private var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(for: pin.launchURL)
    }

    private var currentCachedStoredFavicon: Image? {
        currentLoadedStoredFavicon ?? ShortcutPin.cachedLaunchFavicon(
            for: pin.launchURL,
            partition: faviconPartition
        )
    }

    private var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isEnabled: pin.iconAsset == nil,
            disabledID: pin.id.uuidString
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        guard pin.iconAsset == nil else { return }

        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }
}

private struct StoredPinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let presentationState: ShortcutPresentationState
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: EssentialTileContextMenuActions
    let dragPinnedConfiguration: PinnedTabsConfiguration
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        let resolvedTitle = pin.preferredDisplayTitle
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFaviconImage(partition: faviconPartition)
        let glyphText = pin.glyphText
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? (pin.chromeTemplateSystemImageName ?? pin.storedChromeTemplateSystemImageName(for: faviconPartition))
            : nil
        PinnedTabView(
            tabIcon: resolvedFavicon,
            glyphText: glyphText,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: nil,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: resolvedFavicon,
                chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                pinnedConfiguration: dragPinnedConfiguration,
                exclusionZones: dragExclusionZones,
                onActivate: onActivate,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            storedFaviconLoader.invalidateIfNeeded(for: notification, launchURL: pin.launchURL)
        }
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] { [] }

    private var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(for: pin.launchURL)
    }

    private var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }
}

@MainActor
func makePinnedTileDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    previewIcon: Image?,
    chromeTemplateSystemImageName: String? = nil,
    previewPresentationState: ShortcutPresentationState? = nil,
    pinnedConfiguration: PinnedTabsConfiguration,
    exclusionZones: [SidebarDragSourceExclusionZone],
    onActivate: (() -> Void)? = nil,
    isEnabled: Bool = true
) -> SidebarDragSourceConfiguration {
    SidebarDragSourceConfiguration(
        item: SumiDragItem(
            tabId: pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: .essentials,
        previewKind: .essentialsTile,
        previewIcon: previewIcon,
        chromeTemplateSystemImageName: chromeTemplateSystemImageName,
        pinnedConfig: pinnedConfiguration,
        previewPresentationState: previewPresentationState,
        exclusionZones: exclusionZones,
        onActivate: onActivate,
        isEnabled: isEnabled
    )
}

// MARK: - Preference Keys
// no-op
