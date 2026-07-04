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
        let withStructuralUpdateTransaction: @MainActor (@MainActor () -> Bool) -> Bool
        let withStructuralUpdateTransactionReturningTab: @MainActor (@MainActor () -> Tab) -> Tab
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]
        let updateTransientShortcutTabsByWindow: @MainActor ((inout [UUID: [UUID: Tab]]) -> Void) -> Void
        let firstRegularTabId: @MainActor (UUID) -> UUID?
        let tab: @MainActor (UUID) -> Tab?
        let activeShortcutTab: @MainActor (UUID) -> Tab?
        let resolvedLiveSpaceId: @MainActor (ShortcutPin, UUID?) -> UUID?
        let resolvedExecutionProfileId: @MainActor (ShortcutPin, UUID?) -> UUID?
        let assignProfile: @MainActor (UUID?, Tab) -> Void
        let attach: @MainActor (Tab) -> Void
        let detach: @MainActor (Tab) -> Void
        let notifyTransientShortcutStateChanged: @MainActor () -> Void
        let cancelRuntimeStatePersistence: @MainActor (UUID) -> Void
        let removeFromCurrentContainer: @MainActor (Tab) -> Void
        let insertRegularTab: @MainActor (Tab, UUID, Int?) -> Void
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let visitedLinkStore: @MainActor () -> any BrowserVisitedLinkStoreManaging
    }

    private let dependencies: Dependencies
    private let windowQuery: ShortcutLiveTabWindowQueryOwner

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.windowQuery = ShortcutLiveTabWindowQueryOwner(
            dependencies: ShortcutLiveTabWindowQueryOwner.Dependencies(
                runtimeContext: dependencies.runtimeContext,
                tab: dependencies.tab
            )
        )
    }

    func convertTabToShortcutLiveInstance(
        _ tab: Tab,
        pin: ShortcutPin,
        in windowId: UUID,
        updateSelection: Bool = true
    ) {
        dependencies.removeFromCurrentContainer(tab)
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
            windowState.selectionHistory.removeFromRegularTabHistory(tab.id)
        }
    }

    @discardableResult
    func convertDisplayedTabToShortcutLiveInstances(
        _ tab: Tab,
        pin: ShortcutPin,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        let selectedWindowIds = windowQuery.windowIdsSelecting(
            tabId: tab.id,
            preferredWindowId: preferredWindowId
        )
        let displayingWindowIds = windowQuery.windowIdsDisplaying(
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
        guard let windowId = windowQuery.windowIdDisplaying(tabId: tab.id) else { return false }

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

    func updateTransientShortcutBindings(for pin: ShortcutPin) {
        for (windowId, tabsByPin) in dependencies.transientShortcutTabsByWindow() {
            if let tab = tabsByPin[pin.id] {
                tab.bindToShortcutPin(pin)
                let windowCurrentSpaceId = dependencies.runtimeContext()?.windowState(for: windowId)?.currentSpaceId
                tab.spaceId = dependencies.resolvedLiveSpaceId(pin, windowCurrentSpaceId)
                tab.folderId = pin.folderId
                dependencies.assignProfile(
                    dependencies.resolvedExecutionProfileId(pin, windowCurrentSpaceId),
                    tab
                )
                if let windowState = dependencies.runtimeContext()?.windowState(for: windowId) {
                    if windowState.currentShortcutPinId == pin.id {
                        windowState.currentShortcutPinRole = pin.role
                    }
                    if let spaceId = pin.spaceId {
                        windowState.currentSpaceId = spaceId
                    }
                }
            }
        }
    }

    @discardableResult
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        dependencies.withStructuralUpdateTransactionReturningTab {
            activateShortcutPinWithoutStartingTransaction(pin, in: windowId, currentSpaceId: currentSpaceId)
        }
    }

    @discardableResult
    private func activateShortcutPinWithoutStartingTransaction(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
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
    func deactivateShortcutLiveTab(in windowId: UUID) -> Bool {
        guard let pinId = dependencies.activeShortcutTab(windowId)?.shortcutPinId else { return false }
        return deactivateShortcutLiveTab(pinId: pinId, in: windowId)
    }

    @discardableResult
    func deactivateShortcutLiveTab(pinId: UUID, in windowId: UUID) -> Bool {
        dependencies.withStructuralUpdateTransaction {
            deactivateShortcutLiveTabWithoutStartingTransaction(pinId: pinId, in: windowId)
        }
    }

    @discardableResult
    private func deactivateShortcutLiveTabWithoutStartingTransaction(pinId: UUID, in windowId: UUID) -> Bool {
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

    func liveShortcutEntry(for pinId: UUID) -> (windowId: UUID, tab: Tab)? {
        for (windowId, tabsByPin) in dependencies.transientShortcutTabsByWindow() {
            if let tab = tabsByPin[pinId] {
                return (windowId, tab)
            }
        }
        return nil
    }

    @discardableResult
    func insertRegularTabFromShortcut(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil
    ) -> Tab {
        if let existing = liveShortcutEntry(for: pin.id) {
            let existingWindowId = existing.windowId
            let existingLiveTab = existing.tab
            dependencies.updateTransientShortcutTabsByWindow { liveTabsByWindow in
                liveTabsByWindow[existingWindowId]?.removeValue(forKey: pin.id)
                if liveTabsByWindow[existingWindowId]?.isEmpty == true {
                    liveTabsByWindow.removeValue(forKey: existingWindowId)
                }
            }
            dependencies.notifyTransientShortcutStateChanged()
            existingLiveTab.clearShortcutBinding()
            existingLiveTab.spaceId = targetSpaceId
            existingLiveTab.folderId = nil
            existingLiveTab.isPinned = false
            existingLiveTab.isSpacePinned = false
            dependencies.attach(existingLiveTab)
            dependencies.insertRegularTab(existingLiveTab, targetSpaceId, targetIndex)
            if let windowState = dependencies.runtimeContext()?.windowState(for: existingWindowId) {
                windowState.currentShortcutPinId = nil
                windowState.currentShortcutPinRole = nil
                windowState.currentSpaceId = targetSpaceId
                windowState.currentTabId = existingLiveTab.id
                windowState.activeTabForSpace[targetSpaceId] = existingLiveTab.id
            }
            return existingLiveTab
        }

        let tab = Tab(
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: targetSpaceId,
            index: 0,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        dependencies.attach(tab)
        dependencies.insertRegularTab(tab, targetSpaceId, targetIndex)
        return tab
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

    /// Delegates to `windowQuery`; kept here because `TabRegularLifecycleOwner` reaches this
    /// through `shortcutLiveTabOwner`.
    func windowStateDisplaying(tabId: UUID) -> BrowserWindowState? {
        windowQuery.windowStateDisplaying(tabId: tabId)
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
        windowState.selectionHistory.removeFromRegularTabHistory(originalTab.id)
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
        windowState.selectionHistory.removeFromShortcutLiveSelectionHistory(pinId)
        return cleanupResult
    }
}

extension ShortcutLiveTabOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            withStructuralUpdateTransactionReturningTab: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            runtimeContext: { [weak tabManager] in
                tabManager?.runtimeContext
            },
            transientShortcutTabsByWindow: { [weak tabManager] in
                tabManager?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            },
            updateTransientShortcutTabsByWindow: { [weak tabManager] update in
                tabManager?.transientTabRegistryOwner.updateTransientShortcutTabsByWindow(update)
            },
            firstRegularTabId: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId).first?.id
            },
            tab: { [weak tabManager] tabId in
                tabManager?.tabCollectionMembershipOwner.tab(for: tabId)
            },
            activeShortcutTab: { [weak tabManager] windowId in
                tabManager?.shortcutPresentationOwner.activeShortcutTab(for: windowId)
            },
            resolvedLiveSpaceId: { [weak tabManager] pin, currentSpaceId in
                tabManager?.shortcutPinRuntimeResolutionOwner.resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
            },
            resolvedExecutionProfileId: { [weak tabManager] pin, currentSpaceId in
                tabManager?.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
            },
            assignProfile: { [weak tabManager] profileId, tab in
                tabManager?.profileAssignmentOwner.assignProfile(profileId, to: tab)
            },
            attach: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.attach(tab)
            },
            detach: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.detach(tab)
            },
            notifyTransientShortcutStateChanged: { [weak tabManager] in
                tabManager?.notifyTransientShortcutStateChanged()
            },
            cancelRuntimeStatePersistence: { [weak tabManager] tabId in
                tabManager?.structuralPersistence.cancelRuntimeStatePersistence(for: tabId)
            },
            removeFromCurrentContainer: { [weak tabManager] tab in
                tabManager?.shortcutContainerRemovalOwner.removeFromCurrentContainer(tab)
            },
            insertRegularTab: { [weak tabManager] tab, spaceId, insertionIndex in
                tabManager?.regularTabCollectionOwner.insert(tab, in: spaceId, at: insertionIndex)
            },
            faviconService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconService
            },
            faviconImageService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconImageService
            },
            visitedLinkStore: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.visitedLinkStore
            }
        )
    }
}
