import Foundation

extension TabManager {
    enum EssentialsCapacityPolicy {
        static let maxColumns = 3
        static let maxRows = 4
        static let maxItems = maxColumns * maxRows
    }

    struct EssentialsTargetContext {
        var windowState: BrowserWindowState? = nil
        var spaceId: UUID? = nil
        var profileId: UUID? = nil

        init(
            windowState: BrowserWindowState? = nil,
            spaceId: UUID? = nil,
            profileId: UUID? = nil
        ) {
            self.windowState = windowState
            self.spaceId = spaceId
            self.profileId = profileId
        }
    }

    enum EssentialsTargetSource {
        case space
        case window
        case explicitProfile
        case globalFallback
        case unresolved
    }

    struct EssentialsTargetResolution {
        let profileId: UUID?
        let source: EssentialsTargetSource
    }

    struct EssentialsInsertionContext {
        var target: EssentialsTargetContext? = nil
        var targetIndex: Int? = nil
        var movingPinId: UUID? = nil
    }

    struct EssentialsInsertionPlan {
        let profileId: UUID
        let index: Int
        let resolution: EssentialsTargetResolution
    }

    func withPinnedArray(for profileId: UUID, _ mutate: (inout [ShortcutPin]) -> Void) {
        var arr = pinnedByProfile[profileId] ?? []
        mutate(&arr)
        setPinnedTabs(reindexed(arr), for: profileId)
    }

    func resolveEssentialsTarget(
        using context: EssentialsTargetContext? = nil
    ) -> EssentialsTargetResolution {
        let resolvedSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        if let resolvedSpaceId,
           let profileId = spaces.first(where: { $0.id == resolvedSpaceId })?.profileId {
            return EssentialsTargetResolution(profileId: profileId, source: .space)
        }

        if let profileId = context?.windowState?.currentProfileId {
            return EssentialsTargetResolution(profileId: profileId, source: .window)
        }

        if let profileId = context?.profileId {
            return EssentialsTargetResolution(profileId: profileId, source: .explicitProfile)
        }

        if let profileId = browserManager?.currentProfile?.id {
            return EssentialsTargetResolution(profileId: profileId, source: .globalFallback)
        }

        return EssentialsTargetResolution(profileId: nil, source: .unresolved)
    }

    func resolvedEssentialsProfileId(
        using context: EssentialsTargetContext? = nil
    ) -> UUID? {
        resolveEssentialsTarget(using: context).profileId
    }

    func resolveEssentialsInsertion(
        using context: EssentialsInsertionContext
    ) -> EssentialsInsertionPlan? {
        let resolution = resolveEssentialsTarget(using: context.target)
        guard let profileId = resolution.profileId else { return nil }

        var pins = essentialPins(for: profileId)
        if let movingPinId = context.movingPinId,
           let existingIndex = pins.firstIndex(where: { $0.id == movingPinId }) {
            pins.remove(at: existingIndex)
        }

        guard pins.count < EssentialsCapacityPolicy.maxItems else { return nil }

        let targetIndex = max(0, min(context.targetIndex ?? pins.count, pins.count))
        return EssentialsInsertionPlan(
            profileId: profileId,
            index: targetIndex,
            resolution: resolution
        )
    }

    func resolvedEssentialsProfileId(for operation: DragOperation) -> UUID? {
        operation.scope.profileId
            ?? resolvedEssentialsProfileId(
                using: EssentialsTargetContext(spaceId: operation.scope.spaceId)
            )
    }

    func logEssentialsTargetMismatchIfNeeded(
        resolution: EssentialsTargetResolution,
        context: EssentialsTargetContext?
    ) {
        guard resolution.source == .globalFallback,
              let resolvedProfileId = resolution.profileId,
              let visibleProfileId = context?.windowState?.currentProfileId
                ?? browserManager?.windowRegistry?.activeWindow?.currentProfileId,
              visibleProfileId != resolvedProfileId else {
            return
        }

        RuntimeDiagnostics.emit(
            "⚠️ [Essentials] Fallback profile mismatch visible=\(visibleProfileId.uuidString) resolved=\(resolvedProfileId.uuidString)"
        )
    }

    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId else { return [] }
        return activeShortcutTabs(role: .essential).filter { tab in
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(by: shortcutId) else { return false }
            return pin.profileId == profileId
        }
    }

    func makeShortcutPin(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        folderId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: tab.url,
            title: tab.name,
            faviconCacheKey: ShortcutPin.makeFaviconCacheKey(for: tab.url)
        )
    }

    func resolvedLiveSpaceId(for pin: ShortcutPin, currentSpaceId: UUID?) -> UUID? {
        switch pin.role {
        case .essential:
            return nil
        case .spacePinned:
            return pin.spaceId ?? currentSpaceId
        }
    }

    func updateTransientShortcutBindings(for pin: ShortcutPin) {
        for (windowId, tabsByPin) in transientShortcutTabsByWindow {
            if let tab = tabsByPin[pin.id] {
                tab.bindToShortcutPin(pin)
                let windowCurrentSpaceId = browserManager?.windowRegistry?.windows[windowId]?.currentSpaceId
                tab.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: windowCurrentSpaceId)
                tab.folderId = pin.folderId
                tab.profileId = pin.profileId
                tab.favicon = pin.favicon
                tab.faviconIsTemplateGlobePlaceholder = pin.faviconIsUncachedGlobeTemplate
                if let windowState = browserManager?.windowRegistry?.windows[windowId] {
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
    func convertShortcutPinToRegularTab(_ pin: ShortcutPin, in targetSpaceId: UUID, at targetIndex: Int? = nil) -> Bool {
        withStructuralUpdateTransaction {
            _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: targetIndex)
            removeShortcutPinFromContainers(pin)
            scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    func insertShortcutPin(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        switch pin.role {
        case .essential:
            guard let profileId = pin.profileId else { return nil }
            var destination = pinnedByProfile[profileId] ?? []
            if let existingIndex = destination.firstIndex(where: { $0.id == pin.id }) {
                destination.remove(at: existingIndex)
            }
            guard destination.count < EssentialsCapacityPolicy.maxItems else { return nil }
            let safeIndex = max(0, min(targetIndex, destination.count))
            destination.insert(pin, at: safeIndex)
            let reindexedPins = reindexed(destination)
            setPinnedTabs(reindexedPins, for: profileId)
            return reindexedPins[safeIndex]
        case .spacePinned:
            guard let spaceId = pin.spaceId else { return nil }
            let insertedPin: ShortcutPin?
            if pin.folderId == nil {
                insertedPin = insertTopLevelSpacePinnedShortcut(pin, in: spaceId, at: targetIndex)
            } else {
                var localInsertedPin: ShortcutPin?
                withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { destination in
                    let safeIndex = max(0, min(targetIndex, destination.count))
                    destination.insert(pin, at: safeIndex)
                    localInsertedPin = destination[safeIndex].refreshed(index: safeIndex)
                }
                insertedPin = localInsertedPin
            }
            if openTargetFolder, let folderId = pin.folderId {
                openFolderIfNeeded(folderId)
            }
            return insertedPin.flatMap { inserted in
                spacePinnedShortcuts[spaceId]?.first(where: { $0.id == inserted.id })
            }
        }
    }

    @discardableResult
    func moveShortcutPin(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        return withStructuralUpdateTransaction {
            let adjustedIndex = adjustedShortcutMoveIndex(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                proposedIndex: index
            )
            removeShortcutPinFromContainers(pin)
            let movedPin = cloneShortcutPin(
                pin,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: adjustedIndex
            )
            let inserted = insertShortcutPin(
                movedPin,
                at: adjustedIndex,
                openTargetFolder: openTargetFolder
            )
            if let inserted {
                updateTransientShortcutBindings(for: inserted)
            }
            scheduleStructuralPersistence()
            return inserted
        }
    }

    @discardableResult
    func convertTabToShortcutPin(
        _ tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        return withStructuralUpdateTransaction {
            let pin = makeShortcutPin(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: targetIndex
            )
            guard let insertedPin = insertShortcutPin(
                pin,
                at: targetIndex,
                openTargetFolder: openTargetFolder
            ) else { return nil }

            if let windowId = windowIdDisplaying(tabId: tab.id) {
                convertTabToShortcutLiveInstance(tab, pin: insertedPin, in: windowId)
            } else {
                removeTab(tab.id)
            }
            scheduleStructuralPersistence()
            return insertedPin
        }
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            switch (operation.fromContainer, operation.toContainer) {
            case (.essentials, .essentials):
                return reorderEssential(pin, to: operation.toIndex)

            case (.essentials, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.essentials, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.essentials, .spaceRegular(let targetSpaceId)):
                return convertShortcutPinToRegularTab(pin, in: targetSpaceId, at: operation.toIndex)

            case (.spacePinned, .essentials),
                 (.folder, .essentials):
                guard let currentProfileId = resolvedEssentialsProfileId(for: operation) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .essential,
                    profileId: currentProfileId,
                    spaceId: nil,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .folder(let targetFolderId)),
                 (.folder, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.folder, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spaceRegular(let targetSpaceId)),
                 (.folder, .spaceRegular(let targetSpaceId)):
                removeShortcutPinFromContainers(pin)
                _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: operation.toIndex)
                scheduleStructuralPersistence()
                return true

            case (.spaceRegular, _),
                 (.none, _),
                 (_, .none):
                return false
            }
        }
    }
}

private extension TabManager {
    func adjustedShortcutMoveIndex(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        proposedIndex: Int
    ) -> Int {
        guard pin.role == role,
              pin.profileId == profileId,
              pin.spaceId == spaceId,
              pin.folderId == folderId else {
            return proposedIndex
        }

        let currentIndex: Int?
        switch role {
        case .essential:
            guard let profileId else { return proposedIndex }
            currentIndex = pinnedByProfile[profileId]?.firstIndex(where: { $0.id == pin.id })
        case .spacePinned:
            guard let spaceId else { return proposedIndex }
            if folderId == nil {
                currentIndex = topLevelSpacePinnedItems(for: spaceId).firstIndex {
                    if case .shortcut(let existingPin) = $0 {
                        return existingPin.id == pin.id
                    }
                    return false
                }
            } else {
                currentIndex = spacePinnedPins(for: spaceId)
                    .filter { $0.folderId == folderId }
                    .sorted {
                        if $0.index != $1.index { return $0.index < $1.index }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    .firstIndex(where: { $0.id == pin.id })
            }
        }

        guard currentIndex != nil else { return proposedIndex }
        return proposedIndex
    }

    func cloneShortcutPin(
        _ pin: ShortcutPin,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: pin.id,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            faviconCacheKey: pin.faviconCacheKey ?? ShortcutPin.makeFaviconCacheKey(for: pin.launchURL),
            systemIconName: pin.systemIconName,
            iconAsset: pin.iconAsset
        )
    }

    func liveShortcutEntry(for pinId: UUID) -> (windowId: UUID, tab: Tab)? {
        for (windowId, tabsByPin) in transientShortcutTabsByWindow {
            if let tab = tabsByPin[pinId] {
                return (windowId, tab)
            }
        }
        return nil
    }

    func removeShortcutPinFromContainers(_ pin: ShortcutPin) {
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
            transientShortcutTabsByWindow[existingWindowId]?.removeValue(forKey: pin.id)
            if transientShortcutTabsByWindow[existingWindowId]?.isEmpty == true {
                transientShortcutTabsByWindow.removeValue(forKey: existingWindowId)
            }
            notifyTransientShortcutStateChanged()
            existingLiveTab.clearShortcutBinding()
            existingLiveTab.spaceId = targetSpaceId
            existingLiveTab.folderId = nil
            existingLiveTab.isPinned = false
            existingLiveTab.isSpacePinned = false
            attach(existingLiveTab)
            var arr = tabsBySpace[targetSpaceId] ?? []
            let safeIndex = max(0, min(targetIndex ?? arr.count, arr.count))
            arr.insert(existingLiveTab, at: safeIndex)
            for (i, tab) in arr.enumerated() { tab.index = i }
            setTabs(arr, for: targetSpaceId)
            if let windowState = browserManager?.windowRegistry?.windows[existingWindowId] {
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
            favicon: pin.systemIconName,
            spaceId: targetSpaceId,
            index: 0,
            browserManager: browserManager
        )
        tab.favicon = pin.favicon
        tab.faviconIsTemplateGlobePlaceholder = pin.faviconIsUncachedGlobeTemplate
        attach(tab)
        var arr = tabsBySpace[targetSpaceId] ?? []
        let safeIndex = max(0, min(targetIndex ?? arr.count, arr.count))
        arr.insert(tab, at: safeIndex)
        for (i, item) in arr.enumerated() { item.index = i }
        setTabs(arr, for: targetSpaceId)
        return tab
    }
}
