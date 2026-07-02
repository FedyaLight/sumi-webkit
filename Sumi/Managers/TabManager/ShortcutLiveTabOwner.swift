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
final class ShortcutLiveTabOwner {
    struct Dependencies {
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]
        let updateTransientShortcutTabsByWindow: @MainActor ((inout [UUID: [UUID: Tab]]) -> Void) -> Void
        let currentSpaceId: @MainActor () -> UUID?
        let firstRegularTabId: @MainActor (UUID) -> UUID?
        let tab: @MainActor (UUID) -> Tab?
        let resolvedLiveSpaceId: @MainActor (ShortcutPin, UUID?) -> UUID?
        let resolvedExecutionProfileId: @MainActor (ShortcutPin, UUID?) -> UUID?
        let assignProfile: @MainActor (UUID?, Tab) -> Void
        let attach: @MainActor (Tab) -> Void
        let detach: @MainActor (Tab) -> Void
        let notifyTransientShortcutStateChanged: @MainActor () -> Void
        let cancelRuntimeStatePersistence: @MainActor (UUID) -> Void
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
        let removeRegularTab: @MainActor (UUID, UUID, UUID?) -> Void
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let visitedLinkStore: @MainActor () -> any BrowserVisitedLinkStoreManaging
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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
        let currentSpaceId = dependencies.runtimeContext()?.windowState(for: windowId)?.currentSpaceId
        tab.spaceId = dependencies.resolvedLiveSpaceId(pin, currentSpaceId)
        tab.folderId = pin.folderId
        dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
            var liveTabs = liveTabsByWindow[windowId] ?? [:]
            liveTabs[pin.id] = tab
            liveTabsByWindow[windowId] = liveTabs
        }
        dependencies.notifyTransientShortcutStateChanged()

        if let windowState = dependencies.runtimeContext()?.windowState(for: windowId) {
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
                    windowState.activeTabForSpace[spaceId] = dependencies.firstRegularTabId(spaceId)
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
               dependencies.runtimeContext()?.isTabVisibleInSplit(tab.id, in: windowId) == true {
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

    @discardableResult
    func rebindLiveShortcutTab(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to insertedPin: ShortcutPin
    ) -> Bool {
        guard let windowId = windowIdDisplaying(tabId: tab.id) else { return false }

        dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
            var liveTabs = liveTabsByWindow[windowId] ?? [:]
            liveTabs.removeValue(forKey: sourcePin.id)
            liveTabs[insertedPin.id] = tab
            liveTabsByWindow[windowId] = liveTabs
        }
        dependencies.notifyTransientShortcutStateChanged()

        tab.bindToShortcutPin(insertedPin)
        let currentSpaceId = dependencies.runtimeContext()?.windowState(for: windowId)?.currentSpaceId
        tab.spaceId = dependencies.resolvedLiveSpaceId(insertedPin, currentSpaceId)
        tab.folderId = nil
        dependencies.assignProfile(
            dependencies.resolvedExecutionProfileId(insertedPin, currentSpaceId),
            tab
        )

        if let windowState = dependencies.runtimeContext()?.windowState(for: windowId),
           windowState.currentShortcutPinId == sourcePin.id {
            windowState.currentShortcutPinId = insertedPin.id
            windowState.currentShortcutPinRole = insertedPin.role
        }
        return true
    }

    @discardableResult
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        let currentLiveTabsByWindow = dependencies.transientShortcutTabsByWindow()
        if let existing = currentLiveTabsByWindow[windowId]?[pin.id] {
            existing.bindToShortcutPin(pin)
            existing.spaceId = dependencies.resolvedLiveSpaceId(pin, currentSpaceId)
            existing.folderId = pin.folderId
            dependencies.assignProfile(
                dependencies.resolvedExecutionProfileId(pin, currentSpaceId),
                existing
            )
            dependencies.attach(existing)
            return existing
        }

        let resolvedSpaceId = dependencies.resolvedLiveSpaceId(pin, currentSpaceId)
        let tab = Tab(
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: resolvedSpaceId,
            index: 0,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
        tab.bindToShortcutPin(pin)
        tab.profileId = dependencies.resolvedExecutionProfileId(pin, currentSpaceId)
        tab.folderId = pin.folderId
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        dependencies.attach(tab)
        dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
            var liveTabs = liveTabsByWindow[windowId] ?? [:]
            liveTabs[pin.id] = tab
            liveTabsByWindow[windowId] = liveTabs
        }
        dependencies.notifyTransientShortcutStateChanged()
        return tab
    }

    @discardableResult
    func deactivateShortcutLiveTab(pinId: UUID, in windowId: UUID) -> Bool {
        var removedTab: Tab?
        dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
            removedTab = liveTabsByWindow[windowId]?.removeValue(forKey: pinId)
        }
        guard let tab = removedTab else { return false }

        let runtimeContext = dependencies.runtimeContext()
        let windowState = runtimeContext?.windowState(for: windowId)
        let cleanupResult = windowState.map {
            clearShortcutSelectionReferences(
                to: pinId,
                removedLiveTabId: tab.id,
                removeRememberedSelection: false,
                in: $0
            )
        } ?? ShortcutPinSelectionCleanupResult()
        dependencies.cancelRuntimeStatePersistence(tab.id)
        dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
            if liveTabsByWindow[windowId]?.isEmpty == true {
                liveTabsByWindow.removeValue(forKey: windowId)
            }
        }
        dependencies.notifyTransientShortcutStateChanged()
        tab.performComprehensiveWebViewCleanup()
        runtimeContext?.webViewLifecycle.unloadTab(tab)
        dependencies.detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
        return cleanupResult.didClearCurrentSelection
    }

    @discardableResult
    func removeLiveShortcutTabs(forDeletedPinId pinId: UUID) -> ShortcutPinSelectionCleanupResult {
        let liveWindowIds = dependencies.transientShortcutTabsByWindow().compactMap { windowId, tabsByPin in
            tabsByPin[pinId] == nil ? nil : windowId
        }
        var cleanupResult = ShortcutPinSelectionCleanupResult()
        for windowId in liveWindowIds {
            let windowState = dependencies.runtimeContext()?.windowState(for: windowId)
            if deactivateShortcutLiveTab(pinId: pinId, in: windowId),
               let windowState {
                cleanupResult.recordCurrentSelectionCleared(in: windowState)
            }
        }
        cleanupResult.merge(clearDeletedShortcutPinSelectionReferences(pinId))
        return cleanupResult
    }

    @discardableResult
    func clearDeletedShortcutPinSelectionReferences(_ pinId: UUID) -> ShortcutPinSelectionCleanupResult {
        var cleanupResult = ShortcutPinSelectionCleanupResult()
        dependencies.runtimeContext()?.forEachWindowState { windowState in
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
        guard let runtimeContext = dependencies.runtimeContext() else { return }
        for windowState in cleanupResult.windowStatesNeedingPersistence {
            runtimeContext.persistWindowSession(for: windowState)
        }
    }

    func windowIdDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> UUID? {
        windowIdsDisplaying(tabId: tabId, preferredWindowId: preferredWindowId).first
    }

    func windowIdsSelecting(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        guard let runtimeContext = dependencies.runtimeContext() else { return [] }

        func windowSelectsTab(_ windowState: BrowserWindowState) -> Bool {
            windowState.currentTabId == tabId
        }

        var orderedWindowIds: [UUID] = []

        if let primaryWindowId = dependencies.tab(tabId)?.primaryWindowId,
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
        guard let runtimeContext = dependencies.runtimeContext() else { return [] }

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

        if let primaryWindowId = dependencies.tab(tabId)?.primaryWindowId,
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
        return dependencies.runtimeContext()?.windowState(for: windowId)
    }

    func removeFromCurrentContainer(_ tab: Tab) {
        for (profileId, pins) in dependencies.pinnedByProfile() {
            if let index = pins.firstIndex(where: { $0.id == tab.id }) {
                var copy = pins
                if index < copy.count { copy.remove(at: index) }
                dependencies.setPinnedTabs(copy, profileId)
                return
            }
        }

        if let spaceId = tab.spaceId {
            dependencies.removeRegularTab(
                tab.id,
                spaceId,
                dependencies.currentSpaceId()
            )
        }
    }

    private func replaceDisplayedTabWithShortcutLiveInstance(
        _ originalTab: Tab,
        pin: ShortcutPin,
        in windowId: UUID,
        updateSelection: Bool = true
    ) {
        guard let windowState = dependencies.runtimeContext()?.windowState(for: windowId) else { return }
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
                windowState.activeTabForSpace[spaceId] = dependencies.firstRegularTabId(spaceId)
            }
        }
        windowState.removeFromRegularTabHistory(originalTab.id)
        dependencies.runtimeContext()?.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(liveTab, in: windowState)
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
}
