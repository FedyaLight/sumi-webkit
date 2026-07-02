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

            let cleanupResult = removeLiveShortcutTabs(forDeletedPinId: pin.id)
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

                rebindLiveShortcutTab(tab, from: sourcePin, to: insertedPin)

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

    func folderSpaceId(for folderId: UUID) -> UUID? {
        foldersBySpace.first(where: { $0.value.contains(where: { $0.id == folderId }) })?.key
    }
}
