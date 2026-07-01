import Foundation

extension TabManager {
    enum EssentialsCapacityPolicy {
        static let maxColumns = 3
        static let maxRows = 4
        static let maxItems = maxColumns * maxRows
    }

    struct EssentialsTargetContext {
        var windowState: BrowserWindowState?
        var spaceId: UUID?
        var profileId: UUID?

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
        var target: EssentialsTargetContext?
        var targetIndex: Int?
        var movingPinId: UUID?
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

        if let profileId = runtimeContext?.currentProfileId {
            return EssentialsTargetResolution(profileId: profileId, source: .globalFallback)
        }

        return EssentialsTargetResolution(profileId: nil, source: .unresolved)
    }

    func resolvedEssentialsProfileId(
        using context: EssentialsTargetContext? = nil
    ) -> UUID? {
        resolveEssentialsTarget(using: context).profileId
    }

    func canAddURLToEssentials(
        _ url: URL,
        using context: EssentialsTargetContext? = nil
    ) -> Bool {
        guard let profileId = resolvedEssentialsProfileId(using: context) else { return false }
        let pins = essentialPins(for: profileId)
        guard pins.count < EssentialsCapacityPolicy.maxItems else { return false }
        return pins.contains { $0.launchURL == url } == false
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
              let visibleProfileId = context?.windowState?.currentProfileId,
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
            executionProfileId: shortcutExecutionProfileId(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId
            ),
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: tab.url,
            title: tab.name
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

    func resolvedExecutionProfileId(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> UUID? {
        if let executionProfileId = pin.executionProfileId {
            return executionProfileId
        }

        switch pin.role {
        case .essential:
            return pin.profileId
        case .spacePinned:
            return (pin.spaceId ?? currentSpaceId).flatMap { spaceId in
                spaces.first(where: { $0.id == spaceId })?.profileId
            }
        }
    }

    func resolvedFaviconPartition(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> SumiFaviconPartition {
        let profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
        guard let profileId,
              let profile = runtimeContext?.profile(with: profileId)
        else {
            return .regular(profileId)
        }
        return faviconService.partition(profile: profile)
    }

    func updateTransientShortcutBindings(for pin: ShortcutPin) {
        for (windowId, tabsByPin) in transientShortcutTabsByWindow {
            if let tab = tabsByPin[pin.id] {
                tab.bindToShortcutPin(pin)
                let windowCurrentSpaceId = runtimeContext?.windowState(for: windowId)?.currentSpaceId
                tab.spaceId = resolvedLiveSpaceId(for: pin, currentSpaceId: windowCurrentSpaceId)
                tab.folderId = pin.folderId
                assignProfile(
                    resolvedExecutionProfileId(for: pin, currentSpaceId: windowCurrentSpaceId),
                    to: tab
                )
                if let windowState = runtimeContext?.windowState(for: windowId) {
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
        if let folderId = pin.folderId,
           runtimeContext?.isLiveFolder(folderId) == true {
            return nil
        }

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
        withStructuralUpdateTransaction {
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
        withStructuralUpdateTransaction {
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

            if !convertSelectedTabToShortcutLiveInstances(tab, pin: insertedPin) {
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
    func shortcutExecutionProfileId(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?
    ) -> UUID? {
        guard let tabProfileId = tab.profileId else { return nil }

        let containerProfileId: UUID?
        switch role {
        case .essential:
            containerProfileId = profileId
        case .spacePinned:
            containerProfileId = spaceId.flatMap { targetSpaceId in
                spaces.first(where: { $0.id == targetSpaceId })?.profileId
            }
        }

        return tabProfileId == containerProfileId ? nil : tabProfileId
    }

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

        guard let currentIndex else { return proposedIndex }
        return adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
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
            executionProfileId: pin.executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: pin.launchURL,
            title: pin.title,
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
            regularTabCollectionOwner.insert(existingLiveTab, in: targetSpaceId, at: targetIndex)
            if let windowState = runtimeContext?.windowState(for: existingWindowId) {
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
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        attach(tab)
        regularTabCollectionOwner.insert(tab, in: targetSpaceId, at: targetIndex)
        return tab
    }
}
