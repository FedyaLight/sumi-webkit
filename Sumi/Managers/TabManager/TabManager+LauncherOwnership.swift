import Foundation

@MainActor
struct ShortcutPinSelectionCleanupResult {
    private(set) var didClearCurrentSelection = false
    private(set) var windowStatesNeedingPersistence: [BrowserWindowState] = []

    mutating func recordCurrentSelectionCleared(in windowState: BrowserWindowState) {
        didClearCurrentSelection = true
        recordWindowSessionChange(in: windowState)
    }

    mutating func recordWindowSessionChange(in windowState: BrowserWindowState) {
        guard !windowStatesNeedingPersistence.contains(where: { $0.id == windowState.id }) else {
            return
        }
        windowStatesNeedingPersistence.append(windowState)
    }

    mutating func merge(_ other: ShortcutPinSelectionCleanupResult) {
        didClearCurrentSelection = didClearCurrentSelection || other.didClearCurrentSelection
        for windowState in other.windowStatesNeedingPersistence {
            recordWindowSessionChange(in: windowState)
        }
    }
}

@MainActor
extension TabManager {
    // MARK: - Pinned tabs (global)

    func pinTab(_ tab: Tab, context: EssentialsTargetContext? = nil) {
        withStructuralUpdateTransaction {
            guard let insertion = resolveEssentialsInsertion(
                using: EssentialsInsertionContext(target: context)
            ) else { return }
            if essentialPins(for: insertion.profileId).contains(where: { $0.launchURL == tab.url }) { return }

            let pin = makeShortcutPin(
                from: tab,
                role: .essential,
                profileId: insertion.profileId,
                index: insertion.index
            )
            guard let insertedPin = insertShortcutPin(pin, at: insertion.index) else { return }
            logEssentialsTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )

            if !convertDisplayedTabToShortcutLiveInstances(
                tab,
                pin: insertedPin,
                preferredWindowId: context?.windowState?.id
            ) {
                removeTab(tab.id)
            }
            scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func copyShortcutPinToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: EssentialsTargetContext? = nil
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            guard let insertion = resolveEssentialsInsertion(
                using: EssentialsInsertionContext(target: context)
            ) else { return nil }
            if essentialPins(for: insertion.profileId).contains(where: { $0.launchURL == pin.launchURL }) {
                return nil
            }

            let copiedPin = ShortcutPin(
                id: UUID(),
                role: .essential,
                profileId: insertion.profileId,
                executionProfileId: copiedShortcutExecutionProfileId(
                    for: pin,
                    targetProfileId: insertion.profileId,
                    context: context
                ),
                spaceId: nil,
                index: insertion.index,
                folderId: nil,
                launchURL: pin.launchURL,
                title: title,
                iconAsset: pin.iconAsset
            )
            guard let insertedPin = insertShortcutPin(copiedPin, at: insertion.index) else {
                return nil
            }

            logEssentialsTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )
            scheduleStructuralPersistence()
            return insertedPin
        }
    }

    private func copiedShortcutExecutionProfileId(
        for pin: ShortcutPin,
        targetProfileId: UUID,
        context: EssentialsTargetContext?
    ) -> UUID? {
        let currentSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        let executionProfileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
        return executionProfileId == targetProfileId ? nil : executionProfileId
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        withStructuralUpdateTransaction {
            if shortcutPin(by: pin.id) != nil {
                runtimeContext?.captureDeletedShortcutLauncher(pin)
            }

            if pin.role == .essential, let profileId = pin.profileId {
                var arr = pinnedByProfile[profileId] ?? []
                arr.removeAll { $0.id == pin.id }
                setPinnedTabs(reindexed(arr), for: profileId)
            } else if pin.role == .spacePinned, let spaceId = pin.spaceId {
                if pin.folderId == nil {
                    let items = topLevelSpacePinnedItems(for: spaceId).filter { item in
                        if case .shortcut(let existingPin) = item { return existingPin.id != pin.id }
                        return true
                    }
                    applyTopLevelSpacePinnedOrder(items, for: spaceId)
                } else {
                    withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { arr in
                        arr.removeAll { $0.id == pin.id }
                    }
                }
            }

            let liveWindowIds = transientShortcutTabsByWindow.compactMap { windowId, tabsByPin in
                tabsByPin[pin.id] == nil ? nil : windowId
            }
            var cleanupResult = ShortcutPinSelectionCleanupResult()
            for windowId in liveWindowIds {
                let windowState = runtimeContext?.windowState(for: windowId)
                if deactivateShortcutLiveTab(pinId: pin.id, in: windowId),
                   let windowState {
                    cleanupResult.recordCurrentSelectionCleared(in: windowState)
                }
            }
            cleanupResult.merge(clearDeletedShortcutPinSelectionReferences(pin.id))
            if cleanupResult.didClearCurrentSelection {
                runtimeContext?.validateWindowStates()
            }
            persistWindowSessionsForShortcutSelectionCleanup(cleanupResult)
            scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func updateShortcutPin(
        _ pin: ShortcutPin,
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        executionProfileId: UUID?? = nil
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            let updatedPin = pin.updated(
                title: title,
                launchURL: launchURL,
                iconAsset: iconAsset,
                executionProfileId: executionProfileId
            )

            switch pin.role {
            case .essential:
                guard let profileId = pin.profileId,
                      var pins = pinnedByProfile[profileId],
                      let index = pins.firstIndex(where: { $0.id == pin.id }) else {
                    return nil
                }

                pins[index] = updatedPin.refreshed(index: pin.index)
                setPinnedTabs(reindexed(pins), for: profileId)
                if let inserted = pinnedByProfile[profileId]?.first(where: { $0.id == pin.id }) {
                    updateTransientShortcutBindings(for: inserted)
                    scheduleStructuralPersistence()
                    return inserted
                }
            case .spacePinned:
                guard let spaceId = pin.spaceId else { return nil }
                if pin.folderId == nil {
                    let items = topLevelSpacePinnedItems(for: spaceId).map { item -> SpacePinnedTopLevelItem in
                        guard case .shortcut(let existingPin) = item, existingPin.id == pin.id else {
                            return item
                        }
                        return .shortcut(updatedPin.refreshed(index: pin.index))
                    }
                    applyTopLevelSpacePinnedOrder(items, for: spaceId)
                } else {
                    withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { pins in
                        if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                            pins[index] = updatedPin.refreshed(index: pin.index)
                        }
                    }
                }

                if let inserted = shortcutPin(by: pin.id) {
                    updateTransientShortcutBindings(for: inserted)
                    scheduleStructuralPersistence()
                    return inserted
                }
            }

            return nil
        }
    }

    @discardableResult
    func replaceShortcutPinURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPin? {
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return nil
        }

        let liveTitle = liveTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = liveTitle.isEmpty ? pin.title : liveTitle
        let updated = updateShortcutPin(
            pin,
            title: resolvedTitle,
            launchURL: liveTab.url
        )
        return updated
    }

    @discardableResult
    func resetShortcutPinToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool = false
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
                return nil
            }

            let shouldPreserveCurrentPage = preserveCurrentPage
                && liveTab.url.absoluteString != pin.launchURL.absoluteString

            if shouldPreserveCurrentPage {
                guard let targetSpaceId = pin.spaceId ?? windowState.currentSpaceId else {
                    return nil
                }
                let duplicateTab = Tab(
                    url: liveTab.url,
                    name: liveTab.name,
                    favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId: targetSpaceId,
                    index: 0,
                    faviconService: faviconService,
                    faviconImageService: faviconImageService,
                    visitedLinkStore: visitedLinkStore
                )
                duplicateTab.favicon = liveTab.favicon
                duplicateTab.faviconIsTemplateGlobePlaceholder = liveTab.faviconIsTemplateGlobePlaceholder
                duplicateTab.profileId = liveTab.profileId
                attach(duplicateTab)
                var spaceTabs = tabsBySpace[targetSpaceId] ?? []
                spaceTabs.append(duplicateTab)
                setTabs(spaceTabs, for: targetSpaceId)
            }

            _ = liveTab.acceptResolvedDisplayTitle(pin.title, url: pin.launchURL)
            liveTab.url = pin.launchURL
            liveTab.loadURL(pin.launchURL)

            let updated = updateShortcutPin(
                pin,
                title: pin.title,
                launchURL: pin.launchURL
            )
            return updated
        }
    }

    // MARK: - Essentials API (profile-aware)

    func removeFromEssentials(_ pin: ShortcutPin) {
        removeShortcutPin(pin)
    }

    @discardableResult
    func reorderEssential(_ pin: ShortcutPin, to index: Int) -> Bool {
        withStructuralUpdateTransaction {
            guard let pid = pin.profileId else { return false }
            var arr = pinnedByProfile[pid] ?? []
            guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return false }
            let adjustedIndex = adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: index
            )
            guard adjustedIndex != currentIndex else { return false }
            if currentIndex < arr.count { arr.remove(at: currentIndex) }
            arr.insert(pin, at: max(0, min(adjustedIndex, arr.count)))
            setPinnedTabs(reindexed(arr), for: pid)
            scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    func reorderSpacePinned(_ pin: ShortcutPin, in spaceId: UUID, to index: Int) -> Bool {
        withStructuralUpdateTransaction {
            var didReorder = false
            if pin.folderId == nil {
                didReorder = reorderTopLevelSpacePinnedShortcut(pin, in: spaceId, to: index) != nil
            } else {
                withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { arr in
                    guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return }
                    let adjustedIndex = adjustedSameContainerInsertionIndex(
                        currentIndex: currentIndex,
                        proposedIndex: index
                    )
                    guard adjustedIndex != currentIndex else { return }
                    if currentIndex < arr.count { arr.remove(at: currentIndex) }
                    arr.insert(pin, at: max(0, min(adjustedIndex, arr.count)))
                    didReorder = true
                }
            }
            if didReorder {
                scheduleStructuralPersistence()
            }
            return didReorder
        }
    }

    // MARK: - Space-Level Pinned Tabs

    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        withStructuralUpdateTransaction {
            guard spaces.contains(where: { $0.id == spaceId }) else { return }
            if spacePinnedPins(for: spaceId).contains(where: { $0.launchURL == tab.url }) { return }

            if tab.isShortcutLiveInstance,
               let shortcutId = tab.shortcutPinId,
               let sourcePin = shortcutPin(by: shortcutId),
               sourcePin.role == .essential {
                let targetIndex = spacePinnedPins(for: spaceId).count
                let detachedPin = makeShortcutPin(
                    from: tab,
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceId,
                    folderId: nil,
                    index: targetIndex
                )

                guard let insertedPin = insertShortcutPin(detachedPin, at: targetIndex) else {
                    return
                }

                if let windowId = windowIdDisplaying(tabId: tab.id) {
                    var liveTabs = transientShortcutTabsByWindow[windowId] ?? [:]
                    liveTabs.removeValue(forKey: sourcePin.id)
                    liveTabs[insertedPin.id] = tab
                    transientShortcutTabsByWindow[windowId] = liveTabs
                    notifyTransientShortcutStateChanged()

                    tab.bindToShortcutPin(insertedPin)
                    let currentSpaceId = runtimeContext?.windowState(for: windowId)?.currentSpaceId
                    tab.spaceId = resolvedLiveSpaceId(for: insertedPin, currentSpaceId: currentSpaceId)
                    tab.folderId = nil
                    assignProfile(
                        resolvedExecutionProfileId(for: insertedPin, currentSpaceId: currentSpaceId),
                        to: tab
                    )

                    if let windowState = runtimeContext?.windowState(for: windowId),
                       windowState.currentShortcutPinId == sourcePin.id {
                        windowState.currentShortcutPinId = insertedPin.id
                        windowState.currentShortcutPinRole = insertedPin.role
                    }
                }

                scheduleStructuralPersistence()
                return
            }

            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: spacePinnedPins(for: spaceId).count
            )
        }
    }

    func reindexed(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        pins.enumerated().map { index, pin in
            ShortcutPin(
                id: pin.id,
                role: pin.role,
                profileId: pin.profileId,
                executionProfileId: pin.executionProfileId,
                spaceId: pin.spaceId,
                index: index,
                folderId: pin.folderId,
                launchURL: pin.launchURL,
                title: pin.title,
                iconAsset: pin.iconAsset
            )
        }
    }

    func convertTabToShortcutLiveInstance(
        _ tab: Tab,
        pin: ShortcutPin,
        in windowId: UUID,
        updateSelection: Bool = true
    ) {
        removeFromCurrentContainer(tab)
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        let currentSpaceId = runtimeContext?.windowState(for: windowId)?.currentSpaceId
        tab.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
        tab.folderId = pin.folderId
        var liveTabs = transientShortcutTabsByWindow[windowId] ?? [:]
        liveTabs[pin.id] = tab
        transientShortcutTabsByWindow[windowId] = liveTabs
        notifyTransientShortcutStateChanged()

        if let windowState = runtimeContext?.windowState(for: windowId) {
            if updateSelection || windowState.currentTabId == tab.id {
                windowState.currentShortcutPinId = pin.id
                windowState.currentShortcutPinRole = pin.role
                windowState.currentTabId = tab.id
                windowState.isShowingEmptyState = false
            }
            if let spaceId = pin.spaceId {
                if updateSelection {
                    windowState.currentSpaceId = spaceId
                }
                if windowState.activeTabForSpace[spaceId] == tab.id {
                    windowState.activeTabForSpace[spaceId] = tabsBySpace[spaceId]?.first?.id
                }
            }
            windowState.removeFromRegularTabHistory(tab.id)
        }
    }

    @discardableResult
    func convertDisplayedTabToShortcutLiveInstances(
        _ tab: Tab,
        pin: ShortcutPin,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        let selectedWindowIds = windowIdsSelecting(
            tabId: tab.id,
            preferredWindowId: preferredWindowId
        )
        let displayingWindowIds = windowIdsDisplaying(
            tabId: tab.id,
            preferredWindowId: preferredWindowId
        )
        guard let firstWindowId = selectedWindowIds.first ?? displayingWindowIds.first else {
            return false
        }

        convertTabToShortcutLiveInstance(
            tab,
            pin: pin,
            in: firstWindowId,
            updateSelection: selectedWindowIds.contains(firstWindowId)
        )

        for windowId in displayingWindowIds where windowId != firstWindowId {
            let isSelectedWindow = selectedWindowIds.contains(windowId)
            if !isSelectedWindow,
               runtimeContext?.isTabVisibleInSplit(tab.id, in: windowId) == true {
                continue
            }
            replaceDisplayedTabWithShortcutLiveInstance(
                tab,
                pin: pin,
                in: windowId,
                updateSelection: isSelectedWindow
            )
        }
        return true
    }

    private func replaceDisplayedTabWithShortcutLiveInstance(
        _ originalTab: Tab,
        pin: ShortcutPin,
        in windowId: UUID,
        updateSelection: Bool = true
    ) {
        guard let windowState = runtimeContext?.windowState(for: windowId) else { return }
        let liveTab = activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: windowState.currentSpaceId
        )

        if windowState.currentTabId == originalTab.id {
            windowState.currentTabId = liveTab.id
        }
        if updateSelection || windowState.currentTabId == liveTab.id {
            windowState.currentShortcutPinId = pin.id
            windowState.currentShortcutPinRole = pin.role
            windowState.isShowingEmptyState = false
        }
        if let spaceId = pin.spaceId {
            if updateSelection {
                windowState.currentSpaceId = spaceId
            }
            if windowState.activeTabForSpace[spaceId] == originalTab.id {
                windowState.activeTabForSpace[spaceId] = tabsBySpace[spaceId]?.first?.id
            }
        }
        windowState.removeFromRegularTabHistory(originalTab.id)
        runtimeContext?.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(liveTab, in: windowState)
    }

    @discardableResult
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        withStructuralUpdateTransaction {
            if let existing = transientShortcutTabsByWindow[windowId]?[pin.id] {
                existing.bindToShortcutPin(pin)
                existing.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
                existing.folderId = pin.folderId
                assignProfile(
                    resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId),
                    to: existing
                )
                attach(existing)
                return existing
            }

            let resolvedSpaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
            let tab = Tab(
                url: pin.launchURL,
                name: pin.title,
                favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                spaceId: resolvedSpaceId,
                index: 0,
                faviconService: faviconService,
                faviconImageService: faviconImageService,
                visitedLinkStore: visitedLinkStore
            )
            tab.bindToShortcutPin(pin)
            tab.profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
            tab.folderId = pin.folderId
            _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
            attach(tab)
            var liveTabs = transientShortcutTabsByWindow[windowId] ?? [:]
            liveTabs[pin.id] = tab
            transientShortcutTabsByWindow[windowId] = liveTabs
            notifyTransientShortcutStateChanged()
            return tab
        }
    }

    @discardableResult
    func deactivateShortcutLiveTab(in windowId: UUID) -> Bool {
        guard let pinId = activeShortcutTab(for: windowId)?.shortcutPinId else { return false }
        return deactivateShortcutLiveTab(pinId: pinId, in: windowId)
    }

    @discardableResult
    func deactivateShortcutLiveTab(pinId: UUID, in windowId: UUID) -> Bool {
        withStructuralUpdateTransaction {
            guard let tab = transientShortcutTabsByWindow[windowId]?.removeValue(forKey: pinId) else { return false }
            let runtimeContext = runtimeContext
            let windowState = runtimeContext?.windowState(for: windowId)
            let cleanupResult = windowState.map {
                clearShortcutSelectionReferences(
                    to: pinId,
                    removedLiveTabId: tab.id,
                    removeRememberedSelection: false,
                    in: $0
                )
            } ?? ShortcutPinSelectionCleanupResult()
            cancelRuntimeStatePersistence(for: tab.id)
            if transientShortcutTabsByWindow[windowId]?.isEmpty == true {
                transientShortcutTabsByWindow.removeValue(forKey: windowId)
            }
            notifyTransientShortcutStateChanged()
            tab.performComprehensiveWebViewCleanup()
            runtimeContext?.webViewLifecycle.unloadTab(tab)
            detach(tab)
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
            return cleanupResult.didClearCurrentSelection
        }
    }

    @discardableResult
    func clearDeletedShortcutPinSelectionReferences(_ pinId: UUID) -> ShortcutPinSelectionCleanupResult {
        var cleanupResult = ShortcutPinSelectionCleanupResult()
        runtimeContext?.forEachWindowState { windowState in
            cleanupResult.merge(clearShortcutSelectionReferences(
                to: pinId,
                removedLiveTabId: nil,
                removeRememberedSelection: true,
                in: windowState
            ))
        }
        return cleanupResult
    }

    func persistWindowSessionsForShortcutSelectionCleanup(_ cleanupResult: ShortcutPinSelectionCleanupResult) {
        guard let runtimeContext else { return }
        for windowState in cleanupResult.windowStatesNeedingPersistence {
            runtimeContext.persistWindowSession(for: windowState)
        }
    }

    @discardableResult
    private func clearShortcutSelectionReferences(
        to pinId: UUID,
        removedLiveTabId: UUID?,
        removeRememberedSelection: Bool,
        in windowState: BrowserWindowState
    ) -> ShortcutPinSelectionCleanupResult {
        var cleanupResult = ShortcutPinSelectionCleanupResult()
        if let removedLiveTabId, windowState.currentTabId == removedLiveTabId {
            windowState.currentTabId = nil
            cleanupResult.recordCurrentSelectionCleared(in: windowState)
        }
        if windowState.currentTabId == pinId {
            windowState.currentTabId = nil
            cleanupResult.recordCurrentSelectionCleared(in: windowState)
        }
        if windowState.currentShortcutPinId == pinId {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            cleanupResult.recordCurrentSelectionCleared(in: windowState)
        }
        if removeRememberedSelection {
            let staleSpaceIds = windowState.selectedShortcutPinForSpace.compactMap { spaceId, selectedPinId in
                selectedPinId == pinId ? spaceId : nil
            }
            for spaceId in staleSpaceIds {
                windowState.selectedShortcutPinForSpace.removeValue(forKey: spaceId)
            }
            if !staleSpaceIds.isEmpty {
                cleanupResult.recordWindowSessionChange(in: windowState)
            }
        }
        windowState.removeFromShortcutLiveSelectionHistory(pinId)
        return cleanupResult
    }

    func folderSpaceId(for folderId: UUID) -> UUID? {
        foldersBySpace.first(where: { $0.value.contains(where: { $0.id == folderId }) })?.key
    }

    func windowIdDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> UUID? {
        windowIdsDisplaying(tabId: tabId, preferredWindowId: preferredWindowId).first
    }

    func windowIdsSelecting(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtimeContext else { return [] }

        func windowSelectsTab(_ windowState: BrowserWindowState) -> Bool {
            windowState.currentTabId == tabId
        }

        var orderedWindowIds: [UUID] = []

        if let primaryWindowId = tab(for: tabId)?.primaryWindowId,
           let primaryWindow = runtimeContext.windowState(for: primaryWindowId),
           windowSelectsTab(primaryWindow) {
            orderedWindowIds.append(primaryWindowId)
        }

        if let preferredWindowId,
           let preferredWindow = runtimeContext.windowState(for: preferredWindowId),
           windowSelectsTab(preferredWindow),
           !orderedWindowIds.contains(preferredWindowId) {
            orderedWindowIds.append(preferredWindowId)
        }

        var matchedWindowIds: [UUID] = []
        runtimeContext.forEachWindow { windowId, windowState in
            if !orderedWindowIds.contains(windowId),
               windowSelectsTab(windowState) {
                matchedWindowIds.append(windowId)
            }
        }
        orderedWindowIds.append(
            contentsOf: matchedWindowIds.sorted { $0.uuidString < $1.uuidString }
        )
        return orderedWindowIds
    }

    func windowIdsDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtimeContext else { return [] }

        func windowDisplaysTab(_ windowId: UUID, _ windowState: BrowserWindowState) -> Bool {
            if windowState.currentTabId == tabId {
                return true
            }

            return runtimeContext.visibleSplitTabIds(for: windowId).contains(tabId)
        }

        var orderedWindowIds: [UUID] = []

        if let preferredWindowId,
           let preferredWindow = runtimeContext.windowState(for: preferredWindowId),
           windowDisplaysTab(preferredWindowId, preferredWindow) {
            orderedWindowIds.append(preferredWindowId)
        }

        if let primaryWindowId = tab(for: tabId)?.primaryWindowId,
           let primaryWindow = runtimeContext.windowState(for: primaryWindowId),
           windowDisplaysTab(primaryWindowId, primaryWindow),
           !orderedWindowIds.contains(primaryWindowId) {
            orderedWindowIds.append(primaryWindowId)
        }

        var matchedWindowIds: [UUID] = []
        runtimeContext.forEachWindow { windowId, windowState in
            if !orderedWindowIds.contains(windowId),
               windowDisplaysTab(windowId, windowState) {
                matchedWindowIds.append(windowId)
            }
        }
        orderedWindowIds.append(
            contentsOf: matchedWindowIds.sorted { $0.uuidString < $1.uuidString }
        )
        return orderedWindowIds
    }

    func windowStateDisplaying(tabId: UUID) -> BrowserWindowState? {
        guard let windowId = windowIdDisplaying(tabId: tabId) else { return nil }
        return runtimeContext?.windowState(for: windowId)
    }

    func removeFromCurrentContainer(_ tab: Tab) {
        for (pid, arr) in pinnedByProfile {
            if let index = arr.firstIndex(where: { $0.id == tab.id }) {
                var copy = arr
                if index < copy.count { copy.remove(at: index) }
                setPinnedTabs(copy, for: pid)
                return
            }
        }

        if let spaceId = tab.spaceId {
            _ = regularTabCollectionOwner.remove(
                tab.id,
                from: spaceId,
                currentSpaceId: currentSpace?.id
            )
        }
    }
}
