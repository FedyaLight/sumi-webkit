import Foundation

/// Owns user-level launcher pin commands: pinning tabs to essentials or a
/// space, copying, removing, updating, resetting, and reordering shortcut
/// pins in response to explicit user actions.
@MainActor
final class ShortcutPinCommandOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func pinTab(_ tab: Tab, context: TabManager.EssentialsTargetContext?) {
        tabManager.withStructuralUpdateTransaction {
            guard let insertion = tabManager.essentialsShortcutPlacementOwner.resolveInsertion(
                using: TabManager.EssentialsInsertionContext(target: context)
            ) else { return }
            if tabManager.shortcutPinCollectionStateOwner.essentialPins(for: insertion.profileId)
                .contains(where: { $0.launchURL == tab.url }) { return }

            let pin = tabManager.shortcutPinRuntimeResolutionOwner.makeShortcutPin(
                from: tab,
                role: .essential,
                profileId: insertion.profileId,
                index: insertion.index
            )
            guard let insertedPin = tabManager.shortcutPinStoreOwner.insert(pin, at: insertion.index) else { return }
            tabManager.essentialsShortcutPlacementOwner.logTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )

            if !tabManager.shortcutLiveTabOwner.convertDisplayedTabToShortcutLiveInstances(
                tab,
                pin: insertedPin,
                preferredWindowId: context?.windowState?.id
            ) {
                tabManager.removeTab(tab.id)
            }
            tabManager.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func copyShortcutPinToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: TabManager.EssentialsTargetContext?
    ) -> ShortcutPin? {
        tabManager.withStructuralUpdateTransaction {
            guard let insertion = tabManager.essentialsShortcutPlacementOwner.resolveInsertion(
                using: TabManager.EssentialsInsertionContext(target: context)
            ) else { return nil }
            if tabManager.shortcutPinCollectionStateOwner.essentialPins(for: insertion.profileId)
                .contains(where: { $0.launchURL == pin.launchURL }) {
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
            guard let insertedPin = tabManager.shortcutPinStoreOwner.insert(copiedPin, at: insertion.index) else {
                return nil
            }

            tabManager.essentialsShortcutPlacementOwner.logTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )
            tabManager.scheduleStructuralPersistence()
            return insertedPin
        }
    }

    private func copiedShortcutExecutionProfileId(
        for pin: ShortcutPin,
        targetProfileId: UUID,
        context: TabManager.EssentialsTargetContext?
    ) -> UUID? {
        let currentSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        let executionProfileId = tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        return executionProfileId == targetProfileId ? nil : executionProfileId
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        tabManager.withStructuralUpdateTransaction {
            if tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) != nil {
                tabManager.runtimeContext?.captureDeletedShortcutLauncher(pin)
            }

            tabManager.shortcutPinStoreOwner.removeFromContainers(pin)

            let cleanupResult = tabManager.shortcutLiveTabOwner.removeLiveShortcutTabs(forDeletedPinId: pin.id)
            if cleanupResult.didClearCurrentSelection {
                tabManager.runtimeContext?.validateWindowStates()
            }
            tabManager.shortcutLiveTabOwner.persistWindowSessionsForShortcutSelectionCleanup(cleanupResult)
            tabManager.scheduleStructuralPersistence()
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
        tabManager.withStructuralUpdateTransaction {
            let updatedPin = pin.updated(
                title: title,
                launchURL: launchURL,
                iconAsset: iconAsset,
                executionProfileId: executionProfileId
            )

            switch pin.role {
            case .essential:
                guard let profileId = pin.profileId,
                      var pins = tabManager.pinnedByProfile[profileId],
                      let index = pins.firstIndex(where: { $0.id == pin.id }) else {
                    return nil
                }

                pins[index] = updatedPin.refreshed(index: pin.index)
                tabManager.setPinnedTabs(tabManager.shortcutPinStoreOwner.reindexed(pins), for: profileId)
                if let inserted = tabManager.pinnedByProfile[profileId]?
                    .first(where: { $0.id == pin.id }) {
                    tabManager.shortcutLiveTabOwner.updateTransientShortcutBindings(for: inserted)
                    tabManager.scheduleStructuralPersistence()
                    return inserted
                }
            case .spacePinned:
                guard let spaceId = pin.spaceId else { return nil }
                if pin.folderId == nil {
                    let items = tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId)
                        .map { item -> TabManager.SpacePinnedTopLevelItem in
                            guard case .shortcut(let existingPin) = item, existingPin.id == pin.id else {
                                return item
                            }
                            return .shortcut(updatedPin.refreshed(index: pin.index))
                        }
                    tabManager.spacePinnedStructureOwner.applyTopLevelSpacePinnedOrder(items, for: spaceId)
                } else {
                    tabManager.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { pins in
                        if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                            pins[index] = updatedPin.refreshed(index: pin.index)
                        }
                    }
                }

                if let inserted = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) {
                    tabManager.shortcutLiveTabOwner.updateTransientShortcutBindings(for: inserted)
                    tabManager.scheduleStructuralPersistence()
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
        guard let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return nil
        }

        let liveTitle = liveTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = liveTitle.isEmpty ? pin.title : liveTitle
        let updated = tabManager.shortcutPinCommandOwner.updateShortcutPin(
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
        preserveCurrentPage: Bool
    ) -> ShortcutPin? {
        tabManager.withStructuralUpdateTransaction {
            guard let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id) else {
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
                    faviconService: tabManager.faviconService,
                    faviconImageService: tabManager.faviconImageService,
                    visitedLinkStore: tabManager.visitedLinkStore
                )
                duplicateTab.favicon = liveTab.favicon
                duplicateTab.faviconIsTemplateGlobePlaceholder = liveTab.faviconIsTemplateGlobePlaceholder
                duplicateTab.profileId = liveTab.profileId
                tabManager.attach(duplicateTab)
                var spaceTabs = tabManager.regularTabCollectionOwner.tabs(in: targetSpaceId)
                spaceTabs.append(duplicateTab)
                tabManager.setTabs(spaceTabs, for: targetSpaceId)
            }

            _ = liveTab.acceptResolvedDisplayTitle(pin.title, url: pin.launchURL)
            liveTab.url = pin.launchURL
            liveTab.loadURL(pin.launchURL)

            let updated = tabManager.shortcutPinCommandOwner.updateShortcutPin(
                pin,
                title: pin.title,
                launchURL: pin.launchURL
            )
            return updated
        }
    }

    @discardableResult
    func reorderEssential(_ pin: ShortcutPin, to index: Int) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            guard let pid = pin.profileId else { return false }
            var arr = tabManager.pinnedByProfile[pid] ?? []
            guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return false }
            let adjustedIndex = tabManager.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: index
            )
            guard adjustedIndex != currentIndex else { return false }
            if currentIndex < arr.count { arr.remove(at: currentIndex) }
            arr.insert(pin, at: max(0, min(adjustedIndex, arr.count)))
            tabManager.setPinnedTabs(tabManager.shortcutPinStoreOwner.reindexed(arr), for: pid)
            tabManager.scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    func reorderSpacePinned(_ pin: ShortcutPin, in spaceId: UUID, to index: Int) -> Bool {
        tabManager.withStructuralUpdateTransaction {
            var didReorder = false
            if pin.folderId == nil {
                didReorder = tabManager.spacePinnedStructureOwner.reorderTopLevelSpacePinnedShortcut(
                    pin,
                    in: spaceId,
                    to: index
                ) != nil
            } else {
                tabManager.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { arr in
                    guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return }
                    let adjustedIndex = tabManager.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
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
                tabManager.scheduleStructuralPersistence()
            }
            return didReorder
        }
    }

    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        tabManager.withStructuralUpdateTransaction {
            guard tabManager.spaces.contains(where: { $0.id == spaceId }) else { return }
            if tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
                .contains(where: { $0.launchURL == tab.url }) { return }

            if tab.isShortcutLiveInstance,
               let shortcutId = tab.shortcutPinId,
               let sourcePin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutId),
               sourcePin.role == .essential {
                let targetIndex = tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).count
                let detachedPin = tabManager.shortcutPinRuntimeResolutionOwner.makeShortcutPin(
                    from: tab,
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceId,
                    folderId: nil,
                    index: targetIndex
                )

                guard let insertedPin = tabManager.shortcutPinStoreOwner.insert(detachedPin, at: targetIndex) else {
                    return
                }

                tabManager.shortcutLiveTabOwner.rebindLiveShortcutTab(tab, from: sourcePin, to: insertedPin)

                tabManager.scheduleStructuralPersistence()
                return
            }

            _ = tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).count
            )
        }
    }
}
