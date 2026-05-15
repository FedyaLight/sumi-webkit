import Foundation

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

            if tab.id == currentTab?.id, let windowId = browserManager?.windowRegistry?.activeWindow?.id {
                convertTabToShortcutLiveInstance(tab, pin: insertedPin, in: windowId)
            } else {
                removeTab(tab.id)
            }
            scheduleStructuralPersistence()
        }
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        withStructuralUpdateTransaction {
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
            for windowId in liveWindowIds {
                deactivateShortcutLiveTab(pinId: pin.id, in: windowId)
            }
            scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func updateShortcutPin(
        _ pin: ShortcutPin,
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil
    ) -> ShortcutPin? {
        return withStructuralUpdateTransaction {
            let updatedPin = pin.updated(
                title: title,
                launchURL: launchURL,
                iconAsset: iconAsset
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
        return withStructuralUpdateTransaction {
            guard pin.role == .spacePinned,
                  let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id),
                  let targetSpaceId = pin.spaceId ?? windowState.currentSpaceId else {
                return nil
            }

            let shouldPreserveCurrentPage = preserveCurrentPage
                && liveTab.url.absoluteString != pin.launchURL.absoluteString

            if shouldPreserveCurrentPage {
                let duplicateTab = Tab(
                    url: liveTab.url,
                    name: liveTab.name,
                    favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId: targetSpaceId,
                    index: 0,
                    browserManager: browserManager
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
                    let currentSpaceId = browserManager?.windowRegistry?.windows[windowId]?.currentSpaceId
                    tab.spaceId = resolvedLiveSpaceId(for: insertedPin, currentSpaceId: currentSpaceId)
                    tab.folderId = nil
                    tab.profileId = insertedPin.profileId

                    if let windowState = browserManager?.windowRegistry?.windows[windowId],
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
                spaceId: pin.spaceId,
                index: index,
                folderId: pin.folderId,
                launchURL: pin.launchURL,
                title: pin.title,
                iconAsset: pin.iconAsset
            )
        }
    }

    func convertTabToShortcutLiveInstance(_ tab: Tab, pin: ShortcutPin, in windowId: UUID) {
        removeFromCurrentContainer(tab)
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        let currentSpaceId = browserManager?.windowRegistry?.windows[windowId]?.currentSpaceId
        tab.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
        tab.folderId = pin.folderId
        var liveTabs = transientShortcutTabsByWindow[windowId] ?? [:]
        liveTabs[pin.id] = tab
        transientShortcutTabsByWindow[windowId] = liveTabs
        notifyTransientShortcutStateChanged()

        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            windowState.currentShortcutPinId = pin.id
            windowState.currentShortcutPinRole = pin.role
            windowState.currentTabId = tab.id
            windowState.isShowingEmptyState = false
            if let spaceId = pin.spaceId {
                windowState.currentSpaceId = spaceId
                if windowState.activeTabForSpace[spaceId] == tab.id {
                    windowState.activeTabForSpace[spaceId] = tabsBySpace[spaceId]?.first?.id
                }
            }
            windowState.removeFromRegularTabHistory(tab.id)
        }
    }

    @discardableResult
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        return withStructuralUpdateTransaction {
            if let existing = transientShortcutTabsByWindow[windowId]?[pin.id] {
                existing.bindToShortcutPin(pin)
                existing.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
                existing.folderId = pin.folderId
                existing.profileId = pin.profileId
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
                browserManager: browserManager
            )
            tab.bindToShortcutPin(pin)
            tab.profileId = pin.profileId
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

    func deactivateShortcutLiveTab(in windowId: UUID) {
        guard let pinId = activeShortcutTab(for: windowId)?.shortcutPinId else { return }
        deactivateShortcutLiveTab(pinId: pinId, in: windowId)
    }

    func deactivateShortcutLiveTab(pinId: UUID, in windowId: UUID) {
        withStructuralUpdateTransaction {
            guard let tab = transientShortcutTabsByWindow[windowId]?.removeValue(forKey: pinId) else { return }
            cancelRuntimeStatePersistence(for: tab.id)
            if transientShortcutTabsByWindow[windowId]?.isEmpty == true {
                transientShortcutTabsByWindow.removeValue(forKey: windowId)
            }
            notifyTransientShortcutStateChanged()
            tab.performComprehensiveWebViewCleanup()
            browserManager?.compositorManager.unloadTab(tab)
            if let browserManager {
                browserManager.requireWebViewCoordinator().removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: true
                )
            }
            detach(tab)
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
        }
    }

    func folderSpaceId(for folderId: UUID) -> UUID? {
        foldersBySpace.first(where: { $0.value.contains(where: { $0.id == folderId }) })?.key
    }

    func windowIdDisplaying(tabId: UUID) -> UUID? {
        guard let windows = browserManager?.windowRegistry?.windows else { return nil }
        let splitManager = browserManager?.splitManager

        func windowDisplaysTab(_ windowId: UUID, _ windowState: BrowserWindowState) -> Bool {
            if windowState.currentTabId == tabId {
                return true
            }

            guard let splitManager else { return false }
            return splitManager.leftTabId(for: windowId) == tabId
                || splitManager.rightTabId(for: windowId) == tabId
        }

        if let activeWindowId = browserManager?.windowRegistry?.activeWindow?.id,
           let activeWindow = windows[activeWindowId],
           windowDisplaysTab(activeWindowId, activeWindow) {
            return activeWindowId
        }

        return windows.first(where: { windowId, windowState in
            windowDisplaysTab(windowId, windowState)
        })?.key
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

        if let spaceId = tab.spaceId,
           var regularTabs = tabsBySpace[spaceId],
           let index = regularTabs.firstIndex(where: { $0.id == tab.id }) {
            if index < regularTabs.count { regularTabs.remove(at: index) }
            setTabs(regularTabs, for: spaceId)
        }
    }
}
