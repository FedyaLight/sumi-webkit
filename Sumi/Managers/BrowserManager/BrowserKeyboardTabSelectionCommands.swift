import Foundation
import SumiDomain

/// Active-window tab creation and selection commands for keyboard routing.
@MainActor
final class BrowserKeyboardTabSelectionCommands {
    private let windowTabs: BrowserWindowTabContext
    private let opening: BrowserTabOpeningOwner
    private let newTabCommit: CommandPaletteCommitService
    private let selection: BrowserTabSelectionOwner

    init(
        windowTabs: BrowserWindowTabContext,
        opening: BrowserTabOpeningOwner,
        newTabCommit: CommandPaletteCommitService,
        selection: BrowserTabSelectionOwner
    ) {
        self.windowTabs = windowTabs
        self.opening = opening
        self.newTabCommit = newTabCommit
        self.selection = selection
    }

    @discardableResult
    func openNewTabSurface(in windowState: BrowserWindowState) -> Bool {
        newTabCommit.openNewTabSurface(in: windowState)
    }

    func selectRelativeTab(
        offset: Int,
        in windowState: BrowserWindowState
    ) {
        let currentTabs = windowTabs.tabsForDisplay(in: windowState)
        guard let currentTab = windowTabs.currentTab(for: windowState),
              let currentIndex = currentTabs.firstIndex(where: {
                  $0.id == currentTab.id
              }),
              currentTabs.isEmpty == false else {
            return
        }

        let nextIndex = (
            currentIndex + offset + currentTabs.count
        ) % currentTabs.count
        select(currentTabs[nextIndex], in: windowState)
    }

    func selectTab(at index: Int, in windowState: BrowserWindowState) {
        let currentTabs = windowTabs.tabsForDisplay(in: windowState)
        guard currentTabs.indices.contains(index) else { return }
        select(currentTabs[index], in: windowState)
    }

    func selectLastTab(in windowState: BrowserWindowState) {
        guard let lastTab = windowTabs.tabsForDisplay(in: windowState).last else {
            return
        }
        select(lastTab, in: windowState)
    }

    func duplicateTab(in windowState: BrowserWindowState) {
        guard let tab = windowTabs.currentTab(for: windowState) else {
            return
        }
        opening.duplicateTab(tab, in: windowState)
    }

    private func select(_ tab: Tab, in windowState: BrowserWindowState) {
        _ = selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }
}

/// Contextual pinning commands for the page captured at the shortcut boundary.
/// All mutations delegate to the same transactions as the sidebar menus.
@MainActor
final class BrowserKeyboardPinCommands {
    private let spaces: TabSpaceCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let favorite: FavoriteShortcutPlacementOwner
    private let regularTabs: SidebarRegularTabShortcutCommands
    private let tabCollection: RegularTabCollectionOwner
    private let pinCommands: SidebarPinCommands
    private let splitGroups: SplitGroupStore
    private let splitOrdering: SplitGroupSidebarOrderingService
    private let splitMoves: SidebarDragOperationRouter

    init(
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        favorite: FavoriteShortcutPlacementOwner,
        regularTabs: SidebarRegularTabShortcutCommands,
        tabCollection: RegularTabCollectionOwner,
        pinCommands: SidebarPinCommands,
        splitGroups: SplitGroupStore,
        splitOrdering: SplitGroupSidebarOrderingService,
        splitMoves: SidebarDragOperationRouter
    ) {
        self.spaces = spaces
        self.pins = pins
        self.favorite = favorite
        self.regularTabs = regularTabs
        self.tabCollection = tabCollection
        self.pinCommands = pinCommands
        self.splitGroups = splitGroups
        self.splitOrdering = splitOrdering
        self.splitMoves = splitMoves
    }

    func canPinCurrentTab(in context: BrowserShortcutContext) -> Bool {
        guard let target = regularTarget(in: context),
              let spaceID = context.windowState.currentSpaceId,
              spaces.contains(spaceId: spaceID) else {
            return false
        }
        let urls: [URL]
        if let group = regularSplitGroup(containing: target.tab) {
            let tabs = group.memberIDs.compactMap(regularTab(for:))
            guard tabs.count == group.memberIDs.count else { return false }
            urls = tabs.map(\.url)
        } else {
            urls = [target.url]
        }
        let existingURLs = Set(
            pins.spacePinnedPins(for: spaceID).map(\.launchURL)
        )
        return Set(urls).count == urls.count
            && urls.allSatisfy { existingURLs.contains($0) == false }
    }

    @discardableResult
    func pinCurrentTab(in context: BrowserShortcutContext) -> Bool {
        guard canPinCurrentTab(in: context),
              let tab = context.page?.tab,
              let spaceID = context.windowState.currentSpaceId else {
            return false
        }
        if let group = regularSplitGroup(containing: tab) {
            return moveSplitGroup(
                group,
                from: .spaceRegular(spaceID),
                to: .spacePinned(spaceID),
                at: splitOrdering.topLevelItems(for: spaceID).count,
                in: context
            )
        }
        regularTabs.pinTabToSpace(tab, spaceID: spaceID)
        return true
    }

    func canUnpinCurrentTab(in context: BrowserShortcutContext) -> Bool {
        guard context.windowState.isIncognito == false,
              let pin = currentPin(in: context),
              pin.role == .spacePinned,
              let spaceID = context.windowState.currentSpaceId,
              pin.spaceId == spaceID,
              spaces.contains(spaceId: spaceID) else {
            return false
        }
        if let group = currentSplitGroup(in: context) {
            guard case .shortcutSidebar(let groupSpaceID, _, _, _) =
                    group.container else {
                return false
            }
            return groupSpaceID == spaceID
        }
        return true
    }

    @discardableResult
    func unpinCurrentTab(in context: BrowserShortcutContext) -> Bool {
        guard canUnpinCurrentTab(in: context),
              let pin = currentPin(in: context),
              let spaceID = context.windowState.currentSpaceId else {
            return false
        }
        let destinationIndex = tabCollection.tabs(in: spaceID).count
        if let group = currentSplitGroup(in: context),
           let source = dragContainer(for: group.container) {
            return moveSplitGroup(
                group,
                from: source,
                to: .spaceRegular(spaceID),
                at: destinationIndex,
                in: context
            )
        }
        let source = pin.folderId.map(TabDragManager.DragContainer.folder)
            ?? .spacePinned(spaceID)
        return splitMoves.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: SidebarDragScope(
                    windowId: context.windowState.id,
                    spaceId: spaceID,
                    profileId: context.windowState.currentProfileId,
                    sourceContainer: source,
                    sourceItemId: pin.id,
                    sourceItemKind: .tab
                ),
                fromContainer: source,
                toContainer: .spaceRegular(spaceID),
                toIndex: destinationIndex
            )
        )
    }

    func canAddCurrentToFavorite(
        in context: BrowserShortcutContext
    ) -> Bool {
        guard context.windowState.isIncognito == false,
              let page = context.page,
              page.source == .selectedTab,
              page.tab.representsSumiNativeSurface == false else {
            return false
        }
        if let pin = currentPin(in: context), pin.role == .favorite {
            return false
        }
        if let group = currentSplitGroup(in: context) {
            let urls = group.memberIDs.compactMap(url(for:))
            guard urls.count == group.memberIDs.count else { return false }
            return favorite.canAddURLs(
                urls,
                using: targetContext(in: context)
            )
        }
        return favorite.canAddURL(
            page.url,
            using: targetContext(in: context)
        )
    }

    @discardableResult
    func addCurrentToFavorite(
        in context: BrowserShortcutContext
    ) -> Bool {
        guard canAddCurrentToFavorite(in: context),
              let page = context.page,
              let spaceID = context.windowState.currentSpaceId,
              let space = spaces.space(with: spaceID) else {
            return false
        }
        if let group = currentSplitGroup(in: context) {
            guard let source = dragContainer(for: group.container) else {
                return false
            }
            return moveSplitGroup(
                group,
                from: source,
                to: .favorite,
                at: splitOrdering.favoriteItems(
                    for: context.windowState.currentProfileId
                ).count,
                in: context
            )
        }
        if let pin = currentPin(in: context) {
            return pinCommands.copyToFavorite(
                pin,
                title: pin.resolvedDisplayTitle(liveTab: page.tab),
                context: targetContext(in: context)
            ) != nil
        }
        regularTabs.addTabToFavorite(
            page.tab,
            in: space,
            windowState: context.windowState
        )
        return true
    }

    func canRemoveCurrentFromFavorite(
        in context: BrowserShortcutContext
    ) -> Bool {
        guard context.windowState.isIncognito == false,
              context.windowState.currentSpaceId.flatMap(spaces.space(with:)) != nil,
              let pin = currentPin(in: context) else {
            return false
        }
        guard pin.role == .favorite else { return false }
        if let group = currentSplitGroup(in: context) {
            guard case .favoriteSidebar = group.container else {
                return false
            }
        }
        return true
    }

    @discardableResult
    func removeCurrentFromFavorite(
        in context: BrowserShortcutContext
    ) -> Bool {
        guard canRemoveCurrentFromFavorite(in: context),
              let pin = currentPin(in: context),
              let spaceID = context.windowState.currentSpaceId else {
            return false
        }
        if let group = currentSplitGroup(in: context) {
            return moveSplitGroup(
                group,
                from: .favorite,
                to: .spacePinned(spaceID),
                at: splitOrdering.topLevelItems(for: spaceID).count,
                in: context
            )
        }
        return pinCommands.move(pin, toSpace: spaceID)
    }

    private func regularTarget(
        in context: BrowserShortcutContext
    ) -> ActivePageResolution? {
        guard context.windowState.isIncognito == false,
              let page = context.page,
              page.source == .selectedTab,
              page.tab.representsSumiNativeSurface == false,
              page.tab.isPinned == false,
              page.tab.isSpacePinned == false,
              currentPin(in: context) == nil else {
            return nil
        }
        return page
    }

    private func currentPin(
        in context: BrowserShortcutContext
    ) -> ShortcutPin? {
        let pinID = context.windowState.currentShortcutPinId
            ?? context.page?.tab.shortcutPinId
        return pinID.flatMap(pins.shortcutPin(by:))
    }

    private func currentSplitGroup(
        in context: BrowserShortcutContext
    ) -> SplitGroup? {
        guard let tab = context.page?.tab else { return nil }
        if let pin = currentPin(in: context) {
            return splitGroups.group(containing: .shortcutPin(pin.id))
        }
        return regularSplitGroup(containing: tab)
    }

    private func regularSplitGroup(containing tab: Tab) -> SplitGroup? {
        splitGroups.group(containing: .regularTab(tab.id))
    }

    private func regularTab(for memberID: SplitMemberID) -> Tab? {
        guard case .regularTab(let tabID) = memberID else { return nil }
        return tabCollection.tab(for: tabID)
    }

    private func url(for memberID: SplitMemberID) -> URL? {
        switch memberID {
        case .regularTab:
            regularTab(for: memberID)?.url
        case .shortcutPin(let pinID):
            pins.shortcutPin(by: pinID)?.launchURL
        }
    }

    private func dragContainer(
        for container: SplitGroupContainer
    ) -> TabDragManager.DragContainer? {
        switch container {
        case .regularTabs(let spaceID):
            spaceID.map(TabDragManager.DragContainer.spaceRegular)
        case .shortcutSidebar(let spaceID, _, let folderID, _):
            folderID.map(TabDragManager.DragContainer.folder)
                ?? .spacePinned(spaceID)
        case .favoriteSidebar:
            .favorite
        }
    }

    private func moveSplitGroup(
        _ group: SplitGroup,
        from source: TabDragManager.DragContainer,
        to destination: TabDragManager.DragContainer,
        at index: Int,
        in context: BrowserShortcutContext
    ) -> Bool {
        guard let spaceID = context.windowState.currentSpaceId else {
            return false
        }
        return splitMoves.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: SidebarDragScope(
                    windowId: context.windowState.id,
                    spaceId: spaceID,
                    profileId: context.windowState.currentProfileId,
                    sourceContainer: source,
                    sourceItemId: group.id,
                    sourceItemKind: .splitGroup
                ),
                fromContainer: source,
                toContainer: destination,
                toIndex: index
            )
        )
    }

    private func targetContext(
        in context: BrowserShortcutContext
    ) -> FavoriteShortcutPlacementOwner.TargetContext {
        FavoriteShortcutPlacementOwner.TargetContext(
            windowState: context.windowState,
            spaceId: context.windowState.currentSpaceId
        )
    }
}
